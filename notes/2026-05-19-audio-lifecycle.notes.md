---
issue: 0000
title: Round audio lifecycle
---

Assumptions:

- `issues/0000.md` is the intended target for `/afk issue 0`.
- The frontend is the right implementation surface because audio assets and playback already live there.
- There is no dedicated frontend test command in `package.json`; validation will use TypeScript/Vite build and lint unless a test runner is added later.
- Backend phase names map to frontend phases as `RoundSetup -> WordChoice`, `RoundInProgress -> Guessing`, `RoundScoreDisplay -> ScoreDisplay`, and `GameOver -> GameEnd`.
- "Round reveal" corresponds to `turnEnd`, where the backend currently maps `RoundFinished` to the `Guessing` screen for a brief result phase.
