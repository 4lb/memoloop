Task: build a program-agnostic interval runner daemon, extracted from my existing
tool "memoloop".

## Context
memoloop is a language-learning tool. It currently runs as a systemd daemon that
spawns a bash script in a new `foot` terminal at fixed or random intervals
(configured in interval.conf). It also supports a manual trigger via
`memoloop ask`. I recently added the ability to spawn Anki on its own interval,
which made me realize the scheduling should be generic.

## Goal
Split scheduling from the thing being scheduled. Create a standalone daemon
("intervald", name is changeable) that launches ANY configured command on
configurable fixed and/or random intervals. memoloop becomes just one job
(`memoloop ask`) among many. Think "cron, but with randomized, re-rolled
intervals".

## Before coding
1. Inspect the existing memoloop code, systemd unit, and interval.conf. Summarize
   how scheduling and spawning currently work.
2. Propose a short plan and list any ambiguities. Then proceed with the defaults
   below unless something is blocking.

## Config (YAML, parsed as data, never executed)
Path: ~/.config/intervald/config.yaml (override with -c <path>)

settings:
  terminal: "foot -e"

jobs:
  <job-name>:
    command: "<string>"        # required; split into argv with shlex, no shell
    terminal: true|false       # default false; if true, prefix settings.terminal
    shell: true|false          # default false; if true, run via /bin/sh -c
    overlap: skip|allow        # default skip
    schedule:                  # required, at least one rule
      - every: <dur>           # fixed interval
      - random: [<min>, <max>] # uniform random delay, RE-ROLLED after every fire

Semantics:
- <dur> = positive integer + unit s|m|h (e.g. 90s, 45m, 2h). Reject anything else
  (no floats, no bare numbers, no "1h30m", no days).
- A job may have multiple rules. Each rule is an INDEPENDENT timer. The job fires
  whenever any rule fires. Each rule keeps its own next-fire time.
- overlap: skip  -> if a previous instance of this job is still running when a
  scheduled fire happens, skip that fire and log it. The rule's timer still
  reschedules normally.
- overlap: allow -> always spawn.
- Manual `intervald fire <job>` ALWAYS spawns, ignoring overlap. It does not
  affect or reset the job's scheduled timers.
- Job name is the ID. Names must match [A-Za-z0-9_-]+.

## YAML specifics
- Use PyYAML with yaml.safe_load only (never yaml.load). Document the dependency
  (python-yaml / python3-yaml).
- Use a custom SafeLoader subclass that REJECTS DUPLICATE KEYS with a clear error
  (line number if available). PyYAML silently overwrites by default.
- Booleans must be real YAML booleans (true/false). Reject strings like "yes" or
  "true" given as quoted strings where a bool is expected, and give a helpful
  message.
- Beware of values like `30m`: they are plain strings, which is fine, but validate
  types strictly (a bare `30` is an int and must be rejected with a hint to add a
  unit).

## Validation (strict)
Implement `intervald check [-c path]` that validates and exits non-zero with clear
messages (job name, field, reason, line if possible). Validate: YAML syntax,
duplicate keys, unknown keys (at every level), wrong types, missing command, empty
schedule, rule with neither/both of every/random, random not a 2-item list, bad
duration, zero/negative durations, min > max, bad job name, terminal: true with
no settings.terminal defined, non-existent executable (WARN, not error; document
this). Collect and report ALL errors, not just the first.
- On daemon startup: invalid config = print errors and exit non-zero.
- On reload: invalid config = log errors and KEEP running the old config.

## Daemon behavior
- Single process, single scheduler loop using next-fire timestamps
  (heap or min-of-all), no thread-per-rule, no sleep-drift accumulation.
  Use monotonic time.
- Reload on SIGHUP (and `systemctl --user reload`). Reload re-reads config and
  re-rolls all timers; no catch-up for missed fires (e.g. after suspend/resume:
  if the deadline passed while suspended, fire at most once, then reschedule from
  now; document which you chose).
- Spawned processes must be detached (own session via start_new_session), not
  killed when the daemon restarts or stops (configure KillMode=process or
  equivalent in the unit), and reaped (no zombies). Track running PIDs per job
  for overlap.
- Run as a systemd USER service. Provide the unit file with ExecReload=kill -HUP
  $MAINPID. Make sure GUI apps can launch (WAYLAND_DISPLAY, DISPLAY,
  XDG_RUNTIME_DIR, PATH): document or implement how the environment gets imported
  (e.g. `systemctl --user import-environment` from compositor startup, or
  reading it in the unit).
- Log to journald via stdout/stderr: config loaded, each fire (and whether
  scheduled or manual), next fire time per rule, skipped-due-to-overlap, spawn
  failures.

## CLI
intervald run                 # daemon
intervald check [-c path]     # validate only
intervald status              # jobs, rules, running state, next fire time per rule
                              # (via control socket or state file; pick the
                              # simplest robust way and justify it)
intervald fire <job>          # force spawn now, ignoring overlap
intervald reload              # convenience for SIGHUP

## Migration
- Convert my existing setup into the new config: memoloop job = `memoloop ask`
  (terminal: true) and anki job = `anki`, using the intervals currently in
  interval.conf (fixed 2700s; random 15-30 min for memoloop; anki random 15-30 min
  and fixed 2700s). Express the durations with sensible units.
- memoloop keeps its own non-scheduling settings (decay_hours, min_per_day) in its
  own config. Remove scheduling logic and the scheduling keys from memoloop's
  interval.conf / daemon.
- `memoloop ask` must keep working exactly as before. Existing memoloop commands
  that start/stop/restart the daemon should be sensibly redirected or documented.
- Provide an example config.yaml and migration notes (including how to disable
  the old memoloop systemd unit).

## Implementation preferences
- Language: Python 3.11+, stdlib + PyYAML only (asyncio or a simple selector
  loop). If you think bash is a better fit, argue for it first.
- Small, readable, one main file + tests is fine.
- Tests: duration parsing, schedule rule validation errors, duplicate-key
  rejection, random range bounds, scheduler next-fire logic with a fake clock,
  independent timers for multi-rule jobs, overlap skip, manual fire ignoring
  overlap, reload keeping the old config on error.
- Don't add features beyond this spec (no cron expressions, no GUI, no web UI),
  but list any you think are worth adding later (e.g. active-hours window,
  persisted state across restarts, per-job environment).

## Deliverables
Code, systemd user unit, example config.yaml, tests, README with
install/usage/migration steps, and a short summary of every default and decision
you made.
