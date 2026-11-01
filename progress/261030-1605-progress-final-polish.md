## Session
- who: Kilo (kilo AI CLI tool, runs inside kilo)
- model: kilo/nvidia/nemotron-3.5-super-vl:free
- platform: linux (CachyOS, niri 26.04, Wayland)
- worktree: /mnt/r/projects/a-memoloop
- date: 2026-10-30
- timestamp: 261030-1605

## What was done

Final polish of start/stop/status output:

- `start`: draws bare frame (no title gap) with ⊕ row "memoloop started · PID NNN" and · row "next: fixed ... | random ...". Matches requested layout exactly.
- `stop`: ⟜ memoloop stopped · PID NNN
- `status`: ⦿ memoloop is running / · memoloop is not running / ⊘ memoloop is paused / ▽ memoloop is in do not disturb; next-due only when running
- `stop` / `start` use term_added (⊕) / term_removed (⟜) per term.sh conventions
- Cursor hide/restore on answer feedback (⏵ / ⏵)
- Choice questions: English-only options, no note leakage
- Reverse questions: accept kana + romaji
- Questions: grouped dirs under ~/.config/memoloop/questions/, enabled via pickup.set
- Scoring: base 100, correct +10, incorrect -10 (floor 0), weight 100/(points+100), time decay, ≥10/day minimum
- Tests: 19 passed, 0 failed

Commits pushed:
- 4e3d62d start output format fix
- 72cd35c wording and markers polish
- 8b5f061 status marker refinement
- 93b1181 hide next-due when stopped
- ad6ed00 start/stop correct PID capture
- ffd5cd7 replace watch with start/stop
- 5253405 polish status and ask output
- b35bae5 kana/romaji answers for reverse
- 56c3354 choice questions English-only options

## Files modified (in repo)

- src/memoloop — full implementation
- tests/memoloop_test.sh — 19 tests
- progress/*.md — snapshots
- progress/pickup.md — pointer

## Files outside repo (~/.config/memoloop/, ~/.cache/memoloop/)

- intervals.conf, pickup.set, questions/*/*.json
- answers.json (runtime cache)

## Where to resume next

- None blocking. MVP prototype complete and working.

## Open questions / blockers

- None blocking.