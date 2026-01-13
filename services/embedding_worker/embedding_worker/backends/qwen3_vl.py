from __future__ import annotations

from dataclasses import dataclass
import gc
import os
from typing import Any, Dict, List, Optional

from .base import EmbeddingBackend, EmbeddingResult


@dataclass(frozen=True)
class Qwen3VLOptions:
    model_name_or_path: str
    device: Optional[str] = None
    max_length: int = 8192


class Qwen3VLBackend(EmbeddingBackend):
    def __init__(
        self,
        *,
        model_name_or_path: str,
        device: str = "auto",
        max_length: int = 8192,
        video_fps: float = 1.0,
        video_max_frames: int = 64,
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

        self._transcribe_enabled = transcribe_enabled
        self._whisper_backend = whisper_backend
        self._whisper_model = whisper_model
        self._whisper_device = whisper_device
        self._whisper_language = whisper_language
        self._transcriber = None

    def embed_video(
        self, *, path: str, caption: str, dims: int, transcribe: Optional[bool] = None
    ) -> EmbeddingResult:
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

        inputs: List[Dict[str, Any]] = [
            {
                "video": path,
                "text": text,
                "fps": self._video_fps,
                "max_frames": self._video_max_frames,
            }
        ]
        embeddings = None
        try:
            embeddings = embedder.process(inputs, normalize=True)
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
        return EmbeddingResult(version=version, embedding=vec, transcript=transcript)

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
            video_content = video if str(video).startswith(("http", "oss")) else "file://" + str(video)
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
