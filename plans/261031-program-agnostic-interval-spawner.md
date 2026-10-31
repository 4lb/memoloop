# Plan: intervald, a program-agnostic interval runner

## Working rules (these override anything below)
- Branch: `agnostic`. Everything is backed up remotely. Overwrite or delete
  freely. Be brave, not careful.
- My current memoloop install is a throwaway test install. Remove the old
  install, its systemd unit, and its user data without asking. Nothing to keep.
- The user is away. Before starting, ask ONCE for any access or permissions you
  will need (systemd --user, file deletion, package install, etc.). After that,
  don't stop to ask; pick sensible defaults and document them.
- Tests: keep them minimal. A single small smoke-test file (duration parsing,
  config validation, next-fire logic with a fake clock). No big test suite.

## Goal
Write a NEW standalone tool, "intervald" (name changeable), from the ground up.
It launches ANY configured command on fixed and/or random intervals. Think
"cron, but with randomized, re-rolled intervals".

The existing memoloop scheduler script is flawed. Do not port it. Skim it only
to learn what it currently does (spawns a bash script in a new `foot` terminal;
intervals in interval.conf), then delete the scheduling part from memoloop.

memoloop ends up as ONLY a question-displaying application:
- `memoloop ask` keeps working as before (shows a question).
- Keeps its own non-scheduling settings (decay_hours, min_per_day).
- Remove from memoloop: the daemon, the systemd unit, the scheduling keys in
  interval.conf (fixed_seconds, random_min/max, anki_*), the Anki spawning, and
  any start/stop/restart commands. If a memoloop subcommand is now meaningless,
  delete it.

## Config (YAML, parsed as data, never executed)
Path: ~/.config/intervald/config.yaml (override with -c <path>)

settings:
  terminal: "foot -e"

jobs:
  <job-name>:
    command: "<string>"        # required; split with shlex, no shell
    terminal: true|false       # default false; if true, prefix settings.terminal
    shell: true|false          # default false; if true, run via /bin/sh -c
    overlap: skip|allow        # default skip
    schedule:                  # required, at least one rule
      - every: <dur>           # fixed interval
      - random: [<min>, <max>] # uniform random delay, RE-ROLLED after every fire

Semantics:
- <dur> = positive integer + unit s|m|h (e.g. 90s, 45m, 2h). Reject anything
  else (no floats, no bare numbers, no "1h30m", no days).
- A job may have multiple rules. Each rule is an INDEPENDENT timer with its own
  next-fire time. The job fires whenever any rule fires.
- overlap: skip -> if a previous instance of the job is still running at a
  scheduled fire, skip that fire and log it. The rule still reschedules.
- overlap: allow -> always spawn.
- Manual `intervald fire <job>` ALWAYS spawns, ignoring overlap, and does not
  affect or reset scheduled timers.
- Job name is the ID, must match [A-Za-z0-9_-]+.

## YAML specifics
- PyYAML with yaml.safe_load only. Document the dependency
  (python-yaml / python3-yaml).
- Custom SafeLoader subclass that REJECTS DUPLICATE KEYS with a clear error
  (line number if available).
- Booleans must be real YAML booleans; reject quoted "yes"/"true" strings where
  a bool is expected, with a helpful message.
- A bare `30` is an int and must be rejected with a hint to add a unit.

## Validation (strict, but keep the code compact)
`intervald check [-c path]` validates and exits non-zero with clear messages
(job name, field, reason, line if possible). Check: YAML syntax, duplicate keys,
unknown keys at every level, wrong types, missing command, empty schedule, rule
with neither/both of every/random, random not a 2-item list, bad duration,
zero/negative durations, min > max, bad job name, terminal: true with no
settings.terminal, non-existent executable (WARN only). Report ALL errors, not
just the first.
- Startup with invalid config: print errors, exit non-zero.
- Reload with invalid config: log errors, KEEP the old config running.

## Daemon behavior
- Single process, single scheduler loop on next-fire timestamps (heap or
  min-of-all), monotonic time, no thread-per-rule, no drift accumulation.
- Reload on SIGHUP (and `systemctl --user reload`). Reload re-reads the config
  and re-rolls all timers. No catch-up for missed fires: if a deadline passed
  during suspend, fire at most once, then reschedule from now. Document this.
- Spawned processes: detached (start_new_session), survive daemon
  restart/stop (KillMode=process or equivalent), reaped (no zombies). Track
  running PIDs per job for overlap.
- systemd USER service with ExecReload=kill -HUP $MAINPID. GUI apps must be able
  to launch (WAYLAND_DISPLAY, DISPLAY, XDG_RUNTIME_DIR, PATH): implement or
  document the environment import.
- Log to journald via stdout/stderr: config loaded, each fire (scheduled or
  manual), next fire per rule, overlap skips, spawn failures.

## CLI
intervald run                 # daemon
intervald check [-c path]     # validate only
intervald status              # jobs, rules, running state, next fire per rule
                              # (simplest robust mechanism; justify briefly)
intervald fire <job>          # force spawn now, ignoring overlap
intervald reload              # convenience for SIGHUP

## Initial config to ship
- memoloop job: `memoloop ask`, terminal: true, schedule from the old
  interval.conf (every 45m, random 15m-30m).
- anki job: `anki`, schedule from the old anki_* settings (every 45m,
  random 15m-30m).
Write it as the user's real ~/.config/intervald/config.yaml and also as an
example file in the repo.

## Implementation
- Python 3.11+, stdlib + PyYAML only. One main file is fine. If bash is clearly
  a better fit, say so in one line and proceed with your choice.
- No features beyond this spec (no cron expressions, no GUI/web UI). List ideas
  for later in the README (e.g. active-hours window, persisted state across
  restarts, per-job environment).

## Deliverables
1. intervald (code), systemd user unit, example config.yaml, minimal smoke test.
2. memoloop stripped down to question display only (old daemon, unit, and
   scheduling config removed; old install and data wiped).
3. Installed and running on this machine: old memoloop unit disabled and removed,
   intervald enabled and started, `intervald status` shown working.
4. Short README: install, usage, config reference, and a list of every default
   and decision you made.
