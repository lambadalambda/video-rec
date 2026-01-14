# Embedding Worker (Python)

Small HTTP service that computes video embeddings (for now: deterministic placeholder) and will later run the real multimodal embedding pipeline.

## Setup

Requires Python 3.9+.

```sh
cd services/embedding_worker
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt
```

## Enable Qwen3-VL embeddings (real backend)

```sh
pip install -r requirements-qwen.txt
```

### Qwen3-VL quantization (CUDA only)

To run larger Qwen3-VL models (e.g. 8B) in less VRAM/RAM, the worker supports weight quantization via bitsandbytes:

```sh
# CUDA-only deps:
pip install -r requirements-qwen-cuda.txt

# at runtime:
QWEN_QUANTIZATION=int4  # or: int8
```

### Qwen3-VL microbatching (better GPU utilization)

If the worker receives many concurrent embed requests (e.g. from `mix videos.embed_visual`), it can combine them
into a single forward pass to keep the GPU busier:

```sh
QWEN_BATCH_MAX_SIZE=8
QWEN_BATCH_WAIT_MS=20
```

## Enable Whisper transcription

```sh
pip install -r requirements-whisper.txt
```

### Use Transformers Whisper (Distil-Whisper)

The worker can also run Whisper via 🤗 Transformers:

```sh
WHISPER_BACKEND=transformers
WHISPER_MODEL=distil-whisper/distil-large-v3
```

When using the Transformers backend with video files (e.g. `.mp4`), the worker extracts audio
with `ffmpeg`, so make sure it is installed and available on `PATH` (or set `FFMPEG_BIN`).

Some Whisper model repos (notably `openai/whisper-large-v3-turbo`) ship with a very low default
generation `max_length`, which truncates transcripts. The worker detects this and sets a safe
`max_new_tokens` automatically; override with `WHISPER_MAX_NEW_TOKENS` if needed.

On Apple Silicon, the Transformers backend defaults to `float32` to avoid degraded transcripts on MPS.
Override with `WHISPER_DTYPE=fp16|fp32|bf16` if you want.

## Run

From the repo root (so `priv/static/uploads` resolves correctly):

```sh
PYTHONPATH=services/embedding_worker \
UPLOADS_DIR=priv/static/uploads \
EMBEDDING_BACKEND=deterministic \
EMBEDDING_DIMS=1536 \
python -m uvicorn embedding_worker.main:app --reload --port 9001
```

Or from `services/embedding_worker`:

```sh
UPLOADS_DIR=../../priv/static/uploads \
EMBEDDING_BACKEND=deterministic \
EMBEDDING_DIMS=1536 \
python -m uvicorn embedding_worker.main:app --reload --port 9001
```

To see more detail, run uvicorn with `--log-level debug`.

To run the real backend:

```sh
PYTHONPATH=services/embedding_worker \
UPLOADS_DIR=priv/static/uploads \
EMBEDDING_BACKEND=qwen3_vl \
QWEN3_VL_MODEL=Qwen/Qwen3-VL-Embedding-2B \
EMBEDDING_DIMS=1536 \
TRANSCRIBE_ENABLED=1 \
WHISPER_MODEL=small \
python -m uvicorn embedding_worker.main:app --reload --port 9001
```

### Qwen3-VL video sampling

By default, the worker tries to keep Qwen3-VL video memory usage bounded by sampling ~10 frames across the full video duration:

- `QWEN_VIDEO_TARGET_FRAMES` (default `10`): target frames per video (set to `0` to disable).
- `QWEN_VIDEO_MAX_FRAMES` (default `64`): hard cap on frames.
- `QWEN_VIDEO_FPS` (default `1.0`): fallback sampling rate when target frames is disabled (or duration can't be probed).

When target frames is enabled, the worker uses `ffprobe` to estimate the video duration (set `FFPROBE_BIN` if needed). If `ffprobe` is unavailable, it still applies the `QWEN_VIDEO_TARGET_FRAMES` cap.

If `qwen-vl-utils` falls back to the `torchvision` video reader, it will load the full video into memory before sampling. To avoid huge time/RAM spikes, the worker automatically extracts the sampled frames with `ffmpeg` in that case. Override with `QWEN_VIDEO_FRAME_EXTRACTOR=ffmpeg|native|auto`.

## API

- `POST /v1/transcribe/video` → `{storage_key}` → `{transcript}` (requires `requirements-whisper.txt`)
- `POST /v1/transcribe/audio` → multipart `{audio}` → `{transcript}` (requires `requirements-whisper.txt`)
- `POST /v1/embed/video` → `{storage_key, caption?, dims?, transcribe?}` → `{version, dims, embedding, transcript?}`
- `POST /v1/embed/video_frames` → multipart `{frames[], caption?, dims?, transcript?}` → `{version, dims, embedding, transcript?}`
- `POST /v1/embed/text` → `{text, dims?}` → `{version, dims, embedding}`

## Test

```sh
pytest
```

## Docker (GPU)

This repo ships a Dockerfile intended for running on an NVIDIA GPU machine (e.g. WSL2 + 4090).

Build locally:

```sh
cd services/embedding_worker
docker build -t embedding-worker .
docker run --rm -p 9001:9001 --gpus all embedding-worker
```

Or run via `compose.yaml` (edit `EMBEDDING_WORKER_IMAGE` / env vars as needed):

```sh
cd services/embedding_worker
EMBEDDING_WORKER_IMAGE=ghcr.io/OWNER/video-suggestion-embedding-worker:latest docker compose up -d
```

If you prefer a file, copy `.env.example` to `.env` and run compose (Docker will auto-load `.env` in this folder):

```sh
cd services/embedding_worker
cp .env.example .env
docker compose up -d
```

Example: run the 8B model quantized:

```sh
cd services/embedding_worker
export QWEN3_VL_MODEL=Qwen/Qwen3-VL-Embedding-8B
export QWEN_QUANTIZATION=int4
docker compose up -d
```
