import types

from embedding_worker.transcription import OpenAIWhisperTranscriber


def test_openai_whisper_transcriber_uses_cached_model(monkeypatch):
    calls = {"load_model": 0, "transcribe": 0}

    class FakeModel:
        def transcribe(self, path, **kwargs):
            calls["transcribe"] += 1
            assert path == "/tmp/a.mp4"
            assert kwargs["task"] == "transcribe"
            return {"text": " hello world "}

    def load_model(model_name, device="cpu", download_root=None):
        calls["load_model"] += 1
        assert model_name == "tiny"
        assert device == "cpu"
        return FakeModel()

    fake_whisper = types.SimpleNamespace(load_model=load_model)
    monkeypatch.setitem(__import__("sys").modules, "whisper", fake_whisper)

    transcriber = OpenAIWhisperTranscriber(model_name="tiny", device="cpu")

    assert transcriber.transcribe("/tmp/a.mp4") == "hello world"
    assert transcriber.transcribe("/tmp/a.mp4") == "hello world"
    assert calls["load_model"] == 1
    assert calls["transcribe"] == 2
