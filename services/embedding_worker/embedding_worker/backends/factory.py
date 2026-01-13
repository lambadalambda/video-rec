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
        key = f"qwen3_vl:{settings.qwen_model}"
        if _cached_backend is None or _cached_key != key:
            from .qwen3_vl import Qwen3VLBackend

            _cached_backend = Qwen3VLBackend(model_name_or_path=settings.qwen_model)
            _cached_key = key

        return _cached_backend

    raise NotImplementedError(f"Unknown backend: {settings.backend}")

