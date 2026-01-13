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
