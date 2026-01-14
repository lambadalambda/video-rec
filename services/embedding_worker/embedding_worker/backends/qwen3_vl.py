from __future__ import annotations

from dataclasses import dataclass
import gc
import importlib.util
import logging
import os
import re
import shutil
import subprocess
import time
from io import BytesIO
from pathlib import Path
from typing import Any, Dict, List, Optional

from .base import EmbeddingBackend, EmbeddingResult


@dataclass(frozen=True)
class Qwen3VLOptions:
    model_name_or_path: str
    device: Optional[str] = None
    max_length: int = 8192


logger = logging.getLogger(__name__)


class Qwen3VLBackend(EmbeddingBackend):
    def __init__(
        self,
        *,
        model_name_or_path: str,
        device: str = "auto",
        max_length: int = 8192,
        video_fps: float = 1.0,
        video_max_frames: int = 64,
        video_target_frames: int = 10,
        transcribe_enabled: bool = True,
        whisper_backend: str = "openai",
        whisper_model: str = "small",
        whisper_device: str = "auto",
        whisper_language: Optional[str] = None,
    ):
        self._opts = Qwen3VLOptions(
            model_name_or_path=model_name_or_path, device=device, max_length=max_length
        )
        self._embedder = None

        self._video_fps = video_fps
        self._video_max_frames = video_max_frames
        self._video_target_frames = video_target_frames

        self._transcribe_enabled = transcribe_enabled
        self._whisper_backend = whisper_backend
        self._whisper_model = whisper_model
        self._whisper_device = whisper_device
        self._whisper_language = whisper_language
        self._transcriber = None

    def embed_video(
        self, *, path: str, caption: str, dims: int, transcribe: Optional[bool] = None
    ) -> EmbeddingResult:
        started = time.monotonic()
        transcript = None

        parts = []
        if caption and caption.strip():
            parts.append(caption.strip())

        do_transcribe = self._transcribe_enabled if transcribe is None else bool(transcribe)

        if do_transcribe:
            transcript = self._get_transcriber().transcribe(path)
            if transcript:
                parts.append(transcript)

        text = "\n\n".join(parts)

        embedder = self._get_embedder()

        duration_seconds = None
        if isinstance(self._video_target_frames, int) and self._video_target_frames > 0:
            probe_started = time.monotonic()
            duration_seconds = _probe_video_duration_seconds(path)
            probe_ms = int((time.monotonic() - probe_started) * 1000)
        else:
            probe_ms = 0

        video_fps, video_max_frames = _compute_video_sampling_params(
            duration_seconds=duration_seconds,
            base_fps=self._video_fps,
            base_max_frames=self._video_max_frames,
            target_frames=self._video_target_frames,
        )

        reader_backend = _qwen_video_reader_backend()

        video_input: Any = path
        frame_extractor = "native"
        extracted_frames = 0
        extract_ms = 0
        if _should_extract_video_frames(
            requested_target_frames=self._video_target_frames,
            reader_backend=reader_backend,
        ):
            frame_extractor = "ffmpeg"
            extract_started = time.monotonic()
            extracted = _extract_video_frames_ffmpeg(
                video_path=path,
                fps=video_fps,
                max_frames=video_max_frames,
            )
            extract_ms = int((time.monotonic() - extract_started) * 1000)
            if extracted:
                video_input = extracted
                extracted_frames = len(extracted)
            else:
                frame_extractor = "native_fallback"

        base_input: Dict[str, Any] = {
            "video": video_input,
            "text": text,
            "fps": video_fps,
            "max_frames": video_max_frames,
            "sample_fps": video_fps,
            "duration_seconds": duration_seconds,
        }

        rss_mb = _current_rss_mb()
        logger.info(
            "qwen3_vl.embed_video start path=%s size_mb=%.2f duration_s=%s fps=%.4f max_frames=%d target_frames=%s reader=%s extractor=%s extracted=%d rss_mb=%s probe_ms=%d extract_ms=%d",
            path,
            _file_size_mb(path),
            f"{duration_seconds:.3f}" if isinstance(duration_seconds, (int, float)) else "unknown",
            float(video_fps),
            int(video_max_frames),
            self._video_target_frames,
            reader_backend,
            frame_extractor,
            extracted_frames,
            f"{rss_mb:.1f}" if isinstance(rss_mb, (int, float)) else "unknown",
            probe_ms,
            extract_ms,
        )

        embeddings = None
        try:
            embed_started = time.monotonic()
            embeddings = _process_with_adaptive_max_frames(embedder, base_input)
            embed_ms = int((time.monotonic() - embed_started) * 1000)
            vec = embeddings[0].detach().to("cpu").tolist()
        finally:
            embeddings = None
            embedder.maybe_cleanup()

        if dims is not None and dims > 0 and dims < len(vec):
            vec = vec[:dims]
            vec = _l2_normalize(vec)
        else:
            dims = len(vec)

        version = "qwen3_vl_whisper_v1" if transcript else "qwen3_vl_v1"

        total_ms = int((time.monotonic() - started) * 1000)
        rss_mb_done = _current_rss_mb()
        logger.info(
            "qwen3_vl.embed_video done path=%s version=%s dims=%d elapsed_ms=%d embed_ms=%d rss_mb=%s",
            path,
            version,
            dims,
            total_ms,
            embed_ms if "embed_ms" in locals() else 0,
            f"{rss_mb_done:.1f}" if isinstance(rss_mb_done, (int, float)) else "unknown",
        )
        return EmbeddingResult(version=version, embedding=vec, transcript=transcript)

    def embed_text(self, *, text: str, dims: int) -> EmbeddingResult:
        started = time.monotonic()

        if not text or not text.strip():
            raise ValueError("text_empty")

        embedder = self._get_embedder()

        rss_mb = _current_rss_mb()
        logger.info(
            "qwen3_vl.embed_text start text_len=%d dims=%s rss_mb=%s",
            len(text),
            dims,
            f"{rss_mb:.1f}" if isinstance(rss_mb, (int, float)) else "unknown",
        )

        embeddings = None
        try:
            embed_started = time.monotonic()
            embeddings = embedder.process([{"text": text.strip()}], normalize=True)
            embed_ms = int((time.monotonic() - embed_started) * 1000)
            vec = embeddings[0].detach().to("cpu").tolist()
        finally:
            embeddings = None
            embedder.maybe_cleanup()

        if dims is not None and dims > 0 and dims < len(vec):
            vec = vec[:dims]
            vec = _l2_normalize(vec)
        else:
            dims = len(vec)

        version = "qwen3_vl_v1"

        total_ms = int((time.monotonic() - started) * 1000)
        rss_mb_done = _current_rss_mb()
        logger.info(
            "qwen3_vl.embed_text done version=%s dims=%d elapsed_ms=%d embed_ms=%d rss_mb=%s",
            version,
            dims,
            total_ms,
            embed_ms if "embed_ms" in locals() else 0,
            f"{rss_mb_done:.1f}" if isinstance(rss_mb_done, (int, float)) else "unknown",
        )
        return EmbeddingResult(version=version, embedding=vec, transcript=None)

    def _get_embedder(self):
        if self._embedder is not None:
            return self._embedder

        self._embedder = _Qwen3VLEmbedder(self._opts)
        return self._embedder

    def _get_transcriber(self):
        if self._transcriber is not None:
            return self._transcriber

        from ..transcription import get_whisper_transcriber

        self._transcriber = get_whisper_transcriber(
            backend=self._whisper_backend,
            model_name=self._whisper_model,
            device=self._whisper_device,
            language=self._whisper_language,
        )

        return self._transcriber


