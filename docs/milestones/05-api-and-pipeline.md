# Milestone 05 — API + pipeline (future)

Goal: wire the core into a Phoenix app + background pipeline.

- [x] Phoenix app scaffold (LiveView web MVP)
- [ ] JSON API scaffold (auth + endpoints)
- [x] Web: admin video upload (store locally; no analysis yet)
- [x] Postgres schema: `interactions` table
- [x] Postgres schema: `video_embeddings` table (array<float> placeholder)
- [x] LiveView interaction logging (impression + watch time + favorite/unfavorite)
- [ ] interaction ingestion endpoint (batch)
- [x] Web: feed with cursor pagination
- [ ] feed API endpoint with cursors
- [x] embedding worker interface (HTTP) (stub backend + Qwen3-VL + Whisper options)
- [ ] Oban job pipeline stubs (enqueue → call worker → persist embeddings)
- [ ] Postgres schemas + `pgvector` migration
