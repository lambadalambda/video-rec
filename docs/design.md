# TikTok-Style Short-Video App with Multimodal Embeddings (Qwen3‑VL‑Embedding)

**Design Doc (v0.1) — Elixir/Phoenix + Python GPU embedding service**

> Scope: a “TikTok clone” focusing on (1) upload/playback, (2) a For You feed powered by multimodal embeddings, and (3) lightweight auto-tagging and search.  
> Target scale for v0: **1 GPU**, **~1k–100k videos**, and typical consumer traffic for an MVP.

## Milestones (working checklists)

- `docs/milestones/01-vector-math.md`
- `docs/milestones/02-ranking-diversity.md`
- `docs/milestones/03-user-taste-profiles.md`
- `docs/milestones/04-auto-tagging.md`
- `docs/milestones/05-api-and-pipeline.md`

---

## 1) Goals

- **Fast, addictive feed loop**: vertical video playback with swipe navigation, autoplay, and smooth prefetching.
- **Content-based recommendations from day 1** (no collaborative data needed):
  - Per-video embeddings from **visual** + **audio transcript** (Whisper).
  - Per-user taste vectors updated from watch/click/like signals.
- **Auto-tagging** using a predefined tag taxonomy (your tags), to support:
  - Search/filtering (“cats”, “dogs”, “cooking”, “dance”, …)
  - Explainability (“recommended because: cats, pets, cute animals”)
- **Operational simplicity**:
  - Elixir/Phoenix for app server + real-time UX.
  - A single Python “Embedding Worker” service running on one GPU (NVIDIA) or Apple Silicon GPU (MPS) for dev.

---

## 2) Non-goals (for v0)

- Full-blown collaborative filtering, large-scale graph features, or deep user-to-user similarity.
- Live streaming, Duet/Stitch editing, complex creator tooling.
- Perfect moderation & copyright detection (we’ll add hooks and basic scanning, but not solve everything).

---

## 3) High-level architecture

```
            ┌─────────────────────────────┐
            │  Phoenix (Web/API + LiveView│
            │  or JSON API for mobile)     │
            └──────────────┬──────────────┘
                           │
                     (DB + Queue)
                           │
┌───────────────┐   ┌──────▼────────┐      ┌─────────────────────┐
│ Object Storage │   │ Postgres +     │      │ Redis (maybe later)     │
│ (S3/MinIO) (maybe later)    │   │ pgvector       │      │ session/profile cache│
└──────┬────────┘   └──────┬─────────┘      └─────────────────────┘
       │                    │
       │           ┌────────▼────────┐
       │           │ Oban jobs        │
       │           │ (transcode,      │
       │           │ embed, tag)      │
       │           └────────┬────────┘
       │                    │ HTTP/gRPC
┌──────▼────────┐           │
│ FFmpeg worker  │     ┌────▼──────────────────────────┐
│ (transcode,    │     │ Python Embedding Service       │
│ thumbnails)    │     │ - Whisper ASR                  │
└───────────────┘     │ - Qwen3‑VL‑Embedding (GPU)     │
                      │ - frame sampling + pooling     │
                      └───────────────────────────────┘
```

**Key idea:** Phoenix owns product logic and persistence; embedding is an external service for GPU-heavy work.

---

## 4) Core services

### 4.1 Phoenix app (Elixir)

Responsibilities:

- Auth (email/OTP, OAuth) + device/session management
- Upload endpoints (direct-to-S3 presigned) + metadata
- Playback/feed endpoints + interaction logging
- Recommendation assembly (candidate retrieval + rerank)
- Creator profile + video pages, comments/likes (basic)

Suggested Phoenix stack:

- **Phoenix LiveView** for web MVP; mobile can use the same JSON API later.
- **Oban** (Postgres-backed jobs) for background tasks.
- **Ecto** for persistence.

### 4.2 Media pipeline

