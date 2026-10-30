## Session
- who: Kilo (kilo AI CLI tool, runs inside kilo)
- model: kilo/nvidia/nemotron-3.5-super-vl:free
- platform: linux (CachyOS, niri 26.04, Wayland)
- worktree: /mnt/r/projects/a-memoloop
- date: 2026-10-30
- timestamp: 261030-1422

## What was done

Implemented the Linux prototype per plans/AGENT.md (groundwork was already done; implementation now complete for the MVP scope).

- `src/memoloop` — entry script: `watch` daemon, `ask` popup, `status`, `pause`/`resume`, `dnd`, `test`, `setup` subcommands. Two independent scheduling rules (fixed 15 min, random 30–40 min), each tracking its own next-due time in `state/rules.json`. On (re)start next_due is recalculated from now. Pause and DND suppress prompts without backlog. When a popup is open, due rules are queued (no overlapping foot terminals); the queue drains after dismissal. Each prompt is logged to `log/reminders.log` with its rule id.
- `lib/term.sh` — vendored copy of the glyph-key terminal renderer (frames, status boxes, ask input rows).
- `data/questions/questions.json` — 12 sample Japanese questions (kana + kanji, English meanings, accepted answers including romaji).
- `tests/memoloop_test.sh` — 19 tests covering interval selection, independent rule scheduling, due detection, pause/resume/DND, and answer matching (case + whitespace handling). All pass.
- `README.md` — rewritten: what it does/does not do, dependencies, run instructions, DND/interval config, editing questions, simultaneous-rule/queueing behaviour, restart/pause/missed behaviour, limitations.
- Vendor `lib/term.sh` copied from `t-linux/cli-utilities/utilities/glyph-key/lib/term.sh` (self-contained copy, not a runtime dependency on the reference project).

## Files created / modified

Created: src/memoloop, lib/term.sh, data/questions/questions.json, tests/memoloop_test.sh
Modified: README.md

## Commands run

- `./src/memoloop setup`, `status`, `test`, `ask fixed` (manual smoke tests)
- `./tests/memoloop_test.sh` → 19 passed, 0 failed
- Popup smoke test: `foot --app-id=memoloop-fixed --hold -e src/memoloop ask fixed` launches and renders Japanese correctly.

## Where to resume next

Nothing blocking for the MVP prototype. Optional follow-up per plans:
- Tauri proof of concept (plans/tech-stack.md)
- Per-rule enable/disable, optional prompt bundling, richer question types
- Add GitHub remote for the repo (open question from prior snapshot)

## Open questions / blockers

- Add GitHub remote: create `memoloop` on GitHub, then `git remote add origin <url>`.
- Nothing committed yet; no GitHub remote added.
