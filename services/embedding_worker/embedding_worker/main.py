from fastapi import FastAPI, HTTPException

from .api_models import VideoEmbedRequest, VideoEmbedResponse
from .backends import get_backend
from .backends.deterministic import safe_storage_key_to_path
from .config import get_settings

app = FastAPI(title="Embedding Worker", version="0.1.0")


@app.get("/healthz")
def healthz():
    settings = get_settings()
    return {"status": "ok", "backend": settings.backend}


@app.post("/v1/embed/video", response_model=VideoEmbedResponse)
def embed_video(req: VideoEmbedRequest):
    settings = get_settings()

    try:
        backend = get_backend(settings)
    except NotImplementedError:
        raise HTTPException(status_code=501, detail="backend_not_implemented")

    try:
        path = safe_storage_key_to_path(settings.uploads_dir, req.storage_key)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    if not path.exists():
        raise HTTPException(status_code=404, detail="video_not_found")

    dims = req.dims or settings.dims
    result = backend.embed_video(path=str(path), caption=req.caption or "", dims=dims)

    return VideoEmbedResponse(version=result.version, dims=dims, embedding=result.embedding)