- **Storage**: Local, later maybe S3-compatible (AWS S3 / Cloudflare R2 / MinIO).
- **FFmpeg**:
  - transcode to H.264/AAC MP4 (or HLS for scale)
  - extract thumbnails + a small set of sampled frames
  - extract audio track (wav/flac for ASR)

### 4.3 Embedding service (Python, GPU)

Responsibilities:

- Whisper transcription (recommend `faster-whisper` for speed; standard `whisper` also works)
- Generate multimodal embeddings via **Qwen3‑VL‑Embedding**:
  - text embedding for transcript
  - image/video embedding for sampled frames (or video input when supported)
- Return:
  - `video_embedding` (primary vector used for similarity)
  - `transcript_embedding` (optional for debugging/analysis)
  - `tag_scores` (optional: top tags and similarities)

Deployment modes:

- **NVIDIA GPU server**: run model with **vLLM “pooling”** runner for throughput.
- **MacBook Pro**: run Transformers with **MPS** (slower but workable for dev and small batches).

---

## 5) Embedding strategy (practical + robust)

### 5.1 Inputs per video

For each uploaded video (30s–2m):

- **Visual**: sample `N=12–24` frames uniformly (or 1 fps capped).
- **Audio**: transcribe to text (Whisper).
- **Optional**: caption-like metadata (title/description/hashtags) appended to transcript.

### 5.2 Producing a single vector

We keep _one main embedding per video_ to simplify retrieval.

1. Embed transcript:

- `e_text = embed_text(transcript)`

2. Embed visuals:

- For each sampled frame:
  - `e_i = embed_image(frame_i)`
- Pool:
  - `e_vis = normalize(mean(e_i))`

3. Combine:

- `e_video = normalize( w_vis * e_vis + w_text * e_text )`
- Defaults: `w_vis=0.7`, `w_text=0.3` (tune per content type).

**Why not just embed “video” directly?**  
Video modality support is great, but frame-sampling is simple, stable, and easy to scale; you can switch later.

### 5.3 Embedding dimensionality

Qwen3‑VL‑Embedding supports user-defined output dimensions (Matryoshka-style). For MVP:

- store **512-d** or **1024-d** vectors (smaller = faster DB index, cheaper compute)
- keep “full” dims only if you benchmark and need it.

---

## 6) Data model (Postgres)

Minimal tables:

- `users(id, …)`
- `videos(id, user_id, caption, status, created_at, …)`
- `video_assets(video_id, original_url, mp4_url, hls_url?, thumbnail_url, duration_ms, …)`
- `video_embeddings(video_id, embedding vector(<D>), embedding_version, created_at)`
- `tags(id, slug, display_name)` (your curated list)
- `video_tags(video_id, tag_id, score)` (auto-assigned top-K tags)
- `interactions(id, user_id, video_id, event_type, watch_ms, liked?, created_at)`
  - `event_type`: impression, play, pause, finish, like, share, skip

- `user_profiles(user_id, u_long vector(<D>), S_long bytea/json, W_long float, updated_at)`
  - For simplicity you can store only `u_long` and maintain S/W in app memory; for correctness, persist S/W.

**Vector search option A (simple):** Postgres + `pgvector`  
**Option B (future):** Qdrant/Milvus if you outgrow Postgres or want ANN tuning.

---

## 7) Recommendation design

### 7.1 User representation: long-term + session intent

Maintain two vectors:

**Long-term taste (slow):** running weighted mean over positive engagements.

- Updated on “strong positives” (watch ≥ 40%, like, favorite, rewatch).

**Session taste (fast):** exponential moving average (EMA) within a session.

- Updated quickly from recent behavior to capture “today I want dogs.”

Blend at request time:

- `u = normalize((1-γ) * u_long + γ * u_sess)`
- `γ` increases with within-session evidence (`W_sess`) so the first click doesn’t hijack the feed.

Session state storage:

- later maybe in Redis with TTL (e.g., 30–60 min), keyed by `user_id:session_id`.
- if Redis is not used, store session profile in Phoenix in-memory cache (single node) for MVP.

### 7.2 Candidate generation

For a feed request:

1. Determine `u` (combined vector).
2. Retrieve top-N candidates by cosine similarity (`u · e_video`):
   - with `pgvector`: `ORDER BY embedding <#> u` (inner product) or cosine operator depending on schema.
3. Filter:
   - exclude already-seen/blocked
   - age limits, language, safety flags
4. Mix-in exploration:
   - e.g., 80% personalized, 20% “trending” or “diverse within top 500”.

### 7.3 Reranking and diversity

A simple rerank that works well:

- Start with top similarity
- Apply **MMR-like** selection to avoid near-duplicates (don’t pick 10 almost-identical cat videos)
- Optional hard constraints: max 2 per creator per page

### 7.4 Cold start

- New user: recommend from trending + a few broad clusters (pet/cooking/sports/etc.)
- New video: use its embedding to place it into clusters and as a candidate for similar-video pages

---

## 8) Auto-tagging (your tag list)

Given your curated tags `T = {t1..tm}`:

1. Precompute embeddings for each tag phrase (and synonyms), e.g.:
   - “cat”, “cats”, “kitten”, “cute cat”
2. For each video embedding `e_video`:
   - `score_j = e_video · e_tag_j`
3. Store top-K tags in `video_tags` with scores.

This yields:

- consistent taxonomy
- fast browsing/search filters
- simple explanations in the UI

---

## 9) APIs (sketch)

- `POST /api/videos` → create upload + presigned URL
- `POST /api/videos/:id/complete` → triggers transcode + embed job
- `GET /api/feed?cursor=…` → returns list of videos
- `POST /api/interactions` → batch events (watch time, likes)
- `GET /api/videos/:id/similar` → nearest neighbors by vector search
- `GET /api/search?tag=cats` → tag filter + optional vector query

---

## 9.5) Quick ingestion

- Add an ability to quickly ingest a bunch of videos from a local folder, or from links on a website (like 4chan.org/wsg)

## 10) Job orchestration (Oban)

Pipeline for each uploaded video:

1. `TranscodeJob(video_id)`
   - ffmpeg transcode + thumbnail + frame sampling + audio extract
2. `TranscribeJob(video_id)`
   - Whisper on audio → transcript
3. `EmbedJob(video_id)`
   - call Embedding Service → `e_video` (+ optional e_text/e_vis)
4. `TagJob(video_id)`
   - compute/store top-K tags
5. `PublishJob(video_id)`
   - mark video status = “ready”

Failures:

- retry with exponential backoff
- degrade gracefully (publish without tags if TagJob fails)

---

## 11) Deployment notes (1 GPU)

**Embedding service choices**

- **Throughput (NVIDIA):** vLLM pooling runner is ideal for batching embeddings.
- **Simplicity:** Transformers + Torch is easiest; batch requests from queue.

**Batching**

- process in batches (e.g., 8–32 videos) to keep GPU busy
- cache tag embeddings in memory

**Resource guardrails**

- cap max video length and max resolution in transcode
- cap transcript length (e.g., first N tokens or summarize)

---

## 12) Milestones (MVP path)

1. **Week 1–2:** Upload → transcode → playback feed (chronological)
2. **Week 2–3:** Whisper + embeddings stored; “Similar videos” page
3. **Week 3–4:** Personalized feed (u_long + u_sess) + basic diversity
4. **Week 4+:** Auto-tags + tag search + explanation UI + A/B tuning

---

## Appendix: Implementation tips

- Use an **“embedding_version”** field so you can re-embed later (new model, new weights).
- Normalize vectors consistently (store L2-normalized vectors so dot product = cosine).
- Keep interaction logging **append-only**; build profiles from the event stream.
- Consider a two-stage retrieval later:
- embedding recall → Qwen3‑VL‑Reranker for precision (optional upgrade).
