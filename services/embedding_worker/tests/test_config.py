from embedding_worker.config import get_settings


def test_settings_default_qwen_quantization(monkeypatch):
    monkeypatch.delenv("QWEN_QUANTIZATION", raising=False)
    monkeypatch.delenv("QWEN_BATCH_MAX_SIZE", raising=False)
    monkeypatch.delenv("QWEN_BATCH_WAIT_MS", raising=False)
    get_settings.cache_clear()

    settings = get_settings()
    assert settings.qwen_quantization == "none"
    assert settings.qwen_batch_max_size == 1
    assert settings.qwen_batch_wait_ms == 10


def test_settings_parses_qwen_quantization(monkeypatch):
    monkeypatch.setenv("QWEN_QUANTIZATION", "int4")
    get_settings.cache_clear()

    settings = get_settings()
    assert settings.qwen_quantization == "int4"


def test_settings_parses_qwen_microbatching(monkeypatch):
    monkeypatch.setenv("QWEN_BATCH_MAX_SIZE", "8")
    monkeypatch.setenv("QWEN_BATCH_WAIT_MS", "25")
    get_settings.cache_clear()

    settings = get_settings()
    assert settings.qwen_batch_max_size == 8
    assert settings.qwen_batch_wait_ms == 25
