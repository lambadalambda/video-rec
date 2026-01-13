import math
from pathlib import Path

from fastapi.testclient import TestClient

from embedding_worker.config import get_settings
from embedding_worker.main import app


def test_healthz():
    client = TestClient(app)
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_embed_video_returns_normalized_vector(tmp_path: Path, monkeypatch):
    uploads = tmp_path / "uploads"
    uploads.mkdir(parents=True, exist_ok=True)
    (uploads / "a.mp4").write_bytes(b"fake-mp4")

    monkeypatch.setenv("UPLOADS_DIR", str(uploads))
    monkeypatch.setenv("EMBEDDING_BACKEND", "deterministic")
    monkeypatch.setenv("EMBEDDING_DIMS", "8")
    get_settings.cache_clear()

    client = TestClient(app)
    r = client.post("/v1/embed/video", json={"storage_key": "a.mp4", "caption": "Cats and dogs"})
    assert r.status_code == 200
    payload = r.json()

    assert payload["version"] == "caption_v1"
    assert payload["dims"] == 8
    assert len(payload["embedding"]) == 8

    norm = math.sqrt(sum(x * x for x in payload["embedding"]))
    assert abs(norm - 1.0) < 1.0e-6


def test_unknown_backend_returns_501(tmp_path: Path, monkeypatch):
    uploads = tmp_path / "uploads"
    uploads.mkdir(parents=True, exist_ok=True)
    (uploads / "a.mp4").write_bytes(b"fake-mp4")

    monkeypatch.setenv("UPLOADS_DIR", str(uploads))
    monkeypatch.setenv("EMBEDDING_BACKEND", "nope")
    get_settings.cache_clear()

    client = TestClient(app)
    r = client.post("/v1/embed/video", json={"storage_key": "a.mp4"})
    assert r.status_code == 501


def test_qwen_backend_without_deps_returns_501(tmp_path: Path, monkeypatch):
    uploads = tmp_path / "uploads"
    uploads.mkdir(parents=True, exist_ok=True)
    (uploads / "a.mp4").write_bytes(b"fake-mp4")

    monkeypatch.setenv("UPLOADS_DIR", str(uploads))
    monkeypatch.setenv("EMBEDDING_BACKEND", "qwen3_vl")
    get_settings.cache_clear()

    client = TestClient(app)
    r = client.post("/v1/embed/video", json={"storage_key": "a.mp4"})
    assert r.status_code == 501
