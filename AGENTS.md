# video-suggestion

Goal: ship a working Phoenix + LiveView short‑video app (uploads + TikTok-style feed) and iteratively add the recommendation core from `docs/` milestones (vectors → ranking/diversity → taste profiles → tagging).

Development loop:

1) Write a failing ExUnit test for the next behavior.
2) Implement the smallest change to pass.
3) Run `mix test`.
4) Run `mix format`.
5) Commit (small, focused) with a descriptive message.

Notes:

- Keep commits scoped to one feature at a time.
- Prefer pure functions + unit tests for reco logic (`lib/video_suggestion/reco/`).

## Auth routing (quick rules)

- Don’t duplicate `live_session` names; extend the existing blocks in `lib/video_suggestion_web/router.ex`.
- Public LiveViews go under `live_session :current_user`; authenticated ones under `:require_authenticated_user`.
- Use `@current_scope.user` (not `@current_user`) in LiveViews/templates.

