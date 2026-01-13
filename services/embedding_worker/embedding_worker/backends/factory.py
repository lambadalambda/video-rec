from typing import Optional

from ..config import Settings
from .base import EmbeddingBackend
from .deterministic import DeterministicBackend

_cached_backend: Optional[EmbeddingBackend] = None
_cached_key: Optional[str] = None


def get_backend(settings: Settings) -> EmbeddingBackend:
    global _cached_backend
    global _cached_key

    if settings.backend == "deterministic":
        return DeterministicBackend()

    if settings.backend == "qwen3_vl":
        key = (
            "qwen3_vl:"
            f"{settings.qwen_model}:"
            f"{settings.qwen_device}:"
            f"{settings.qwen_max_length}:"
            f"{settings.qwen_video_fps}:"
            f"{settings.qwen_video_max_frames}:"
            f"{settings.transcribe_enabled}:"
            f"{settings.whisper_backend}:"
            f"{settings.whisper_model}:"
            f"{settings.whisper_device}:"
            f"{settings.whisper_language}"
        )
        if _cached_backend is None or _cached_key != key:
            from .qwen3_vl import Qwen3VLBackend

            _cached_backend = Qwen3VLBackend(
                model_name_or_path=settings.qwen_model,
                device=settings.qwen_device,
                max_length=settings.qwen_max_length,
                video_fps=settings.qwen_video_fps,
                video_max_frames=settings.qwen_video_max_frames,
                transcribe_enabled=settings.transcribe_enabled,
                whisper_backend=settings.whisper_backend,
                whisper_model=settings.whisper_model,
                whisper_device=settings.whisper_device,
                whisper_language=settings.whisper_language,
            )
            _cached_key = key

        return _cached_backend

    raise NotImplementedError(f"Unknown backend: {settings.backend}")