def _l2_normalize(vec: List[float]) -> List[float]:
    import math

    norm = math.sqrt(sum(x * x for x in vec))
    if norm == 0.0:
        return vec
    return [x / norm for x in vec]


class _Qwen3VLEmbedder:
    def __init__(self, opts: Qwen3VLOptions):
        import torch
        from transformers import AutoConfig
        from transformers.models.qwen3_vl.modeling_qwen3_vl import Qwen3VLModel, Qwen3VLPreTrainedModel
        from transformers.models.qwen3_vl.processing_qwen3_vl import Qwen3VLProcessor

        self._torch = torch
        self._max_length = opts.max_length

        config = AutoConfig.from_pretrained(opts.model_name_or_path, trust_remote_code=True)
        self._processor = Qwen3VLProcessor.from_pretrained(opts.model_name_or_path, trust_remote_code=True)

        class Qwen3VLForEmbedding(Qwen3VLPreTrainedModel):
            def __init__(self, config):
                super().__init__(config)
                self.model = Qwen3VLModel(config)

            def forward(self, input_ids=None, attention_mask=None, position_ids=None, **kwargs):
                outputs = self.model(
                    input_ids=input_ids,
                    attention_mask=attention_mask,
                    position_ids=position_ids,
                    **kwargs,
                )
                return {"last_hidden_state": outputs.last_hidden_state, "attention_mask": attention_mask}

        self._model = (
            Qwen3VLForEmbedding.from_pretrained(
                opts.model_name_or_path, config=config, trust_remote_code=True
            )
            .eval()
        )

        device = opts.device
        if not device or device == "auto":
            device = _default_device(torch)

        self._device = device
        self._model.to(device)

    def maybe_cleanup(self):
        if not _should_torch_cleanup(self._device):
            return

        gc.collect()

        torch = self._torch

        if self._device == "cuda" and hasattr(torch, "cuda"):
            try:
                torch.cuda.empty_cache()
            except Exception:
                pass

            ipc_collect = getattr(torch.cuda, "ipc_collect", None)
            if callable(ipc_collect):
                try:
                    ipc_collect()
                except Exception:
                    pass

        if self._device == "mps" and hasattr(torch, "mps"):
            empty_cache = getattr(torch.mps, "empty_cache", None)
            if callable(empty_cache):
                try:
                    empty_cache()
                except Exception:
                    pass

    def process(self, inputs: List[Dict[str, Any]], normalize: bool = True):
        import torch.nn.functional as F
        from qwen_vl_utils import process_vision_info

        conversations = [self._format_conversation(ele) for ele in inputs]

        text = self._processor.apply_chat_template(conversations, add_generation_prompt=True, tokenize=False)

        images, video_inputs, video_kwargs = process_vision_info(
            conversations, image_patch_size=16, return_video_metadata=True, return_video_kwargs=True
        )

        if video_inputs is not None:
            videos, video_metadata = zip(*video_inputs)
            videos = list(videos)
            video_metadata = list(video_metadata)
        else:
            videos, video_metadata = None, None

        model_inputs = self._processor(
            text=text,
            images=images,
            videos=videos,
            video_metadata=video_metadata,
            truncation=True,
            max_length=self._max_length,
            padding=True,
            do_resize=False,
            return_tensors="pt",
            **video_kwargs,
        )

        model_inputs = {k: v.to(self._model.device) for k, v in model_inputs.items()}

        with self._torch.inference_mode():
            outputs = self._model(**model_inputs)

            embeddings = _pool_last(outputs["last_hidden_state"], outputs["attention_mask"])

            if normalize:
                embeddings = F.normalize(embeddings, p=2, dim=-1)

            return embeddings

    @staticmethod
    def _format_conversation(ele: Dict[str, Any]):
        instruction = ele.get("instruction") or "Represent the user's input."
        text = ele.get("text")
        video = ele.get("video")
        image = ele.get("image")
        fps = ele.get("fps")
        max_frames = ele.get("max_frames")

        content: List[Dict[str, Any]] = []

        if video:
            if isinstance(video, (list, tuple)):
                video_content = video
            else:
                video_content = (
                    video if str(video).startswith(("http", "oss")) else "file://" + str(video)
                )
            video_kwargs: Dict[str, Any] = {}
            if fps is not None:
                video_kwargs["fps"] = fps
            if max_frames is not None:
                video_kwargs["max_frames"] = max_frames

            content.append({"type": "video", "video": video_content, **video_kwargs})

        if image:
            image_content = image if str(image).startswith(("http", "oss")) else "file://" + str(image)
            content.append({"type": "image", "image": image_content})

        if text:
            content.append({"type": "text", "text": text})

        system = {
            "role": "system",
            "content": [
                {"type": "text", "text": "You are an expert at creating and understanding embeddings."},
                {"type": "text", "text": "Your task is to provide embeddings for the given user input."},
            ],
        }

        user = {"role": "user", "content": [{"type": "text", "text": instruction}] + content}

        return [system, user]


