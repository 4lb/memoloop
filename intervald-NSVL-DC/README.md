# intervald

Program-agnostic interval runner. It launches any configured command on fixed
and/or randomized intervals, re-rolling random delays after every fire. Think
"cron, but with unpredictable intervals".

## Install

Dependencies: Python 3.11+ with PyYAML, and whatever programs you configure.

Arch/CachyOS:

    paru -S python-yaml

Install:

    ./install.sh          # copies to ~/.local/bin, installs the user unit, enables + starts it
    # or manually:
    #   install -Dm755 intervald ~/.local/bin/intervald
    #   install -Dm644 config.example.yaml ~/.config/intervald/config.yaml
    #   install -Dm644 intervald.service ~/.config/systemd/user/intervald.service
    #   systemctl --user daemon-reload
    #   systemctl --user enable --now intervald.service

Edit `~/.config/intervald/config.yaml`, then:

    intervald check
    intervald reload

## Usage

    intervald run                 # daemon, normally run by systemd
    intervald check [-c PATH]     # validate only; reports every error
    intervald status              # jobs, rules, running PIDs, next fire
    intervald fire <job>          # spawn now, ignoring overlap and timers
    intervald reload              # SIGHUP the running daemon

`-c PATH` can be placed before or after the command. The default config is
`~/.config/intervald/config.yaml`.

Status reads a state file written by the daemon at
`$XDG_STATE_HOME/intervald/state.json` (normally
`~/.local/state/intervald/state.json`). A state file is the simplest mechanism
that works without a control socket, survives a daemon restart, and still
shows per-rule next-fire times. A stale PID is reported as not running; the
file is not authoritative for scheduling.

## Config

YAML is parsed as data with `yaml.safe_load`; it is never executed.

```yaml
settings:
  terminal: "foot -e"

jobs:
  memoloop:
    command: "memoloop ask"
    terminal: true
    overlap: skip
    schedule:
      - every: 45m
      - random: [15m, 30m]

  anki:
    command: "anki"
    schedule:
      - every: 45m
```

### settings

| key | type | meaning |
|---|---|---|
| `terminal` | string | command prefix used when a job has `terminal: true` |

### jobs

Job names are IDs: `[A-Za-z0-9_-]+`.

| key | type | default | meaning |
|---|---|---|---|
| `command` | string | required | split with `shlex`, no shell by default |
| `terminal` | bool | `false` | prefix `settings.terminal` to the command |
| `shell` | bool | `false` | run through `/bin/sh -c` instead of `shlex` |
| `overlap` | `skip` / `allow` | `skip` | behavior when a previous instance still runs |
| `schedule` | list | required | at least one fixed or random rule |

### schedule rules

```yaml
schedule:
  - every: 90s
  - random: [15m, 30m]
```

Durations are a positive integer plus `s`, `m`, or `h`. Floats, bare numbers,
`1h30m`, and days are rejected. Each rule is an independent timer with its own
next-fire time. A job fires when any of its rules fires. If several rules for
the same job are due in the same scheduler pass, the job is spawned once and
all of those rules reschedule.

Random rules pick a uniform integer number of seconds in `[min, max]` and
re-roll after every fire.

### overlap

- `skip` (default): a scheduled fire is skipped when a previous instance of the
  same job is still running; the rule still reschedules and the skip is logged.
- `allow`: every scheduled fire spawns.

`intervald fire <job>` always spawns, regardless of overlap, and never changes
scheduled timers.

## Behavior

- One process, one loop. Timers are monotonic deadlines, not sleeps and not
  thread-per-rule.
- Fixed rules advance by their interval from the previous deadline, so normal
  processing time does not accumulate as drift.
- No catch-up after suspend or a late wakeup. A deadline that passed while the
  machine slept fires at most once. If more than one interval was missed, the
  next deadline is computed from now.
- Random rules always reschedule from now with a fresh draw.
- Children are started with `start_new_session=True`, their stdin/output are
  detached, and they are reaped by the loop. They survive daemon stop/restart.
- GUI environment is imported at spawn time: `WAYLAND_DISPLAY`/`DISPLAY` are
  auto-detected from `XDG_RUNTIME_DIR` when not already set, so jobs launched
  from a systemd user service can open windows on a Wayland/X11 session.
- The systemd unit uses `KillMode=process`, so stopping the service does not
  kill spawned jobs.
- `SIGHUP` (and `systemctl --user reload intervald`) re-reads the config and
  re-rolls every timer. An invalid reload is logged and the old config keeps
  running. An invalid config at startup prints all errors and exits non-zero.
- Logging goes to stderr/journald: config load, reload, scheduled and manual
  fires, overlap skips, spawn failures, child exits, and each rule's next fire.

## Defaults and decisions

- Config path `~/.config/intervald/config.yaml`; `-c` overrides it.
- State path `$XDG_STATE_HOME/intervald/state.json`; `INTERVALD_STATE` overrides.
- Default `overlap: skip`.
- Default `terminal: false`, `shell: false`.
- A config with no jobs is valid; the daemon simply idles.
- A nonexistent executable is a warning from `check`, not an error.
- Duplicate YAML keys are rejected by a custom safe loader with line numbers.
- Quoted booleans (`"true"`, `"yes"`) are rejected with a hint.
- Bare integers where a duration is expected are rejected with a hint to add a
  unit.
- Random delays use Python's `random.Random`, seeded at daemon start.
- Manual `fire` loads the config independently of the daemon.
- `reload` signals the PID in the state file; if that is unavailable it falls
  back to `systemctl --user reload intervald.service`.

## Tests

    python3 -m unittest discover -s intervald-NSVL-DC/tests -v

## Later ideas

- Active-hours window per job (only fire between HH:MM and HH:MM).
- Persisted next-fire times across daemon restarts.
- Per-job environment variables and working directory.
- Per-job logging to files.
- `intervald pause` / `resume` for individual jobs.
- Cron expressions (deliberately out of scope now).
