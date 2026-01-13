import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    uploads_dir: Path
    backend: str
    dims: int
    qwen_model: str


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    uploads_dir = Path(os.environ.get("UPLOADS_DIR", "priv/static/uploads")).resolve()
    backend = os.environ.get("EMBEDDING_BACKEND", "deterministic")
    dims = int(os.environ.get("EMBEDDING_DIMS", "64"))
    qwen_model = os.environ.get("QWEN3_VL_MODEL", "Qwen/Qwen3-VL-Embedding-2B")
    return Settings(uploads_dir=uploads_dir, backend=backend, dims=dims, qwen_model=qwen_model)
