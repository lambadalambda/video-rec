import logging
import os
import tempfile
import time
import uuid
from typing import Optional

from fastapi import FastAPI, File, Form, HTTPException, UploadFile

from .api_models import (
    TextEmbedRequest,
    TextEmbedResponse,
    VideoEmbedRequest,
    VideoEmbedResponse,
    VideoTranscribeRequest,
    VideoTranscribeResponse,
)
from .backends import get_backend
from .backends.deterministic import safe_storage_key_to_path
from .config import get_settings

app = FastAPI(title="Embedding Worker", version="0.1.0")
logger = logging.getLogger(__name__)


@app.get("/healthz")
def healthz():
    settings = get_settings()
    return {"status": "ok", "backend": settings.backend}


@app.post("/v1/embed/video", response_model=VideoEmbedResponse)
def embed_video(req: VideoEmbedRequest):
    settings = get_settings()
    req_id = uuid.uuid4().hex[:8]
    started = time.monotonic()

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
    logger.info(
        "embed_video start req_id=%s backend=%s storage_key=%s dims=%s transcribe=%s caption_len=%d",
        req_id,
        settings.backend,
        req.storage_key,
        dims,
        req.transcribe,
        len(req.caption or ""),
    )

    try:
        result = backend.embed_video(
            path=str(path),
            caption=req.caption or "",
            dims=dims,
            transcribe=req.transcribe,
        )
    except (ModuleNotFoundError, ImportError) as e:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        logger.exception("embed_video deps_missing req_id=%s elapsed_ms=%d", req_id, elapsed_ms)
        raise HTTPException(status_code=501, detail="backend_dependencies_missing") from e
    except Exception:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        logger.exception("embed_video failed req_id=%s elapsed_ms=%d", req_id, elapsed_ms)
        raise

    elapsed_ms = int((time.monotonic() - started) * 1000)
    transcript_len = len(result.transcript or "")
    logger.info(
        "embed_video done req_id=%s version=%s dims=%s transcript_len=%d elapsed_ms=%d",
        req_id,
        result.version,
        dims,
        transcript_len,
        elapsed_ms,
    )

    return VideoEmbedResponse(
        version=result.version, dims=dims, embedding=result.embedding, transcript=result.transcript
    )


@app.post("/v1/embed/video_frames", response_model=VideoEmbedResponse)
def embed_video_frames(
    frames: list[UploadFile] = File(...),
    caption: str = Form(""),
    dims: Optional[int] = Form(None),
    transcript: Optional[str] = Form(None),
):
    settings = get_settings()
    req_id = uuid.uuid4().hex[:8]
    started = time.monotonic()

    try:
        backend = get_backend(settings)
    except NotImplementedError:
        raise HTTPException(status_code=501, detail="backend_not_implemented")

    dims = dims or settings.dims

    frame_bytes: list[bytes] = []
    for item in frames or []:
        try:
            raw = item.file.read()
        except Exception:
            raw = None
        if raw:
            frame_bytes.append(raw)

    if not frame_bytes:
        raise HTTPException(status_code=400, detail="frames_empty")

    transcript_len = len(transcript or "")
    logger.info(
        "embed_video_frames start req_id=%s backend=%s frames=%d dims=%s transcript=%s caption_len=%d",
        req_id,
        settings.backend,
        len(frame_bytes),
        dims,
        transcript_len > 0,
        len(caption or ""),
    )

    try:
        result = backend.embed_video_frames(
            frames=frame_bytes,
            caption=caption or "",
            dims=dims,
            transcript=transcript,
        )
    except NotImplementedError as e:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        logger.exception("embed_video_frames not_implemented req_id=%s elapsed_ms=%d", req_id, elapsed_ms)
        raise HTTPException(status_code=501, detail="backend_not_implemented") from e
    except (ModuleNotFoundError, ImportError) as e:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        logger.exception("embed_video_frames deps_missing req_id=%s elapsed_ms=%d", req_id, elapsed_ms)
        raise HTTPException(status_code=501, detail="backend_dependencies_missing") from e
    except ValueError as e:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        logger.exception("embed_video_frames bad_request req_id=%s elapsed_ms=%d", req_id, elapsed_ms)
        raise HTTPException(status_code=400, detail=str(e)) from e
    except Exception:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        logger.exception("embed_video_frames failed req_id=%s elapsed_ms=%d", req_id, elapsed_ms)
        raise

    elapsed_ms = int((time.monotonic() - started) * 1000)
    transcript_len = len(result.transcript or "")
    logger.info(
        "embed_video_frames done req_id=%s version=%s dims=%s transcript_len=%d elapsed_ms=%d",
        req_id,
        result.version,
        dims,
        transcript_len,
        elapsed_ms,
    )

    return VideoEmbedResponse(
        version=result.version, dims=dims, embedding=result.embedding, transcript=result.transcript
    )


