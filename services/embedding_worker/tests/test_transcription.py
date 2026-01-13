from embedding_worker.transcription import TransformersWhisperTranscriber


def test_transformers_transcriber_extracts_audio_for_video(monkeypatch):
    calls = []

    def fake_pipeline(path, **kwargs):
        calls.append((path, kwargs))
        return {"text": "hello world"}

    monkeypatch.setattr(TransformersWhisperTranscriber, "_get_pipeline", lambda self: fake_pipeline)
    monkeypatch.setattr("embedding_worker.transcription._extract_audio_to_wav", lambda _p: "converted.wav")

    t = TransformersWhisperTranscriber(model_name="noop", device="cpu")
    assert t.transcribe("video.mp4") == "hello world"
    assert calls[0][0] == "converted.wav"

