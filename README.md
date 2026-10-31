# memoloop

MemoLoop — Linux prototype of a Japanese desktop language-learning app.

Project: directory `a-memoloop`, name `memoloop` (MemoLoop).
PopLoop — the quick-popup feature (marketing / internal naming).
Resume: `read ./pickup.md`

## Status

Prototype implemented (Linux/Bash). See [`plans/AGENT.md`](plans/AGENT.md) for the
product plan, [`plans/first-steps.md`](plans/first-steps.md) for the build
stages, and [`plans/app-plan.md`](plans/app-plan.md) for the revised product
plan. See [`plans/config-scoring-plan.md`](plans/config-scoring-plan.md) for the
config + scoring design.

## What the prototype does and does not do

Does:
- Two independent scheduling rules: fixed (every 45 minutes by default) and random
  (every 15–30 minutes), each tracking its own next-due time.
- A terminal popup (`foot`) showing a Japanese prompt with its English meaning,
  answer instructions, and current status (running / paused / DND).
- Answer submission, correctness feedback (accepted vs not accepted, intended
  answer shown), dismiss without answering, and a global pause-all control.
  After the feedback, `n` opens another question in the same window; any other
  key closes it.
- A configurable Do-Not-Disturb window.
- No backlog: prompts due while paused or in DND are skipped, not queued.
- Queueing: if a popup is already open when another rule fires, the second
  prompt is queued and shown after the first is dismissed (no overlapping
  popup terminals).
- Logging of each prompt (rule, scheduled time, result) to `log/`.
- Answer scoring with point system: base 100, correct +10, incorrect -10
  (floor 0). Weighted random selection favours low-point questions, with time
  decay so unseen questions resurface. Minimum ~10 unique questions per day.
- Basic automated tests in `tests/`.

Does not:
- Cross-platform packaging (Tauri is the planned future, see `plans/tech-stack.md`).
- Spaced repetition / SuperMemo scheduling (explicitly out of scope for this prototype).
- System-wide keyboard interception, OS locking, accounts, cloud sync, or Anki integration.

## Dependencies

- `bash` (5.x)
- `foot` terminal emulator (popup windows)
- `jq` (JSON processing)
- `awk` (floating-point math for scoring weights)
- A UTF-8 locale and a font that covers Japanese (kana/kanji) for correct display.

Install (CachyOS/Arch example):

    paru -S foot jq

## Run instructions

All commands run from the repo root:

    ./src/memoloop setup        # initialise state, log, data and config directories
    ./src/memoloop status       # show running / paused / DND / next-due state
    ./src/memoloop config       # show effective configuration
    ./src/memoloop watch        # run the reminder loop in the foreground
    ./src/memoloop start        # start the systemd user service (installed copy)
    ./src/memoloop stop         # stop the systemd user service
    ./src/memoloop restart      # restart the systemd user service (use after editing config)
    ./src/memoloop test         # launch one test prompt immediately
    ./src/memoloop pause        # pause all reminders
    ./src/memoloop resume       # resume all reminders
    ./src/memoloop dnd 09:00 17:00   # set the DND window
    ./src/memoloop dnd off      # clear the DND window
    ./src/memoloop ask [rule]   # show one question popup (used by the daemon)

`watch` is the daemon: leave it running in the background (e.g. under a
systemd user service or `nohup ./src/memoloop watch &`). It opens one terminal
popup at a time when a rule is due.

Tests:

    ./tests/memoloop_test.sh

## Configuration (`~/.config/memoloop/`)

**config.conf** — daemon settings:

```
nohelp=true
```

- `nohelp`: skip the "press any key to close" prompt after answering

**Changes take effect only after `memoloop restart`** — the daemon reads
`config.conf` once at startup (`pickup.set` is re-read each question, so it
needs no restart).

Override at run time through the environment:

    MEMOLOOP_DECAY_HOURS=24 ./src/memoloop watch

The same exists for `MEMOLOOP_MIN_PER_DAY` and `MEMOLOOP_NOHELP`.
Environment values win over `config.conf`.

Scheduling (fixed/random intervals) is handled by `intervald`; configure its
jobs in `~/.config/intervald/config.yaml`.

**pickup.set** — enabled question groups, one ID per line:

```
greetings
family
weather
conversation
adjectives
verbs
nouns
```

Only groups listed here are in the loop. Lines starting with `#` are comments.

**questions/<group>/<file>.json** — question files grouped by directory.
See [`docs/question-format.md`](docs/question-format.md) for the full format.
Short version: each entry needs `japanese`, `english`, `accepted`, and `type`:

