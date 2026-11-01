## Session
- who: Kilo (kilo AI CLI tool, runs inside kilo)
- model: kilo/nvidia/nemotron-3.5-super-vl:free
- platform: linux (CachyOS, niri 26.04, Wayland)
- worktree: /mnt/r/projects/a-memoloop
- date: 2026-10-30
- timestamp: 261030-1542

## What was done

Implemented the ~/.config/memoloop/ config system + answer scoring with weighted selection.

- `src/memoloop` — rewritten: config dir `~/.config/memoloop/` (intervals.conf, pickup.set, questions/<group>/), cache dir `~/.cache/memoloop/` (answers.json). Point system: base 100, correct +10, incorrect -10 (floor 0). Weight: 100/(points+100). Time decay: half-life every decay_hours (default 24h). Daily minimum: min_per_day unique questions/day. Weighted random selection via awk (jq lacks exp/ln/random). New `cmd_config` subcommand.
- `tests/memoloop_test.sh` — rewritten: 19 tests for config loading, question loading, scoring, weights, daily minimum, selection. All pass.
- `plans/261030-config-scoring-plan.md` — design document for the feature.
- `README.md` — updated to document new config system.
- Fixed `questions_shown_today()` stray `)` syntax bug.
- Fixed `update_points()` to pass `$result` via `--arg` to jq.
- Fixed `state_init()` to write `{}` to answers.json even if file exists but is empty.
- Fixed `question_weight()` / `select_question()` to use awk instead of jq's missing exp/ln/random.

## Files modified

Modified: src/memoloop, tests/memoloop_test.sh, README.md
Created: plans/261030-config-scoring-plan.md

## Commands run

- `./tests/memoloop_test.sh` → 19 passed, 0 failed
- Manual smoke tests: setup, status, config, ask (all question types)
- Committed `cc18cb2` and pushed to `origin main`

## Where to resume next

- Update README.md with full config system documentation (partially done)
- Consider removing legacy data/questions/questions.json (no longer used)
- Test the watch daemon end-to-end with the new config system
- Consider adding `memoloop config` subcommands to edit intervals/pickup.set

## Open questions / blockers

- None blocking.
