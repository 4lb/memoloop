## Session
- who: Kilo (kilo AI CLI tool, runs inside kilo)
- model: kilo/nvidia/nemotron-3.5-super-vl:free
- platform: linux (CachyOS, niri 26.04, Wayland)
- worktree: /mnt/r/projects/a-memoloop
- date: 2026-10-30
- timestamp: 261030-1357

## What was done

Combined groundwork + project rename into one snapshot (supersedes
`261030-1324-repo-groundwork.md` and `261030-1353-rename-memoloop.md`, both removed).

Project: directory `a-memoloop`, name `memoloop` (MemoLoop), quick-popup feature
`PopLoop`. Git repo initialized (`git init`, config `4lb`/`github@robal.net`),
nothing committed yet. Local config `repo.name=memoloop`. No GitHub remote yet.

Groundwork (files created):
- `.gitignore` — `state/`, `log/`, `*.state`, editor/OS files
- `LICENSE` — MIT
- `README.md` — repo/project name, MemoLoop/PopLoop, resume line `read ./pickup.md`
- `pickup.md` — resume pointer to latest `progress/*.md` + `plans/AGENT.md`
- `progress/README.md` — progress report conventions (naming `YYMMDD-HHMM`, frontmatter,
  pointer sentence to latest snapshot)
- Empty placeholder dirs: `src/`, `lib/`, `data/questions/`, `docs/`, `tests/`, `state/`,
  `log/` (state/log gitignored)

Read & absorbed (reference context — do not redo):
- `plans/AGENT.md`, `tech-stack.md`, `first-steps.md`, `261030-app-plan.md`
- Reference projects (read-only, not modified, no runtime dep):
  `t-linux/cli-utilities/utilities/glyph-key` (popup terminal renderer, own lib/ copy
  of term.sh), `desk-reminder` (per-rule intervals, XDG_STATE_HOME state, D-Bus daemon
  polling)

Decisions locked:
- Bash prototype (throwaway UX harness per tech-stack.md), own `lib/term.sh` renderer,
  two independent rules (fixed 15 min / random 30–40 min), overlap queued in-app,
  no backlog on pause/DND, Japanese kana+kanji question set, state/log gitignored inside repo.

[PATH] updated to `/home/eru/r/projects/a-memoloop` in `plans/AGENT.md`.

## Where to resume next

Implementation per `plans/AGENT.md` — groundwork done, implementation not started.
Next: `src/` entry script + `lib/term.sh` renderer + sample questions in
`data/questions/`, then two scheduling rules (fixed 15 min, random 30–40 min), controls
(submit/dismiss/pause), DND window, answer checking, tests in `tests/`, final README.

## Open questions / blockers

- Add GitHub remote: user will create `memoloop` on GitHub, then `git remote add origin <url>`.