- `translation` (default) — show Japanese, type the Japanese or romaji answer.
- `reverse` — show the English meaning, type the Japanese.
- `cloze` — show Japanese with one word blanked out (`target`), fill in the missing word.
- `choice` — show the question plus `choices` (A/B/C), type the letter.

Extra fields by type:

- `cloze`: `target` — the word to blank out in `japanese`
- `choice`: `choices` — array of option strings, `answer` — the correct letter

## Data and state

`~/.local/share/memoloop/` — user data (override with `MEMOLOOP_DATA_DIR`):

- `questions/<group>/*.json`
- `answers.json` — per-question points and show history

`~/.local/state/memoloop/` — runtime state (override with `MEMOLOOP_STATE`):

- `rules.json` (next-due per rule), `session.json` (paused, DND, queue, open pid),
  `current.json` (last prompt), `result.json` (last answer), `log/reminders.log`

**answers.json** — per-question answer data with points:

```json
{
  "t-greet-1": {
    "points": 110,
    "last_shown": 1793371387,
    "last_correct": 1793371387,
    "times_shown": 1,
    "times_correct": 1
  }
}
```

Scoring: base 100 points, correct +10, incorrect -10 (floor 0). Weight for
random selection: `100 / (points + 100)` — lower points = higher chance.
Points decay by half-life every `decay_hours` so unseen questions resurface.
Minimum `min_per_day` unique questions per day guaranteed.

## Floating popups (niri)

memoloop opens its prompt in a `foot` terminal. To make that window float
(centred, not tiled) under niri, add this to your `~/.config/niri/config.kdl`
— after any global window rules so it takes precedence:

    include optional=true "memoloop.kdl"

and place `niri/memoloop.kdl` at
`~/.config/niri/memoloop.kdl`. It matches `app-id="memoloop"` exactly, so
every other `foot` window keeps tiling. The size rule dimensions the window to
the term.sh frame (64 columns) so the popup box is centred.

`MOD+N` runs `memoloop ask` from `PATH`, so the installed binary in
`~/.local/bin` must be reachable from the shell that niri spawns.

## Directory tree

- `src/memoloop` — entry script (daemon + popup + scheduling)
- `lib/term.sh` — terminal renderer (vendored copy, like glyph-key's)
- `data/questions/questions.json` — legacy sample question set (no longer used)
- runtime state and logs live in `~/.local/state/memoloop/` (or `MEMOLOOP_STATE`)
- `tests/memoloop_test.sh` — basic automated tests
- `plans/` — product and technical plans
- `progress/` — session progress snapshots

## How simultaneous rules and an already-open popup are handled

Each rule keeps its own next-due time. If fixed and random both fire close
together, the first one opens its popup and the second is queued in
`state/session.json` (`queue`). While a popup is open, any further due rule
is queued rather than launching an overlapping terminal. When the user
dismisses the held window, the daemon launches the next queued rule.
Each prompt is logged separately with its rule id, so both rules are honoured
and none is silently merged or discarded.

## Restart, pause, and missed-prompt behaviour

- Restart: on start, `watch` recalculates each rule's next-due from now
  (fixed: now + fixed_seconds; random: now + random_min–random_max min).
- Pause: `./src/memoloop pause` stops all prompts; `resume` restarts them.
  Missed prompts during pause are skipped, not queued.
- DND: prompts due inside the DND window are skipped (no backlog).
- After answering or dismissing, that rule's timer resets from that moment.

## Assumptions, limitations, follow-up work

- Runs under a terminal emulator (`foot`) on Wayland/X11; no display → popups
  cannot open (foot errors out).
- The daemon runs the script that was installed when it started. Reinstalling
  restarts the service; after editing `src/memoloop` by hand, run
  `systemctl --user restart memoloop`.
- Japanese display/input assumes a UTF-8 locale and a font covering kana/kanji;
  verify with `memoloop ask fixed`.
- DND window is same-day only (no overnight windows) in this prototype.
- Follow-up: Tauri proof of concept (see `plans/tech-stack.md`), per-rule
  enable/disable, optional prompt bundling, `config` subcommands to edit
  pickup.set interactively.

## Reference projects (do not modify, no runtime dependency)

- `t-linux/cli-utilities/utilities/glyph-key` — popup terminal that accepts
  input and reflects its current state (pattern for `term.sh` + `foot --hold`).
- `t-linux/cli-utilities/utilities/desk-reminder` — interval scheduling and
  reminder behaviour (pattern for independent rules and state).
