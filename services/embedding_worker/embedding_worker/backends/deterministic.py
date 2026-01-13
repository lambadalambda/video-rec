from pathlib import Path

from ..embeddings import caption_embedding, seed_embedding, sha256_file
from .base import EmbeddingBackend, EmbeddingResult


class DeterministicBackend(EmbeddingBackend):
    def embed_video(self, *, path: str, caption: str, dims: int, transcribe=None) -> EmbeddingResult:
        if caption and caption.strip():
            return EmbeddingResult(
                version="caption_v1",
                embedding=caption_embedding(caption, dims),
                transcript=None,
            )

        seed = sha256_file(path)
        return EmbeddingResult(
            version="hash_v1",
            embedding=seed_embedding(seed, dims),
            transcript=None,
        )


def safe_storage_key_to_path(uploads_dir: Path, storage_key: str) -> Path:
    if storage_key is None:
        raise ValueError("missing_storage_key")

    storage_key = str(storage_key)

    if storage_key.strip() == "":
        raise ValueError("missing_storage_key")

    if "/" in storage_key or "\\" in storage_key or ".." in storage_key:
        raise ValueError("invalid_storage_key")

    return (uploads_dir / storage_key).resolve()