def _pool_last(hidden_state, attention_mask):
    import torch

    flipped = attention_mask.flip(dims=[1])
    last_one = flipped.argmax(dim=1)
    col = attention_mask.shape[1] - last_one - 1
    row = torch.arange(hidden_state.shape[0], device=hidden_state.device)
    return hidden_state[row, col]


def _default_device(torch) -> str:
    if torch.cuda.is_available():
        return "cuda"
    if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def _should_torch_cleanup(device: str) -> bool:
    raw = (os.environ.get("TORCH_CLEANUP") or "auto").strip().lower()
    if raw in ("1", "true", "t", "yes", "y", "on"):
        return True
    if raw in ("0", "false", "f", "no", "n", "off"):
        return False

    # Auto mode: on Apple Silicon, the MPS backend often holds onto large cached buffers
    # across requests; freeing them prevents unbounded growth in long-running batch jobs.
    return device == "mps"


def _process_with_adaptive_max_frames(embedder, base_input: Dict[str, Any]):
    max_frames = base_input.get("max_frames")
    duration_seconds = base_input.get("duration_seconds")
    inputs: List[Dict[str, Any]] = [base_input]

    for _attempt in range(6):
        try:
            return embedder.process(inputs, normalize=True)
        except RuntimeError as e:
            if not _is_video_frame_stack_size_mismatch(e):
                raise

            current_input = inputs[0] if inputs else base_input
            video = current_input.get("video")

            normalized = None
            if isinstance(video, (list, tuple)):
                normalized = _normalize_video_frames_to_common_size(video)

            if normalized is None and isinstance(video, (str, Path)):
                extracted = _extract_video_frames_ffmpeg(
                    video_path=str(video),
                    fps=float(current_input.get("fps") or 1.0),
                    max_frames=int(current_input.get("max_frames") or 1),
                )

                if extracted:
                    normalized = _normalize_video_frames_to_common_size(extracted)

            if normalized:
                logger.warning("qwen3_vl frame_size_mismatch retrying_with_normalized_frames")
                inputs = [{**current_input, "video": normalized}]
                embedder.maybe_cleanup()
                continue

            raise
        except ValueError as e:
            if not _is_mm_video_token_mismatch(e) or not isinstance(max_frames, int) or max_frames <= 1:
                raise

            previous_max_frames = max_frames
            next_max_frames = _reduce_max_frames_from_error(max_frames, str(e))
            if next_max_frames >= max_frames:
                next_max_frames = max_frames // 2

            max_frames = max(1, int(next_max_frames))
            next_input = {**base_input, "max_frames": max_frames}
            if isinstance(duration_seconds, (int, float)) and duration_seconds > 0:
                next_input["fps"] = max_frames / float(duration_seconds)
                next_input["sample_fps"] = next_input["fps"]

            video = next_input.get("video")
            if isinstance(video, (list, tuple)):
                next_input["video"] = _downsample_frames(video, max_frames)

            logger.warning(
                "qwen3_vl token_mismatch max_frames=%s->%s fps=%s",
                previous_max_frames,
                max_frames,
                next_input.get("fps"),
            )

            inputs = [next_input]

            embedder.maybe_cleanup()

    return embedder.process(inputs, normalize=True)


