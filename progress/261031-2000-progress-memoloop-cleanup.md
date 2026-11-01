## What changed

- **Removed `intervald-b/` and `intervald-N-CD/` directories** — these were consolidation experiment branches. The main branch now uses the original `intervald/` from the plan.
- **Removed scheduling from `src/memoloop`** — `load_intervals()`, `FIXED_SECONDS`, `RANDOM_MIN`, `RANDOM_MAX`, `ANKI_*` variables and all interval config processing have been stripped. `memoloop ask` now purely displays questions; all scheduling is handled by `intervald` as specified in the plan.
- **Updated `usage()`** — now reads "Scheduling is handled by intervald; configure its jobs in `~/.config/intervald/config.yaml`."
- **Verified**: `memoloop setup`, `memoloop config`, `memoloop ask`, `memoloop test`, `memoloop usage` all work correctly.

## Current state

- `src/memoloop` — cleaned entry script (question-displaying only)
- `intervald/` — original plan implementation (kept in branch)
- `intervald-b/` — removed (experiment)
- `intervald-N-CD/` — removed (experiment)
- `src/memoloop` — entry script for `memoloop ask`/`test`/`config`/`setup`
- `data/questions/` — question JSON files
- `install.sh` — install script
- `README.md`, `AGENTS.md` — documentation
- `progress/pickup.md` — pickup set configuration

**On system:**
- `~/.local/bin/memoloop` — binary
- `~/.config/memoloop/` — `config.conf`, `pickup.set`, `questions/`
- `~/.local/share/memoloop/` — `answers.json`, `current.json`, `result.json`, `log/reminders.log`
- `~/.config/intervald/config.yaml` — intervald config (separate from memoloop)
- `~/.config/systemd/user/memoloop.service` — enabled & running (disabled; scheduling delegated to intervald)
- `~/.local/share/memoloop/` — data dir

**Committed:** c0982a1 — "Remove scheduling from memoloop; keep only question-displaying functionality. Scheduling handled by intervald."

## Where to resume next

- Nothing blocking. MVP prototype complete and running on system.
- Optional: Discussion of XDG cache location, Tauri proof of concept, per-rule enable/disable, richer question types

## Open questions / blockers

- None blocking.
