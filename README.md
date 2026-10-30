# memoloop

MemoLoop — Linux prototype of a Japanese desktop language-learning app.

Project: directory `a-memoloop`, name `memoloop` (MemoLoop).
PopLoop — the quick-popup feature (marketing / internal naming).
Resume: `read ./pickup.md`

## Status

Prototype implemented (Linux/Bash). See [`plans/AGENT.md`](plans/AGENT.md) for the
product plan, [`plans/first-steps.md`](plans/first-steps.md) for the build
stages, and [`plans/app-plan.md`](plans/app-plan.md) for the revised product
plan.

## What the prototype does and does not do

Does:
- Two independent scheduling rules: fixed (every 15 minutes by default) and random
  (every 30–40 minutes), each tracking its own next-due time.
- A terminal popup (`foot`) showing a Japanese prompt with its English meaning,
  answer instructions, and current status (running / paused / DND).
- Answer submission, correctness feedback (accepted vs not accepted, intended
  answer shown), dismiss without answering, and a global pause-all control.
- A configurable Do-Not-Disturb window.
- No backlog: prompts due while paused or in DND are skipped, not queued.
- Queueing: if a popup is already open when another rule fires, the second
  prompt is queued and shown after the first is dismissed (no overlapping
  popup terminals).
- Logging of each prompt (rule, scheduled time, result) to `log/`.
- Basic automated tests in `tests/`.

Does not:
- Cross-platform packaging (Tauri is the planned future, see `plans/tech-stack.md`).
- Spaced repetition / SuperMemo scheduling (explicitly out of scope for this prototype).
- System-wide keyboard interception, OS locking, accounts, cloud sync, or Anki integration.

## Dependencies

- `bash` (5.x)
- `foot` terminal emulator (popup windows)
- `jq` (JSON processing)
- A UTF-8 locale and a font that covers Japanese (kana/kanji) for correct display.

Install (CachyOS/Arch example):

    paru -S foot jq

## Run instructions

All commands run from the repo root:

    ./src/memoloop setup        # initialise state/ and log/ directories
    ./src/memoloop status       # show paused / DND / next-due state
    ./src/memoloop watch        # run the reminder daemon (fixed 15 min + random 30–40 min)
    ./src/memoloop test         # launch one test prompt immediately
    ./src/memoloop pause        # pause all reminders
    ./src/memoloop resume       # resume all reminders
    ./src/memoloop dnd <start> <end>   # set DND window, e.g. dnd 09:00 17:00
    ./src/memoloop ask <rule>   # show one question popup (used by the daemon)

`watch` is the daemon: leave it running in the background (e.g. under a
systemd user service or `nohup ./src/memoloop watch &`). It opens one terminal
popup at a time when a rule is due.

Tests:

    ./tests/memoloop_test.sh

## Floating popups (niri)

memoloop opens its prompt in a `foot` terminal. To make that window float
(centred, not tiled) under niri, add this to your `~/.config/niri/config.kdl`
— after any global window rules so it takes precedence:

    include optional=true "memoloop.kdl"

and place `niri/memoloop.kdl` at
`~/.config/niri/memoloop.kdl`. It matches `app-id="memoloop"` exactly, so
every other `foot` window keeps tiling. The size rule dimensions the window to
the term.sh frame (64 columns) so the popup box is centred.

## Directory tree

- `src/memoloop` — entry script (daemon + popup + scheduling)
- `lib/term.sh` — terminal renderer (vendored copy, like glyph-key's)
- `data/questions/questions.json` — local sample Japanese question set
- `state/` — runtime state (rules, session, current question, result; gitignored)
- `log/` — runtime logs (gitignored)
- `tests/memoloop_test.sh` — basic automated tests
- `plans/` — product and technical plans
- `progress/` — session progress snapshots

## How to configure intervals and DND

Intervals are defined in `src/memoloop` (`FIXED_SECONDS=900` = 15 minutes by
default, `RANDOM_MIN=30`, `RANDOM_MAX=40`). Override the fixed interval at run
time via the `MEMOLOOP_FIXED_SECONDS` environment variable, e.g. for a 30-second
test:

    MEMOLOOP_FIXED_SECONDS=30 ./src/memoloop watch

Edit the source values and restart `watch` for a permanent change.

DND is a global window set with:

    ./src/memoloop dnd 09:00 17:00

It is stored in `state/session.json` (`dnd_start`/`dnd_end`). Clear it by
setting both to null, or omit the times. Prompts due inside the window are
skipped (no backlog).

## How to edit the sample questions

Edit `data/questions/questions.json`. Each entry needs:

- `japanese` — the prompt text (kana and/or kanji)
- `english` — the meaning shown to the learner
- `accepted` — list of accepted answers (Japanese and/or romaji; matched
  case-insensitively with surrounding whitespace trimmed)

Add/remove entries freely; `ask` picks one at random each time.

## How simultaneous rules and an already-open popup are handled

Each rule keeps its own next-due time. If fixed and random both fire close
together, the first one opens its popup and the second is queued in
`state/session.json` (`queue`). While a popup is open (`foot --hold`), any
further due rule is queued rather than launching an overlapping terminal. When
the user dismisses the held window, the daemon launches the next queued rule.
Each prompt is logged separately with its rule id, so both rules are honoured
and none is silently merged or discarded.

## Restart, pause, and missed-prompt behaviour

- Restart: on start, `watch` recalculates each rule's next-due from now
  (fixed: now + 15 min; random: now + 30–40 min). No complex persistence; a
  small JSON state file is enough.
- Pause: `./src/memoloop pause` stops all prompts; `resume` restarts them.
  Missed prompts during pause are skipped, not queued.
- DND: prompts due inside the DND window are skipped (no backlog).
- After answering or dismissing, that rule's timer resets from that moment.

## Assumptions, limitations, follow-up work

- Runs under a terminal emulator (`foot`) on Wayland/X11; no display → popups
  cannot open (foot errors out).
- Japanese display/input assumes a UTF-8 locale and a font covering kana/kanji;
  verify with `memoloop ask fixed`.
- DND window is same-day only (no overnight windows) in this prototype.
- State files live inside the repo (`state/`, `log/`, gitignored) for
  self-containment.
- Follow-up: Tauri proof of concept (see `plans/tech-stack.md`), spaced
  repetition behind a replaceable interface, richer question types, per-rule
  enable/disable, optional prompt bundling.

## Reference projects (do not modify, no runtime dependency)

- `t-linux/cli-utilities/utilities/glyph-key` — popup terminal that accepts
  input and reflects its current state (pattern for `term.sh` + `foot --hold`).
- `t-linux/cli-utilities/utilities/desk-reminder` — interval scheduling and
  reminder behaviour (pattern for independent rules and state).
