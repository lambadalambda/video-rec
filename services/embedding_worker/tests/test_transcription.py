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


def test_transformers_transcriber_returns_empty_string_when_video_has_no_audio(monkeypatch):
    calls = []

    def fake_pipeline(path, **kwargs):
        calls.append((path, kwargs))
        return {"text": "should not be called"}

    monkeypatch.setattr(TransformersWhisperTranscriber, "_get_pipeline", lambda self: fake_pipeline)
    monkeypatch.setattr("embedding_worker.transcription._extract_audio_to_wav", lambda _p: None)

    t = TransformersWhisperTranscriber(model_name="noop", device="cpu")
    assert t.transcribe("silent.mp4") == ""
    assert calls == []


def test_transformers_transcriber_overrides_suspicious_max_length(monkeypatch):
    calls = []

    class DummyGenerationConfig:
        max_length = 20

    class DummyConfig:
        max_length = 20
        max_target_positions = 448

    class DummyModel:
        config = DummyConfig()
        generation_config = DummyGenerationConfig()

    class DummyPipeline:
        model = DummyModel()

        class tokenizer:
            @staticmethod
            def get_decoder_prompt_ids(*, task=None, language=None):
                # Matches Whisper behaviour when language is not provided:
                # task token + no-timestamps token (start token is implicit).
                return [(1, 123), (2, 456)]

        def __call__(self, path, **kwargs):
            calls.append((path, kwargs))
            return {"text": "hello world"}

    monkeypatch.setattr(TransformersWhisperTranscriber, "_get_pipeline", lambda self: DummyPipeline())
    monkeypatch.setattr("embedding_worker.transcription._extract_audio_to_wav", lambda _p: "converted.wav")

    t = TransformersWhisperTranscriber(model_name="noop", device="cpu")
    assert t.transcribe("video.mp4") == "hello world"
    # max_target_positions 448 - (start token + 2 prompt tokens) - 1 safety margin = 444
    assert calls[0][1]["generate_kwargs"]["max_new_tokens"] == 444


def test_default_whisper_dtype(monkeypatch):
    import torch

    from embedding_worker import transcription

    assert transcription._default_whisper_dtype("cpu", torch) == torch.float32
    assert transcription._default_whisper_dtype("mps", torch) == torch.float32
    assert transcription._default_whisper_dtype("cuda", torch) == torch.float16


def test_whisper_dtype_override(monkeypatch):
    import torch

    from embedding_worker import transcription

    monkeypatch.setenv("WHISPER_DTYPE", "fp16")
    assert transcription._whisper_dtype_from_env(torch) == torch.float16
