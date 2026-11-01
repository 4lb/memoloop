## Session
- who: Kilo (kilo AI CLI tool, runs inside kilo)
- model: kilo/nvidia/nemotron-3.5-super-vl:free
- platform: linux (CachyOS, niri 26.04, Wayland)
- worktree: /mnt/r/projects/a-memoloop
- date: 2026-10-30
- timestamp: 261030-1956

## What was done

Final state of memoloop prototype — fully implemented, tested, and installed on the system.

**Core functionality:**
- `src/memoloop` — entry script: `watch` daemon, `ask` popup, `status`, `pause`/`resume`, `dnd`, `test`, `setup`
- Two independent scheduling rules: fixed (45 min default) and random (15–30 min default), each tracking own next-due time
- Startup recalculates next_due from now; pause/DND suppress prompts without backlog; queued while popup open (no overlapping foot terminals)
- Each prompt logged to `log/reminders.log` with rule id

**Config system (`~/.config/memoloop/`):**
- `intervals.conf` — fixed_seconds, random_min, random_max, decay_hours, min_per_day, nohelp
- `pickup.set` — enabled question group IDs
- `questions/<group>/<file>.json` — questions grouped by directories

**Cache (`~/.local/share/memoloop/`):**
- `answers.json` — per-question point system: base 100, correct +10, incorrect -10 (floor 0), weight 100/(points+100), time decay (half-life per decay_hours), ≥min_per_day unique/day guarantee

**Question types:** translation, reverse, cloze (fill-in-the-blank), choice (ABC multiple-choice, English-only options)
- Reverse questions accept kana + romaji answers
- Answer matching: case-insensitive, whitespace-trimmed, spaces removed from romaji

**Popup behavior:**
- `foot` terminal window, floats via niri rules (933×660)
- `--app-id=memoloop` for niri window rules
- Closes on any key after feedback (NOHELP=true suppresses "Press any key" text but still waits for key)
- `memoloop ask` relaunches inside foot if not already inside one (FOOT_POPUP env var)

**Install script (`install.sh`):**
- `--user` (default) / `--system` / `--uninstall` / `--reinstall` / `--dry-run` / `--no-integration` / `--install-path`
- Vendored `lib/term.sh` and `lib/installer.sh`
- Installs binary to `~/.local/bin/memoloop`, lib/term.sh alongside
- systemd user service at `~/.config/systemd/user/memoloop.service` (enabled + started on install)
- Config at `~/.config/memoloop/`, cache at `~/.local/share/memoloop/`
- zsh alias `memoloop` in `~/.config/zsh/my_zsh_aliases`
- niri `memoloop.kdl` (window floating + MOD+N keybinding) + include in `config.kdl`
- Copies questions from `~/.config/memoloop-bak/questions` if available, else creates defaults
- Uninstall removes ALL traces (binary, lib, config, cache, systemd unit, niri files, zsh alias)

**niri keybinding:** MOD+N → `memoloop ask` with `MEMOLOOP_NOHELP=1`

**Tests:** 19 passed, 0 failed (`tests/memoloop_test.sh`)

**Code style:** All comments stripped from shell scripts (AGENTS.md documents the no-comments policy referencing `t-linux/cli-utilities/conventions/output.md`)

**Files in repo:**
- `src/memoloop` — entry script
- `lib/term.sh` — vendored terminal renderer
- `lib/installer.sh` — vendored installer library
- `install.sh` — install script
- `data/questions/questions.json` — legacy sample questions (no longer used by daemon)
- `niri/memoloop.kdl` — niri window rules + keybinding
- `tests/memoloop_test.sh` — 19 tests
- `README.md` — documentation
- `AGENTS.md` — no-comments policy
- `progress/pickup.md`, `progress/*.md` — session tracking

**Installed on system:**
- `~/.local/bin/memoloop` — binary
- `~/.local/lib/term.sh` — renderer
- `~/.config/systemd/user/memoloop.service` — enabled & running
- `~/.config/memoloop/` — intervals.conf, pickup.set, questions/
- `~/.local/share/memoloop/` — answers.json (cache)
- `~/.config/zsh/my_zsh_aliases` — memoloop alias
- `~/.config/niri/memoloop.kdl` + include in `config.kdl` — MOD+N keybinding

**Committed & pushed:** cc8c592 (NOHELP behavior), 7d670f6 (installer output), 502bdf6 (XDG cache migration), 92ff50a (installer output refactor), 388d026 (niri config include), 4e950ea (questions + error handling), 4490a5b (ask foot popup), 19d3686 (MVP), etc.

## Where to resume next

- Nothing blocking. MVP prototype complete and running on system.
- Optional: XDG cache location discussion (currently `~/.local/share/memoloop/`), Tauri proof of concept, per-rule enable/disable, richer question types

## Open questions / blockers

- None blocking.