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

## Run

From the repo root (so `priv/static/uploads` resolves correctly):

```sh
UPLOADS_DIR=priv/static/uploads \
EMBEDDING_BACKEND=deterministic \
EMBEDDING_DIMS=64 \
python -m uvicorn embedding_worker.main:app --reload --port 9001
```

## Test

```sh
pytest
```

