from typing import List, Optional

from pydantic import BaseModel, Field


class VideoEmbedRequest(BaseModel):
    storage_key: str = Field(..., min_length=1)
    caption: Optional[str] = None
    dims: Optional[int] = Field(None, gt=0)


class VideoEmbedResponse(BaseModel):
    version: str
    dims: int
    embedding: List[float]