def _is_mm_video_token_mismatch(error: Exception) -> bool:
    msg = str(error)
    return "Mismatch in `video` token count between text and `input_ids`" in msg


def _is_video_frame_stack_size_mismatch(error: Exception) -> bool:
    msg = str(error)
    return "stack expects each tensor to be equal size" in msg


def _reduce_max_frames_from_error(current_max_frames: int, msg: str) -> int:
    match = re.search(r"Got ids=\[(\d+)\] and text=\[(\d+)\]", msg)
    if not match:
        return max(1, current_max_frames // 2)

    try:
        ids_count = int(match.group(1))
        text_count = int(match.group(2))
    except ValueError:
        return max(1, current_max_frames // 2)

    if ids_count <= 0 or text_count <= 0:
        return max(1, current_max_frames // 2)

    ratio = ids_count / text_count
    # Conservative reduction to avoid repeated retries.
    candidate = int(current_max_frames * ratio)

    if candidate <= 0:
        return 1
    if candidate >= current_max_frames:
        return max(1, current_max_frames - 1)

    return candidate


def _compute_video_sampling_params(
    *,
    duration_seconds: Optional[float],
    base_fps: float,
    base_max_frames: int,
    target_frames: int,
) -> tuple[float, int]:
    fps = float(base_fps)

    try:
        max_frames = int(base_max_frames)
    except (TypeError, ValueError):
        max_frames = 1

    if max_frames <= 0:
        max_frames = 1

    if not isinstance(target_frames, int) or target_frames <= 0:
        return fps, max_frames

    target = min(max_frames, target_frames)

    if not isinstance(duration_seconds, (int, float)) or duration_seconds <= 0:
        return fps, target

    return (target / float(duration_seconds)), target


def _probe_video_duration_seconds(video_path: str) -> Optional[float]:
    ffprobe_bin = _find_ffprobe()
    if ffprobe_bin is None:
        return None

    if not Path(str(video_path)).exists():
        return None

    cmd = [
        ffprobe_bin,
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "default=nk=1:nw=1",
        str(video_path),
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    except Exception:
        return None

    if result.returncode != 0:
        return None

    raw = (result.stdout or "").strip()
    if not raw:
        return None

    try:
        duration = float(raw)
    except ValueError:
        return None

    if duration <= 0.0:
        return None

    return duration


def _find_ffprobe() -> Optional[str]:
    override = os.environ.get("FFPROBE_BIN")
    if override:
        return override

    found = shutil.which("ffprobe")
    if found:
        return found

    ffmpeg_bin = os.environ.get("FFMPEG_BIN")
    if ffmpeg_bin:
        try:
            candidate = str(Path(ffmpeg_bin).with_name("ffprobe"))
        except Exception:
            candidate = None

        if candidate and Path(candidate).exists():
            return candidate

    for candidate in ("/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"):
        if Path(candidate).exists():
            return candidate

    return None


def _qwen_video_reader_backend() -> str:
    override = os.environ.get("FORCE_QWENVL_VIDEO_READER")
    if override:
        return override

    if importlib.util.find_spec("torchcodec") is not None:
        return "torchcodec"
    if importlib.util.find_spec("decord") is not None:
        return "decord"
    return "torchvision"


def _should_extract_video_frames(*, requested_target_frames: int, reader_backend: str) -> bool:
    if not isinstance(requested_target_frames, int) or requested_target_frames <= 0:
        return False

    raw = (os.environ.get("QWEN_VIDEO_FRAME_EXTRACTOR") or "auto").strip().lower()
    if raw in ("ffmpeg", "1", "true", "t", "yes", "y", "on"):
        return True
    if raw in ("native", "0", "false", "f", "no", "n", "off"):
        return False

    # Auto: qwen-vl-utils falls back to torchvision.io.read_video which reads the full
    # video into memory before sampling, causing large and duration-dependent memory/time spikes.
    return reader_backend == "torchvision"


def _extract_video_frames_ffmpeg(
    *, video_path: str, fps: float, max_frames: int
) -> Optional[List[Any]]:
    ffmpeg_bin = _find_ffmpeg()
    if ffmpeg_bin is None:
        return None

    try:
        from PIL import Image
    except ModuleNotFoundError:
        return None

    if max_frames <= 0:
        return []

    try:
        fps_value = float(fps)
    except (TypeError, ValueError):
        fps_value = 0.0

    if fps_value <= 0.0:
        fps_value = 1.0

    frames: List[Any] = []

    for i in range(int(max_frames)):
        timestamp = i / fps_value
        cmd = [
            ffmpeg_bin,
            "-hide_banner",
            "-loglevel",
            "error",
            "-ss",
            str(timestamp),
            "-i",
            str(video_path),
            "-an",
            "-sn",
            "-dn",
            "-frames:v",
            "1",
            "-f",
            "image2pipe",
            "-vcodec",
            "png",
            "pipe:1",
        ]

        try:
            result = subprocess.run(cmd, capture_output=True, timeout=30)
        except Exception:
            continue

        if result.returncode != 0 or not result.stdout:
            continue

        try:
            with BytesIO(result.stdout) as bio:
                img = Image.open(bio)
                img.load()
        except Exception:
            continue

        frames.append(img)

    if not frames:
        return None

    return _normalize_video_frames_to_common_size(frames) or frames


def _find_ffmpeg() -> Optional[str]:
    override = os.environ.get("FFMPEG_BIN")
    if override:
        return override

    found = shutil.which("ffmpeg")
    if found:
        return found

    for candidate in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"):
        if Path(candidate).exists():
            return candidate

    return None


def _downsample_frames(frames: Any, target_frames: int) -> List[Any]:
    items = list(frames)
    if target_frames <= 0:
        return []
    if len(items) <= target_frames:
        return items
    if target_frames == 1:
        return [items[0]]

    last = len(items) - 1
    indices = [int(i * last / (target_frames - 1)) for i in range(target_frames)]
    return [items[i] for i in indices]


def _normalize_video_frames_to_common_size(frames: Any) -> Optional[List[Any]]:
    items = list(frames)
    if not items:
        return None

    sizes = []
    for item in items:
        size = getattr(item, "size", None)
        if not (isinstance(size, (tuple, list)) and len(size) == 2):
            return None
        sizes.append((int(size[0]), int(size[1])))

    if all(size == sizes[0] for size in sizes):
        return items

    try:
        from PIL import Image, ImageOps
    except ModuleNotFoundError:
        return None

    counts: Dict[tuple[int, int], int] = {}
    for size in sizes:
        counts[size] = counts.get(size, 0) + 1

    def key(size: tuple[int, int]) -> tuple[int, int]:
        return (counts.get(size, 0), size[0] * size[1])

    target_size = max(counts.keys(), key=key)

    normalized: List[Any] = []
    for item in items:
        img = item

        if getattr(img, "mode", None) != "RGB":
            try:
                img = img.convert("RGB")
            except Exception:
                pass

        if getattr(img, "size", None) != target_size:
            try:
                resample = getattr(Image, "Resampling", Image).BILINEAR
                img = ImageOps.pad(img, target_size, method=resample, color=(0, 0, 0))
            except Exception:
                try:
                    img = img.resize(target_size)
                except Exception:
                    continue

        normalized.append(img)

    if normalized:
        logger.warning(
            "qwen3_vl normalized_frames sizes=%s target_size=%s",
            sorted(set(sizes)),
            target_size,
        )

    return normalized or None


def _file_size_mb(path: str) -> float:
    try:
        return Path(str(path)).stat().st_size / (1024 * 1024)
    except OSError:
        return 0.0


def _current_rss_mb() -> Optional[float]:
    try:
        result = subprocess.run(
            ["ps", "-o", "rss=", "-p", str(os.getpid())],
            capture_output=True,
            text=True,
            timeout=2,
        )
    except Exception:
        return None

    if result.returncode != 0:
        return None

    raw = (result.stdout or "").strip()
    if not raw:
        return None

    try:
        kb = int(raw)
    except ValueError:
        return None

    return kb / 1024.0