@app.post("/v1/embed/text", response_model=TextEmbedResponse)
def embed_text(req: TextEmbedRequest):
    settings = get_settings()
    req_id = uuid.uuid4().hex[:8]
    started = time.monotonic()

    try:
        backend = get_backend(settings)
    except NotImplementedError:
        raise HTTPException(status_code=501, detail="backend_not_implemented")

    dims = req.dims or settings.dims
    logger.info(
        "embed_text start req_id=%s backend=%s dims=%s text_len=%d",
        req_id,
        settings.backend,
        dims,
        len(req.text or ""),
    )

    try:
        result = backend.embed_text(text=req.text or "", dims=dims)
    except NotImplementedError as e:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        logger.exception("embed_text not_implemented req_id=%s elapsed_ms=%d", req_id, elapsed_ms)
        raise HTTPException(status_code=501, detail="backend_not_implemented") from e
    except (ModuleNotFoundError, ImportError) as e:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        logger.exception("embed_text deps_missing req_id=%s elapsed_ms=%d", req_id, elapsed_ms)
        raise HTTPException(status_code=501, detail="backend_dependencies_missing") from e
    except ValueError as e:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        logger.exception("embed_text bad_request req_id=%s elapsed_ms=%d", req_id, elapsed_ms)
        raise HTTPException(status_code=400, detail=str(e)) from e
    except Exception:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        logger.exception("embed_text failed req_id=%s elapsed_ms=%d", req_id, elapsed_ms)
        raise

    elapsed_ms = int((time.monotonic() - started) * 1000)
    logger.info(
        "embed_text done req_id=%s version=%s dims=%s elapsed_ms=%d",
        req_id,
        result.version,
        dims,
        elapsed_ms,
    )

    return TextEmbedResponse(version=result.version, dims=dims, embedding=result.embedding)


@app.post("/v1/transcribe/audio", response_model=VideoTranscribeResponse)
def transcribe_audio(audio: UploadFile = File(...)):
    settings = get_settings()
    req_id = uuid.uuid4().hex[:8]
    started = time.monotonic()

    suffix = ".wav"
    if audio and audio.filename:
        _, ext = os.path.splitext(audio.filename)
        if ext:
            suffix = ext

    tmp_path = None
    try:
        fd, tmp_path = tempfile.mkstemp(prefix="embedding_worker_upload_", suffix=suffix)
        os.close(fd)

        raw = audio.file.read()
        with open(tmp_path, "wb") as f:
            f.write(raw)

        logger.info(
            "transcribe_audio start req_id=%s backend=%s model=%s bytes=%d",
            req_id,
            settings.whisper_backend,
            settings.whisper_model,
            len(raw or b""),
        )

        from .transcription import get_whisper_transcriber

        transcriber = get_whisper_transcriber(
            backend=settings.whisper_backend,
            model_name=settings.whisper_model,
            device=settings.whisper_device,
            language=settings.whisper_language,
        )

        transcript = transcriber.transcribe(path=str(tmp_path))
    except (ModuleNotFoundError, ImportError) as e:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        logger.exception("transcribe_audio deps_missing req_id=%s elapsed_ms=%d", req_id, elapsed_ms)
        raise HTTPException(status_code=501, detail="backend_dependencies_missing") from e
    except NotImplementedError as e:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        logger.exception("transcribe_audio not_implemented req_id=%s elapsed_ms=%d", req_id, elapsed_ms)
        raise HTTPException(status_code=501, detail="backend_not_implemented") from e
    except RuntimeError as e:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        logger.exception("transcribe_audio failed req_id=%s elapsed_ms=%d", req_id, elapsed_ms)
        detail = str(e)
        status = 501 if detail.startswith("ffmpeg_") else 500
        raise HTTPException(status_code=status, detail=detail) from e
    finally:
        if tmp_path is not None:
            try:
                os.remove(tmp_path)
            except OSError:
                pass

    elapsed_ms = int((time.monotonic() - started) * 1000)
    logger.info(
        "transcribe_audio done req_id=%s transcript_len=%d elapsed_ms=%d",
        req_id,
        len(transcript or ""),
        elapsed_ms,
    )

    return VideoTranscribeResponse(transcript=transcript or "")


@app.post("/v1/transcribe/video", response_model=VideoTranscribeResponse)
def transcribe_video(req: VideoTranscribeRequest):
    settings = get_settings()
    req_id = uuid.uuid4().hex[:8]
    started = time.monotonic()

    try:
        path = safe_storage_key_to_path(settings.uploads_dir, req.storage_key)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    if not path.exists():
        raise HTTPException(status_code=404, detail="video_not_found")

    logger.info(
        "transcribe_video start req_id=%s backend=%s model=%s storage_key=%s",
        req_id,
        settings.whisper_backend,
        settings.whisper_model,
        req.storage_key,
    )

    try:
        from .transcription import get_whisper_transcriber

        transcriber = get_whisper_transcriber(
            backend=settings.whisper_backend,
            model_name=settings.whisper_model,
            device=settings.whisper_device,
            language=settings.whisper_language,
        )

        transcript = transcriber.transcribe(path=str(path))
    except (ModuleNotFoundError, ImportError) as e:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        logger.exception("transcribe_video deps_missing req_id=%s elapsed_ms=%d", req_id, elapsed_ms)
        raise HTTPException(status_code=501, detail="backend_dependencies_missing") from e
    except NotImplementedError as e:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        logger.exception("transcribe_video not_implemented req_id=%s elapsed_ms=%d", req_id, elapsed_ms)
        raise HTTPException(status_code=501, detail="backend_not_implemented") from e
    except RuntimeError as e:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        logger.exception("transcribe_video failed req_id=%s elapsed_ms=%d", req_id, elapsed_ms)
        detail = str(e)
        status = 501 if detail.startswith("ffmpeg_") else 500
        raise HTTPException(status_code=status, detail=detail) from e

    elapsed_ms = int((time.monotonic() - started) * 1000)
    logger.info(
        "transcribe_video done req_id=%s transcript_len=%d elapsed_ms=%d",
        req_id,
        len(transcript or ""),
        elapsed_ms,
    )

    return VideoTranscribeResponse(transcript=transcript or "")
