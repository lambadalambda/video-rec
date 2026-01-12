# video-suggestion

An Elixir recommendation-core playground for a short‑video “For You” feed:

- Vector math + similarity
- Diversity reranking (MMR-style)
- Auto-tag scoring against a curated taxonomy
- User taste vectors (long-term + session)

Design docs live in `docs/`.

## Dev

Requirements: Elixir 1.19 / Erlang 28 (see `mise.toml`).

Run tests:

```sh
mix test
```

Format:

```sh
mix format
```

