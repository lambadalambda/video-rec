# Milestone 06 — Personalized feed (app integration)

Goal: use `interactions` + `video_embeddings` to build a real “For You” ranking loop.

Prereq: `docs/milestones/00-web-mvp.md` and `docs/milestones/05-api-and-pipeline.md`.

- [ ] define signal weights (favorite/unfavorite/watch/impression)
- [ ] persist long-term `user_profiles` (TasteProfile long_sum + weights)
- [ ] background updater (batch process interactions → update profiles)
- [ ] ranked feed query (candidates + filtering + exploration + MMR)
- [ ] keep wrap-around + economical window loading for ranked IDs
- [ ] admin/dev view to inspect: profile vector + top recommendations

