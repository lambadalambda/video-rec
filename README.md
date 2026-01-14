# video-suggestion

Phoenix + LiveView short‑video prototype with an evolving recommendation core.

## Web MVP

- Auth via magic link (`mix phx.gen.auth`)
- First registered user becomes admin
- Admin-only video upload (stored in `priv/static/uploads/`)
- Public TikTok-style feed at `/`

## Setup

Requirements: Elixir 1.19 / Erlang 28 (see `mise.toml`) and Postgres.

```sh
mix setup
mix phx.server
```

Open `http://localhost:5000`, register at `/users/register`, then use `/dev/mailbox` (dev only) to grab the login link. The first registered user is admin; upload at `/admin/videos/new`.

## Example videos

There’s a small sample `.mp4` in `examples/videos/` you can import:

```sh
mix videos.import examples/videos
```

## Embeddings + Transcripts (optional)

This repo includes a small Python embedding worker in `services/embedding_worker/`.

Run the worker (from the repo root so uploads resolve correctly):

```sh
# (optional) activate your venv:
# source services/embedding_worker/.venv/bin/activate
PYTHONPATH=services/embedding_worker \
UPLOADS_DIR=priv/static/uploads \
python -m uvicorn embedding_worker.main:app --reload --port 9001
```

Then run:

```sh
mix videos.transcribe
mix videos.embed_visual
```

### Remote worker (no shared uploads)

If the embedding worker runs on another machine (e.g. via Tailscale) and **does not have access to**
`priv/static/uploads`, set:

- `EMBEDDING_WORKER_BASE_URL` to the worker’s URL (e.g. `http://pc:9001`)
- `EMBEDDING_WORKER_MEDIA_MODE=upload` so mix tasks upload sampled frames / extracted audio instead of `storage_key`

Example:

```sh
EMBEDDING_WORKER_BASE_URL=http://pc:9001 EMBEDDING_WORKER_MEDIA_MODE=upload mix videos.embed_visual
EMBEDDING_WORKER_BASE_URL=http://pc:9001 EMBEDDING_WORKER_MEDIA_MODE=upload mix videos.transcribe
```

## Recommendation Core

Pure, unit-tested modules (see `lib/video_suggestion/reco/`):

- `vector.ex` (dot/norm/normalize/mean)
- `ranking.ex` (dot scoring, filtering, MMR reranking)
- `taste_profile.ex` (long-term + session vectors)
- `tagging.ex` (top-K tag scoring)

Design docs live in `docs/`.

## Dev

Run tests:

```sh
mix test
```

Format:

```sh
mix format
```
