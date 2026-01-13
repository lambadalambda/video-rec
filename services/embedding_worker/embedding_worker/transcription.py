from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
import subprocess
import tempfile
import os
import shutil
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

        max_new_tokens = _default_max_new_tokens_for_pipeline(pipeline, generate_kwargs)
        if max_new_tokens is not None:
            generate_kwargs["max_new_tokens"] = max_new_tokens

        tmp_audio_path = None
        audio_path = path

        try:
            if not _is_likely_audio_path(audio_path):
                tmp_audio_path = _extract_audio_to_wav(audio_path)
                if tmp_audio_path is None:
                    return ""

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
                    if tmp_audio_path is None:
                        return ""

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


def _extract_audio_to_wav(video_path: str) -> Optional[str]:
    fd, out_path = tempfile.mkstemp(prefix="embedding_worker_audio_", suffix=".wav")
    os.close(fd)

    ffmpeg_bin = _find_ffmpeg()
    if ffmpeg_bin is None:
        raise RuntimeError("ffmpeg_not_found")

    cmd = [
        ffmpeg_bin,
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

    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        stderr = (result.stderr or "").strip()
        if _ffmpeg_no_audio(stderr):
            try:
                os.remove(out_path)
            except OSError:
                pass

            return None

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


def _default_max_new_tokens_for_pipeline(pipeline, generate_kwargs) -> Optional[int]:
    override = os.environ.get("WHISPER_MAX_NEW_TOKENS")
    budget = _max_new_tokens_budget_for_pipeline(pipeline, generate_kwargs)

    if override:
        try:
            value = int(override)
        except ValueError:
            value = None

        if value is not None and value > 0:
            if budget is None:
                return value
            return min(value, budget)

    model = getattr(pipeline, "model", None)
    if model is None:
        return None

    generation_config = getattr(model, "generation_config", None)
    config = getattr(model, "config", None)

    max_target_positions = getattr(config, "max_target_positions", None)
    if not isinstance(max_target_positions, int) or max_target_positions <= 0:
        return None

    # Some Whisper model configs (notably openai/whisper-large-v3-turbo) ship with a very low
    # generation max_length, which truncates transcriptions to a handful of tokens. When we
    # detect a suspiciously-low max length, use the model's maximum target positions instead.
    gen_max_length = getattr(generation_config, "max_length", None)
    cfg_max_length = getattr(config, "max_length", None)

    suspected_max_length = None
    for candidate in (gen_max_length, cfg_max_length):
        if isinstance(candidate, int):
            if suspected_max_length is None:
                suspected_max_length = candidate
            else:
                suspected_max_length = min(suspected_max_length, candidate)

    if suspected_max_length is not None and suspected_max_length < 64:
        return budget

    return None


def _max_new_tokens_budget_for_pipeline(pipeline, generate_kwargs) -> Optional[int]:
    model = getattr(pipeline, "model", None)
    if model is None:
        return None

    config = getattr(model, "config", None)
    max_target_positions = getattr(config, "max_target_positions", None)
    if not isinstance(max_target_positions, int) or max_target_positions <= 0:
        return None

    prompt_len = _decoder_prompt_len_for_pipeline(pipeline, generate_kwargs)
    if not isinstance(prompt_len, int) or prompt_len <= 0:
        return None

    # Transformers validates that `decoder_input_ids` (prompt+start tokens) plus `max_new_tokens`
    # stays strictly below `max_target_positions`.
    budget = max_target_positions - prompt_len - 1
    if budget <= 0:
        return None

    return budget


def _decoder_prompt_len_for_pipeline(pipeline, generate_kwargs) -> Optional[int]:
    tokenizer = getattr(pipeline, "tokenizer", None)
    get_prompt_ids = getattr(tokenizer, "get_decoder_prompt_ids", None)
    if callable(get_prompt_ids):
        try:
            prompt_ids = get_prompt_ids(
                task=generate_kwargs.get("task"),
                language=generate_kwargs.get("language"),
            )
        except Exception:
            prompt_ids = None

        # `prompt_ids` excludes the decoder start token, which still counts towards length.
        if prompt_ids is None:
            return 1
        return 1 + len(prompt_ids)

    # Fallback heuristic for older tokenizers (Whisper starts with task/no-timestamps + optional language).
    if generate_kwargs.get("language"):
        return 4
    return 3


def _find_ffmpeg() -> Optional[str]:
    override = os.environ.get("FFMPEG_BIN")
    if override:
        return override

    found = shutil.which("ffmpeg")
    if found:
        return found

    for candidate in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"):
        if os.path.exists(candidate):
            return candidate

    return None


def _ffmpeg_no_audio(stderr: str) -> bool:
    if not stderr:
        return False

    stderr = stderr.lower()
    return "does not contain any stream" in stderr or "matches no streams" in stderr
