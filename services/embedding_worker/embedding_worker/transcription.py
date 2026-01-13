from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class TranscriptionResult:
    text: str
    language: Optional[str] = None


class OpenAIWhisperTranscriber:
    def __init__(
        self,
        *,
        model_name: str = "small",
        device: str = "auto",
        language: Optional[str] = None,
    ):
        self._model_name = model_name
        self._device = device
        self._language = language
        self._model = None

    def transcribe(self, path: str) -> str:
        model = self._get_model()

        kwargs = {"task": "transcribe"}
        if self._language:
            kwargs["language"] = self._language

        # Whisper uses fp16 on CUDA by default; keep it off for CPU/MPS.
        kwargs["fp16"] = self._device == "cuda"

        result = model.transcribe(path, **kwargs)
        text = (result.get("text") or "").strip()
        return " ".join(text.split())

    def _get_model(self):
        if self._model is not None:
            return self._model

        whisper = __import__("whisper")

        device = self._device
        if device == "auto":
            device = _default_device()

        self._device = device
        self._model = whisper.load_model(self._model_name, device=device)
        return self._model


def _default_device() -> str:
    try:
        import torch
    except Exception:
        return "cpu"

    if torch.cuda.is_available():
        return "cuda"
    if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        return "mps"
    return "cpu"

