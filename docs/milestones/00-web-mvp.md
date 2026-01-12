# Milestone 00 — Web MVP (visible app first)

Goal: ship a working, mobile-first site before recommendation logic.

- [x] Authentication (register/login/logout)
- [x] Admin bootstrap (first user becomes admin)
- [x] Admin-only video upload (store locally; no analysis yet)
  - [x] Deduplicate by content hash
  - [x] Bulk upload (ignore duplicates)
- [x] Public (or logged-in) feed showing uploaded videos
- [x] TikTok-style mobile UX (vertical, full-screen, swipe/scroll)
  - [x] Fit arbitrary aspect ratios (no cropping)
  - [x] Hide native video controls
  - [x] Desktop next/prev controls + arrow keys
  - [x] Preload adjacent videos
  - [x] Hide feed scrollbars
  - [x] Favorite button + favorites count
  - [x] Sound toggle (persists + switches with active video)
  - [x] Endless feed wrap-around
- [x] Basic access control + smoke tests
