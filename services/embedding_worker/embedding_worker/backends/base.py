from dataclasses import dataclass
from typing import List, Optional


@dataclass(frozen=True)
class EmbeddingResult:
    version: str
    embedding: List[float]
    transcript: Optional[str] = None


class EmbeddingBackend:
    def embed_video(self, *, path: str, caption: str, dims: int) -> EmbeddingResult:
        raise NotImplementedError

