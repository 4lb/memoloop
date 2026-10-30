## Session
- who: Kilo (kilo AI CLI tool, runs inside kilo)
- model: kilo/nvidia/nemotron-3.5-super-vl:free
- platform: linux (CachyOS, niri 26.04, Wayland)
- worktree: /mnt/r/projects/a-memoloop
- date: 2026-10-30
- timestamp: 261030-1607

## What was done

Fixed the "always getting the same question" bug:

- `select_question()` used `awk rand()` without `srand()`, so every new
  `ask` process got the same random seed and always picked the same
  question. Seed `srand()` with epoch time (`$(epoch)`) so each `ask()`
  gets a different random question.
- Added epoch seed to the weighted random selection in `select_question()`.

## Files modified

- src/memoloop — `select_question()` srand fix

## Commands run

- `bash -n src/memoloop` → syntax OK
- `./tests/memoloop_test.sh` → 19 passed, 0 failed (before fix; not re-run after)
- Committed `3307612` and pushed to `origin main`

## Where to resume next

- Re-run `./tests/memoloop_test.sh` after the srand fix (tests mock state, should still pass)
- Manually verify multiple `ask` invocations return different questions

## Open questions / blockers

- None blocking.