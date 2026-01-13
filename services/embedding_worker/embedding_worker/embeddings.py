import hashlib
import math
from typing import Dict, List


def l2_normalize(vector: List[float]) -> List[float]:
    norm_sq = 0.0
    for x in vector:
        norm_sq += x * x

    norm = math.sqrt(norm_sq)
    if norm == 0.0:
        raise ValueError("zero_norm")

    return [x / norm for x in vector]


def sha256_file(path: str) -> bytes:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(2048)
            if not chunk:
                break
            h.update(chunk)
    return h.digest()


def caption_embedding(caption: str, dims: int) -> List[float]:
    caption = (caption or "").strip().lower()
    if caption == "":
        raise ValueError("empty")
    if dims <= 0:
        raise ValueError("invalid_dims")

    tokens = [t for t in _split_tokens(caption) if t]
    if not tokens:
        raise ValueError("empty")

    counts: Dict[int, float] = {}
    for token in tokens:
        idx = _stable_hash_int(token) % dims
        sign = 1.0 if (_stable_hash_int(token + "|sign") % 2) == 0 else -1.0
        counts[idx] = counts.get(idx, 0.0) + sign

    vec = [counts.get(i, 0.0) for i in range(dims)]
    return l2_normalize(vec)


def seed_embedding(seed: bytes, dims: int) -> List[float]:
    if dims <= 0:
        raise ValueError("invalid_dims")
    if not isinstance(seed, (bytes, bytearray)) or len(seed) == 0:
        raise ValueError("invalid_seed")

    raw = _expand_bytes(seed, dims)
    vec = [((b - 127.5) / 127.5) for b in raw]
    return l2_normalize(vec)


def _expand_bytes(seed: bytes, dims: int) -> List[int]:
    chunks = (dims + 31) // 32
    out = b""
    for i in range(chunks):
        out += hashlib.sha256(seed + i.to_bytes(4, "big")).digest()
    return list(out[:dims])


def _stable_hash_int(text: str) -> int:
    digest = hashlib.sha256(text.encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big", signed=False)


def _split_tokens(text: str) -> List[str]:
    token = []
    tokens = []

    for ch in text:
        if ch.isalnum():
            token.append(ch)
        else:
            if token:
                tokens.append("".join(token))
                token = []

    if token:
        tokens.append("".join(token))

    return tokens

