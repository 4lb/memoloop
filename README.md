# memoloop

MemoLoop — Linux prototype of a Japanese desktop language-learning question
popup.

Project: directory `a-memoloop`, name `memoloop` (MemoLoop).
PopLoop — the quick-popup feature (marketing / internal naming).
Resume: `read ./pickup.md`

## Status

MemoLoop is now a question-display application only. Scheduling lives in the
separate [`intervald`](intervald/README.md) tool: it spawns `memoloop ask` on
fixed and randomized intervals.

See [`plans/AGENT.md`](plans/AGENT.md) for the product plan,
[`plans/first-steps.md`](plans/first-steps.md) for the build stages,
[`plans/app-plan.md`](plans/app-plan.md) for the revised product plan, and
[`plans/config-scoring-plan.md`](plans/config-scoring-plan.md) for the config
and scoring design.

## What memoloop does

- `memoloop ask` opens a `foot` popup showing a Japanese prompt with its
  English meaning, answer instructions, and a question type.
- Accepts typed answers, checks them against one or more accepted answers,
  shows accepted/not-accepted feedback with the intended answer, and allows
  dismissing without answering.
- After feedback, `n` opens another question in the same window; any other key
  closes it.
- Answer scoring: base 100 points, correct +10, incorrect -10 (floor 0).
  Weighted random selection favours low-point questions, with a time decay so
  unseen questions resurface. A minimum number of unique questions per day is
  guaranteed.
- Logs each prompt to `log/reminders.log`.

It does not schedule anything, run a daemon, manage DND/pause state, or spawn
Anki. Configure those jobs in intervald.

## Dependencies

- `bash` (5.x)
- `foot` terminal emulator (popup windows)
- `jq` (JSON processing)
- `awk` (floating-point math for scoring weights)
- A UTF-8 locale and a font that covers Japanese (kana/kanji) for correct display.

Install (CachyOS/Arch example):

    paru -S foot jq

## Install

    ./install.sh

This installs `src/memoloop` and `lib/term.sh`, writes the default config,
copies the question data, and installs the niri floating-window rule. It also
removes a legacy `memoloop.service` unit; memoloop no longer has a daemon.

Uninstall while keeping data:

    ./install.sh uninstall

Purge config, data and state:

    ./install.sh uninstall --purge-data

## Run instructions

All commands run from the repo root:

    ./src/memoloop setup        # initialise state, log, data and config directories
    ./src/memoloop config       # show effective configuration
    ./src/memoloop test         # launch one test prompt immediately
    ./src/memoloop ask [name]   # show one question popup (name defaults to manual)

Tests:

    ./tests/memoloop_test.sh

## Scheduling with intervald

`intervald` reads `~/.config/intervald/config.yaml` and runs any command on
fixed or re-rolled random intervals. The shipped jobs are:

    settings:
      terminal: "foot -e"

    jobs:
      memoloop:
        command: "memoloop ask"
        terminal: true
        schedule:
          - every: 45m
          - random: [15m, 30m]

      anki:
        command: "anki"
        schedule:
          - every: 45m
          - random: [15m, 30m]

Install, configure and inspect it with:

    intervald check
    intervald status
    intervald fire memoloop
    intervald reload
    systemctl --user status intervald.service

Full reference: [`intervald/README.md`](intervald/README.md).

## Configuration (`~/.config/memoloop/`)

**intervals.conf** — question-selection parameters:

```
decay_hours=24
min_per_day=10
```

- `decay_hours`: half-life for answer-point decay in hours (default 24)
- `min_per_day`: minimum unique questions shown per day (default 10)

Override at run time through the environment:

    MEMOLOOP_DECAY_HOURS=12 MEMOLOOP_MIN_PER_DAY=5 ./src/memoloop ask

`MEMOLOOP_NOHELP` also exists for suppressing the post-question key hint.

**config.conf** — paths and display:

```
nohelp=true
USER_DATA_DIR="~/.local/share/memoloop"
```

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

- `current.json` (last prompt), `result.json` (last answer),
  `log/reminders.log`

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

- `src/memoloop` — question popup and scoring
- `lib/term.sh` — terminal renderer (vendored copy, like glyph-key's)
- `intervald/` — standalone interval runner (code, unit, example config, tests)
- `data/questions/<group>/*.json` — question sets
- `docs/question-format.md` — question schema
- `niri/memoloop.kdl` — floating popup rule
- `tests/memoloop_test.sh` — memoloop tests
- `plans/` — product and technical plans
- `progress/` — session progress snapshots

## Assumptions and limitations

- Runs under a terminal emulator (`foot`) on Wayland/X11; no display → popups
  cannot open.
- Japanese display/input assumes a UTF-8 locale and a font covering kana/kanji;
  verify with `memoloop ask`.
- Spaced repetition / SuperMemo scheduling is explicitly out of scope.
- Cross-platform packaging, system-wide keyboard interception, OS locking,
  accounts, cloud sync and Anki integration are out of scope.

## Reference projects (do not modify, no runtime dependency)

- `t-linux/cli-utilities/utilities/glyph-key` — popup terminal that accepts
  input and reflects its current state (pattern for `term.sh` + `foot --hold`).
- `t-linux/cli-utilities/utilities/desk-reminder` — interval scheduling and
  reminder behaviour (reference for intervald).
