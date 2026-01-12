# video-suggestion

Phoenix + LiveView short‑video prototype with an evolving recommendation core.

## Web MVP

- Auth via magic link (`mix phx.gen.auth`)
- First registered user becomes admin
- Admin-only video upload (stored in `priv/static/uploads/`)
- Public TikTok-style feed at `/`

## Setup

Requirements: Elixir 1.19 / Erlang 28 (see `mise.toml`) and Postgres.

```sh
mix setup
mix phx.server
```

Open `http://localhost:5000`, register at `/users/register`, then use `/dev/mailbox` (dev only) to grab the login link. The first registered user is admin; upload at `/admin/videos/new`.

## Recommendation Core

Pure, unit-tested modules (see `lib/video_suggestion/reco/`):

- `vector.ex` (dot/norm/normalize/mean)
- `ranking.ex` (dot scoring, filtering, MMR reranking)
- `taste_profile.ex` (long-term + session vectors)
- `tagging.ex` (top-K tag scoring)

Design docs live in `docs/`.

## Dev

Run tests:

```sh
mix test
```

Format:

```sh
mix format
```
