import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    uploads_dir: Path
    backend: str
    dims: int


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    uploads_dir = Path(os.environ.get("UPLOADS_DIR", "priv/static/uploads")).resolve()
    backend = os.environ.get("EMBEDDING_BACKEND", "deterministic")
    dims = int(os.environ.get("EMBEDDING_DIMS", "64"))
    return Settings(uploads_dir=uploads_dir, backend=backend, dims=dims)

