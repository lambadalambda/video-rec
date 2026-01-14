import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Optional


def _env_bool(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default

    raw = raw.strip().lower()
    if raw in ("1", "true", "t", "yes", "y", "on"):
        return True
    if raw in ("0", "false", "f", "no", "n", "off"):
        return False

    return default


@dataclass(frozen=True)
class Settings:
    uploads_dir: Path
    backend: str
    dims: int
    qwen_model: str
    qwen_device: str
    qwen_max_length: int
    qwen_quantization: str
    qwen_batch_max_size: int
    qwen_batch_wait_ms: int
    qwen_video_fps: float
    qwen_video_max_frames: int
    qwen_video_target_frames: int
    transcribe_enabled: bool
    whisper_backend: str
    whisper_model: str
    whisper_device: str
    whisper_language: Optional[str]


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    uploads_dir = Path(os.environ.get("UPLOADS_DIR", "priv/static/uploads")).resolve()
    backend = os.environ.get("EMBEDDING_BACKEND", "deterministic")
    dims = int(os.environ.get("EMBEDDING_DIMS", "1536"))
    qwen_model = os.environ.get("QWEN3_VL_MODEL", "Qwen/Qwen3-VL-Embedding-2B")
    qwen_device = os.environ.get("QWEN_DEVICE", "auto")
    qwen_max_length = int(os.environ.get("QWEN_MAX_LENGTH", "8192"))
    qwen_quantization = (os.environ.get("QWEN_QUANTIZATION") or "none").strip().lower()
    qwen_batch_max_size = int(os.environ.get("QWEN_BATCH_MAX_SIZE", "1"))
    qwen_batch_wait_ms = int(os.environ.get("QWEN_BATCH_WAIT_MS", "10"))
    qwen_video_fps = float(os.environ.get("QWEN_VIDEO_FPS", "1.0"))
    qwen_video_max_frames = int(os.environ.get("QWEN_VIDEO_MAX_FRAMES", "64"))
    qwen_video_target_frames = int(os.environ.get("QWEN_VIDEO_TARGET_FRAMES", "10"))

    transcribe_enabled = _env_bool("TRANSCRIBE_ENABLED", True)
    whisper_backend = os.environ.get("WHISPER_BACKEND", "openai")
    whisper_model = os.environ.get("WHISPER_MODEL", "small")
    whisper_device = os.environ.get("WHISPER_DEVICE", "auto")
    whisper_language = os.environ.get("WHISPER_LANGUAGE")

    return Settings(
        uploads_dir=uploads_dir,
        backend=backend,
        dims=dims,
        qwen_model=qwen_model,
        qwen_device=qwen_device,
        qwen_max_length=qwen_max_length,
        qwen_quantization=qwen_quantization,
        qwen_batch_max_size=qwen_batch_max_size,
        qwen_batch_wait_ms=qwen_batch_wait_ms,
        qwen_video_fps=qwen_video_fps,
        qwen_video_max_frames=qwen_video_max_frames,
        qwen_video_target_frames=qwen_video_target_frames,
        transcribe_enabled=transcribe_enabled,
        whisper_backend=whisper_backend,
        whisper_model=whisper_model,
        whisper_device=whisper_device,
        whisper_language=whisper_language,
    )
