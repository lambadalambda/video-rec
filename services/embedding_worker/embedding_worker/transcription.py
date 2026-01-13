from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
import subprocess
import tempfile
import os
from pathlib import Path
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


@lru_cache(maxsize=4)
def get_openai_whisper_transcriber(
    *, model_name: str = "small", device: str = "auto", language: Optional[str] = None
) -> OpenAIWhisperTranscriber:
    return OpenAIWhisperTranscriber(model_name=model_name, device=device, language=language)


class TransformersWhisperTranscriber:
    def __init__(
        self,
        *,
        model_name: str = "distil-whisper/distil-large-v3",
        device: str = "auto",
        language: Optional[str] = None,
    ):
        self._model_name = model_name
        self._device = device
        self._language = language
        self._pipeline = None

    def transcribe(self, path: str) -> str:
        pipeline = self._get_pipeline()

        generate_kwargs = {"task": "transcribe"}
        if self._language:
            generate_kwargs["language"] = self._language

        tmp_audio_path = None
        audio_path = path

        try:
            if not _is_likely_audio_path(audio_path):
                tmp_audio_path = _extract_audio_to_wav(audio_path)
                audio_path = tmp_audio_path

            try:
                result = _run_asr_pipeline(pipeline, audio_path, generate_kwargs)
            except ValueError as e:
                # Some pipeline backends try to open files via soundfile, which doesn't support
                # video containers. If that happens, fall back to extracting audio and retry.
                message = str(e)
                if (
                    tmp_audio_path is None
                    and "Soundfile is either not in the correct format" in message
                ):
                    tmp_audio_path = _extract_audio_to_wav(path)
                    audio_path = tmp_audio_path
                    result = _run_asr_pipeline(pipeline, audio_path, generate_kwargs)
                else:
                    raise
        finally:
            if tmp_audio_path is not None:
                try:
                    os.remove(tmp_audio_path)
                except OSError:
                    pass

        if isinstance(result, dict):
            text = (result.get("text") or "").strip()
        else:
            text = str(result).strip()

        return " ".join(text.split())

    def _get_pipeline(self):
        if self._pipeline is not None:
            return self._pipeline

        import torch
        from transformers import pipeline

        device = self._device
        if device == "auto":
            device = _default_device_torch(torch)

        self._device = device

        self._pipeline = pipeline(
            task="automatic-speech-recognition",
            model=self._model_name,
            device=device,
        )

        return self._pipeline


@lru_cache(maxsize=4)
def get_transformers_whisper_transcriber(
    *, model_name: str = "distil-whisper/distil-large-v3", device: str = "auto", language: Optional[str] = None
) -> TransformersWhisperTranscriber:
    return TransformersWhisperTranscriber(model_name=model_name, device=device, language=language)


@lru_cache(maxsize=8)
def get_whisper_transcriber(
    *, backend: str = "openai", model_name: str = "small", device: str = "auto", language: Optional[str] = None
):
    if backend == "openai":
        return get_openai_whisper_transcriber(
            model_name=model_name,
            device=device,
            language=language,
        )

    if backend == "transformers":
        return get_transformers_whisper_transcriber(
            model_name=model_name,
            device=device,
            language=language,
        )

    raise NotImplementedError(f"Unknown whisper backend: {backend}")


def _default_device() -> str:
    try:
        import torch
    except Exception:
        return "cpu"

    return _default_device_torch(torch)


def _default_device_torch(torch) -> str:
    if torch.cuda.is_available():
        return "cuda"
    if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def _is_likely_audio_path(path: str) -> bool:
    ext = Path(str(path)).suffix.lower()
    return ext in {".wav", ".flac", ".mp3", ".m4a", ".ogg", ".opus"}


def _extract_audio_to_wav(video_path: str) -> str:
    fd, out_path = tempfile.mkstemp(prefix="embedding_worker_audio_", suffix=".wav")
    os.close(fd)

    cmd = [
        "ffmpeg",
        "-y",
        "-i",
        str(video_path),
        "-vn",
        "-ac",
        "1",
        "-ar",
        "16000",
        "-f",
        "wav",
        out_path,
        "-loglevel",
        "error",
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
    except FileNotFoundError as e:
        raise RuntimeError("ffmpeg_not_found") from e

    if result.returncode != 0:
        stderr = (result.stderr or "").strip()
        raise RuntimeError(f"ffmpeg_failed: {stderr}")

    return out_path


def _run_asr_pipeline(pipeline, audio_path: str, generate_kwargs):
    try:
        return pipeline(audio_path, generate_kwargs=generate_kwargs)
    except ValueError as e:
        # For audio > ~30s, Whisper switches to long-form generation which requires timestamp tokens.
        message = str(e)
        if "return_timestamps" in message and "long-form generation" in message:
            return pipeline(audio_path, generate_kwargs=generate_kwargs, return_timestamps=True)
        raise
