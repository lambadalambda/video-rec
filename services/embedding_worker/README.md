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
generation `max_length`, which truncates transcripts. The worker detects this and sets
`max_new_tokens` automatically; override with `WHISPER_MAX_NEW_TOKENS` if needed.

## Run

From the repo root (so `priv/static/uploads` resolves correctly):

```sh
PYTHONPATH=services/embedding_worker \
UPLOADS_DIR=priv/static/uploads \
EMBEDDING_BACKEND=deterministic \
EMBEDDING_DIMS=64 \
python -m uvicorn embedding_worker.main:app --reload --port 9001
```

Or from `services/embedding_worker`:

```sh
UPLOADS_DIR=../../priv/static/uploads \
EMBEDDING_BACKEND=deterministic \
EMBEDDING_DIMS=64 \
python -m uvicorn embedding_worker.main:app --reload --port 9001
```

To run the real backend:

```sh
PYTHONPATH=services/embedding_worker \
UPLOADS_DIR=priv/static/uploads \
EMBEDDING_BACKEND=qwen3_vl \
QWEN3_VL_MODEL=Qwen/Qwen3-VL-Embedding-2B \
EMBEDDING_DIMS=512 \
TRANSCRIBE_ENABLED=1 \
WHISPER_MODEL=small \
python -m uvicorn embedding_worker.main:app --reload --port 9001
```

## API

- `POST /v1/transcribe/video` → `{storage_key}` → `{transcript}` (requires `requirements-whisper.txt`)
- `POST /v1/embed/video` → `{storage_key, caption?, dims?, transcribe?}` → `{version, dims, embedding, transcript?}`

## Test

```sh
pytest
```
