from fastapi import FastAPI, HTTPException

from .api_models import (
    VideoEmbedRequest,
    VideoEmbedResponse,
    VideoTranscribeRequest,
    VideoTranscribeResponse,
)
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
    try:
        result = backend.embed_video(
            path=str(path),
            caption=req.caption or "",
            dims=dims,
            transcribe=req.transcribe,
        )
    except (ModuleNotFoundError, ImportError) as e:
        raise HTTPException(status_code=501, detail="backend_dependencies_missing") from e

    return VideoEmbedResponse(
        version=result.version, dims=dims, embedding=result.embedding, transcript=result.transcript
    )


@app.post("/v1/transcribe/video", response_model=VideoTranscribeResponse)
def transcribe_video(req: VideoTranscribeRequest):
    settings = get_settings()

    try:
        path = safe_storage_key_to_path(settings.uploads_dir, req.storage_key)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    if not path.exists():
        raise HTTPException(status_code=404, detail="video_not_found")

    try:
        from .transcription import get_openai_whisper_transcriber

        transcriber = get_openai_whisper_transcriber(
            model_name=settings.whisper_model,
            device=settings.whisper_device,
            language=settings.whisper_language,
        )

        transcript = transcriber.transcribe(path=str(path))
    except (ModuleNotFoundError, ImportError) as e:
        raise HTTPException(status_code=501, detail="backend_dependencies_missing") from e

    return VideoTranscribeResponse(transcript=transcript or "")
