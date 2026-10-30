## Session
- who: Kilo (kilo AI CLI tool, runs inside kilo)
- model: kilo/nvidia/nemotron-3.5-super-vl:free
- platform: linux (CachyOS, niri 26.04, Wayland)
- worktree: /mnt/r/projects/a-memoloop
- date: 2026-10-30
- timestamp: 261030-1530

## What was done

Fixed start/stop daemon management and polished status output.

- `cmd_start`: launches `memoloop watch` in background via `setsid`. The child writes its own PID to `state/pidfile` before exec'ing, so stop always kills the correct process. Includes status info (daemon PID, paused/DND/running, next-due times) in output.
- `cmd_stop`: kills the daemon by pidfile PID (SIGTERM → SIGKILL fallback), removes stale pidfiles.
- `cmd_status`: now shows `daemon: running (PID N)` or `daemon: stopped` by checking the pidfile, plus state (reminders running / PAUSED / Do Not Disturb) and next-due times.
- Removed `watch` from user-facing commands (replaced by `start`/`stop`), kept as internal foreground loop used by `start`.
- `PID_FILE="$STATE_DIR/pidfile"` added for daemon PID tracking.

Tests: 19 passed, 0 failed.
Committed `ad6ed00` and pushed to `origin main`.

## Files modified

- src/memoloop — start/stop/status rewritten
- progress/261030-1530-progress-start-stop.md — this snapshot
- pickup.md — updated pointer

## Where to resume next

- None blocking. MVP prototype is complete and working.

## Open questions / blockers

- None blocking.