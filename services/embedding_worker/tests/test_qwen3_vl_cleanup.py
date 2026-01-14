import math

from embedding_worker.backends import qwen3_vl


def test_should_torch_cleanup_defaults_to_true_on_mps(monkeypatch):
    monkeypatch.delenv("TORCH_CLEANUP", raising=False)
    assert qwen3_vl._should_torch_cleanup("mps") is True


def test_should_torch_cleanup_defaults_to_false_on_cpu(monkeypatch):
    monkeypatch.delenv("TORCH_CLEANUP", raising=False)
    assert qwen3_vl._should_torch_cleanup("cpu") is False


def test_should_torch_cleanup_honors_env_override(monkeypatch):
    monkeypatch.setenv("TORCH_CLEANUP", "1")
    assert qwen3_vl._should_torch_cleanup("cpu") is True

    monkeypatch.setenv("TORCH_CLEANUP", "0")
    assert qwen3_vl._should_torch_cleanup("mps") is False


def test_reduce_max_frames_from_error_parses_token_mismatch():
    msg = (
        "Mismatch in `video` token count between text and `input_ids`. "
        "Got ids=[8052] and text=[23040]. Likely due to `truncation='max_length'`."
    )
    assert qwen3_vl._reduce_max_frames_from_error(64, msg) == 22


def test_compute_video_sampling_params_scales_fps_to_target_frames():
    fps, max_frames = qwen3_vl._compute_video_sampling_params(
        duration_seconds=30.0,
        base_fps=1.0,
        base_max_frames=64,
        target_frames=10,
    )

    assert max_frames == 10
    assert math.isclose(fps, 10.0 / 30.0, rel_tol=1e-6)


def test_compute_video_sampling_params_long_video_keeps_about_target_frames():
    fps, max_frames = qwen3_vl._compute_video_sampling_params(
        duration_seconds=600.0,
        base_fps=1.0,
        base_max_frames=64,
        target_frames=10,
    )

    assert max_frames == 10
    assert math.isclose(fps, 10.0 / 600.0, rel_tol=1e-6)


def test_compute_video_sampling_params_caps_target_frames_to_max_frames():
    fps, max_frames = qwen3_vl._compute_video_sampling_params(
        duration_seconds=10.0,
        base_fps=1.0,
        base_max_frames=8,
        target_frames=10,
    )

    assert max_frames == 8
    assert math.isclose(fps, 8.0 / 10.0, rel_tol=1e-6)


def test_compute_video_sampling_params_falls_back_when_duration_unknown():
    fps, max_frames = qwen3_vl._compute_video_sampling_params(
        duration_seconds=None,
        base_fps=1.0,
        base_max_frames=64,
        target_frames=10,
    )

    assert fps == 1.0
    assert max_frames == 10


def test_compute_video_sampling_params_disables_with_zero_target():
    fps, max_frames = qwen3_vl._compute_video_sampling_params(
        duration_seconds=30.0,
        base_fps=1.0,
        base_max_frames=64,
        target_frames=0,
    )

    assert fps == 1.0
    assert max_frames == 64


def test_format_conversation_preserves_video_frames_list():
    frames = ["frame-a", "frame-b"]

    conversation = qwen3_vl._Qwen3VLEmbedder._format_conversation(
        {
            "video": frames,
            "text": "hello",
            "fps": 1.0,
            "max_frames": 2,
        }
    )

    user = conversation[1]
    video_items = [item for item in user["content"] if item.get("type") == "video"]
    assert len(video_items) == 1
    assert video_items[0]["video"] is frames


def test_normalize_video_frames_to_common_size_resizes_mismatched_frames():
    try:
        from PIL import Image
    except ModuleNotFoundError:
        return

    big = Image.new("RGB", (1408, 1088), color=(10, 10, 10))
    small = Image.new("RGB", (320, 256), color=(20, 20, 20))

    normalized = qwen3_vl._normalize_video_frames_to_common_size([big, small, big])
    assert normalized is not None
    assert len(normalized) == 3
    assert all(getattr(img, "size", None) == normalized[0].size for img in normalized)
