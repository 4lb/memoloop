## Session
- who: Kilo (kilo AI CLI tool, runs inside kilo)
- model: kilo/nvidia/nemotron-3.5-super-vl:free
- platform: linux (CachyOS, niri 26.04, Wayland)
- worktree: /mnt/r/projects/a-memoloop
- date: 2026-10-30
- timestamp: 261030-1354

## What was done

Implemented the memoloop Linux prototype MVP and made it runnable on the user's system.

- `src/memoloop` — entry script: `watch` daemon, `ask` popup, `status`, `pause`/`resume`, `dnd`, `test`, `setup`. Two independent scheduling rules (fixed, random) each tracking its own next-due time; restart recalculates from now; pause/DND suppress prompts with no backlog; queued while a popup is open (no overlapping foot terminals). Fixed interval overridable via `MEMOLOOP_FIXED_SECONDS` env var (default 900s = 15 min). Status line rendered as two unwrapped rows. Popup closes on any key after feedback (no `--hold`).
- `lib/term.sh` — vendored terminal renderer (glyph-key pattern).
- `data/questions/questions.json` — 12 sample Japanese questions (kana/kanji, English, accepted answers incl. romaji).
- `niri/memoloop.kdl` — floating + size rules for memoloop popups; included in `~/.config/niri/config.kdl`.
- `tests/memoloop_test.sh` — 19 tests (intervals, scheduling, due detection, pause/resume/DND, answer matching); all pass.
- `README.md` — run instructions, intervals, controls, question editing, queueing behaviour, limitations.

## Files created / modified

Created: src/memoloop, lib/term.sh, data/questions/questions.json, tests/memoloop_test.sh, niri/memoloop.kdl, progress/261030-1354-progress-implementation.md
Modified: README.md, pickup.md, ~/.config/niri/config.kdl (added memoloop.kdl include)

## Commands run

- `./tests/memoloop_test.sh` → 19 passed, 0 failed
- `./src/memoloop setup` / `status` / `ask fixed` / `test` smoke tests
- Daemon run on user's system: `MEMOLOOP_FIXED_SECONDS=30 ./src/memoloop watch` (fixed rule every 30s, floating popups, any-key-to-close)
- Committed `d75b76e` (this session's changes) and pushed to `origin main`

## Where to resume next

Improve the question set per user request: not only translation patterns — add fill-in-the-blank (cloze), multiple-choice (A/B/C), and one more pattern. Base content on user's Japanese references under `/home/eru/q/` (JLPT kanji level 4 base, common words, homework conjugations) to match their beginner level.

## Open questions / blockers

- User's `~/mynotes/` not found at `/home/eru/mynotes/`; notes location unclear. References live in `/home/eru/q/NIHONGO/` and `/home/eru/q/_sync/MEGA/Preply-Nihongo/`.
