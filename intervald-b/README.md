# intervald

Runs any command on fixed and/or random (re-rolled) intervals. "cron with a twist."
Python 3.11+, needs PyYAML (`pacman -S python-yaml` / `apt install python3-yaml`).

## Install
    ./install.sh          # copies to ~/.local/bin, installs the user unit, enables + starts it
Edit `~/.config/intervald/config.yaml`, then `intervald check && intervald reload`.

## Commands
    intervald run [-c file]     daemon (what the unit runs)
    intervald check [-c file]   validate only (exit 2 on errors, reports ALL errors)
    intervald status            jobs, running PIDs, next fire per rule
    intervald fire <job>        spawn now, ignores overlap, doesn't touch timers
    intervald reload            re-read config (same as `systemctl --user reload intervald`)

## Config reference
See `config.example.yaml`. Durations: integer + `s|m|h` (`90s`, `45m`, `2h`).
Per job: `command` (required), `terminal` (false), `shell` (false), `overlap` (skip|allow, default skip),
`schedule` (list of `every: <dur>` / `random: [<min>, <max>]`; rules are independent timers).

## Decisions / defaults
- Control channel: unix socket `$XDG_RUNTIME_DIR/intervald.sock` (JSON, one line). Simple, gives errors back to `reload`.
- Bad config at startup: print errors, exit 2. Bad config on reload: logged, old config kept.
- Reload re-rolls all timers. Timers use the monotonic clock, which does NOT tick during suspend,
  so a suspend just pauses timers; no catch-up burst on resume.
- Fixed rules advance from the previous deadline (no drift); random rules re-roll from "now".
- Spawned programs: own session, stdio to /dev/null, survive daemon stop (`KillMode=process`), reaped every <=5s.
- Overlap tracks the PID *we* spawned. With `terminal: true` that's the terminal (foot), which is what you want.
  An app you opened by hand isn't tracked.
- Missing executable is a warning, not an error. No shell unless `shell: true`.
- GUI env: if WAYLAND_DISPLAY/DISPLAY are missing, the daemon looks for `wayland-*` in XDG_RUNTIME_DIR (or X0) at spawn time.
  For a cleaner setup add to your compositor startup: `systemctl --user import-environment WAYLAND_DISPLAY DISPLAY`.
- Duplicate YAML keys are errors; quoted "yes" for a bool is an error; bare `30` is an error (needs a unit).

## Replacing old memoloop scheduling
    systemctl --user disable --now memoloop.service   # use your real unit name (systemctl --user list-units | grep memo)
Then remove the daemon/scheduling code and the scheduling keys from memoloop; keep `memoloop ask`.

## Ideas for later
Active-hours window, persisted state across restarts, per-job environment/cwd, stdout/stderr logging per job.
