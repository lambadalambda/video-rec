from typing import List, Optional

from pydantic import BaseModel, Field


class VideoEmbedRequest(BaseModel):
    storage_key: str = Field(..., min_length=1)
    caption: Optional[str] = None
    dims: Optional[int] = Field(None, gt=0)
    transcribe: Optional[bool] = None


class VideoEmbedResponse(BaseModel):
    version: str
    dims: int
    embedding: List[float]
    transcript: Optional[str] = None


class VideoTranscribeRequest(BaseModel):
    storage_key: str = Field(..., min_length=1)


class VideoTranscribeResponse(BaseModel):
    transcript: str


class TextEmbedRequest(BaseModel):
    text: str = Field(..., min_length=1)
    dims: Optional[int] = Field(None, gt=0)


class TextEmbedResponse(BaseModel):
    version: str
    dims: int
    embedding: List[float]
