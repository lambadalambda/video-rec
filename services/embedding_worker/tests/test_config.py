from embedding_worker.config import get_settings


def test_settings_default_qwen_quantization(monkeypatch):
    monkeypatch.delenv("QWEN_QUANTIZATION", raising=False)
    get_settings.cache_clear()

    settings = get_settings()
    assert settings.qwen_quantization == "none"


def test_settings_parses_qwen_quantization(monkeypatch):
    monkeypatch.setenv("QWEN_QUANTIZATION", "int4")
    get_settings.cache_clear()

    settings = get_settings()
    assert settings.qwen_quantization == "int4"

