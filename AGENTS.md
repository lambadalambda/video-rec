# video-suggestion

Goal: build a small, well-tested recommendation core (vectors, ranking/diversity, tagging, user taste profiles) that can later be wired into a Phoenix app + embedding worker.

Development loop:

1) Write a failing ExUnit test for the next behavior.
2) Implement the smallest change to pass.
3) Run `mix test`.
4) Run `mix format`.
5) Commit (small, focused) with a descriptive message.

Notes:

- Prefer pure functions + unit tests (no external services required for `mix test`).
- Keep commits scoped to one feature at a time.

