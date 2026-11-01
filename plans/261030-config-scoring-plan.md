# Plan: ~/.config/memoloop/ config system + answer scoring

## Goals

1. Move intervals configuration out of source into `~/.config/memoloop/intervals.conf`
2. Move questions data into a group-based directory structure under `~/.config/memoloop/questions/`
3. Enable/disable question groups via a "pickup set" file
4. Track answers in a cache with a point system
5. Weighted random question selection favoring low-point questions, with time decay
6. Guarantee minimum ~10 different questions per day

## Directory layout

### `~/.config/memoloop/` (configuration)
```
~/.config/memoloop/
├── intervals.conf        # fixed_seconds, random_min, random_max, decay_hours, min_per_day
├── pickup.set            # enabled question group ids (one per line)
└── questions/
    ├── greetings/
    │   └── basics.json
    ├── family/
    │   └── relatives.json
    └── ...
```

### `~/.cache/memoloop/` (runtime cache - answers/points)
```
~/.cache/memoloop/
└── answers.json          # answer cache with points + timestamps
```

## File formats

### intervals.conf
```
fixed_seconds=2700
random_min=900
random_max=1800
```

### pickup.set (enabled groups)
```
greetings
family
weather
```
Only groups listed here are in the loop. Comments with `#` allowed.

### questions/<group>/<file>.json
Same entry format as current `questions.json`, plus optional `group` field:
```json
[
  {"id": "g001", "type": "translation", "japanese": "こんにちは", "english": "Hello", "accepted": ["こんにちは", "konnichiwa"]}
]
```

### answers.json
```json
{
  "q001": {"points": 3, "last_shown": 1793367393, "last_correct": 1793367393, "times_shown": 2, "times_correct": 2},
  "q002": {"points": -2, "last_shown": 1793366000, "last_correct": null, "times_shown": 3, "times_correct": 1}
}
```

## Scoring algorithm

### Points
- Base starting points: 100
- Correct answer: +10 points
- Incorrect/wrong answer: -10 points (floor at 0)
- Dismissed/skipped: 0 points

### Weight for random selection
Base weight = `100 / (points + 100)` → points of 0 gives weight 1.0 (max), points of 100 gives weight 0.5, points of 200 gives weight 0.33
Lower points = higher chance of being shown.

### Time decay
If a question hasn't been shown for `decay_hours` (default 24h), its effective points decay toward 0:
```
effective_points = points * decay_factor
decay_factor = 0.5 ^ (hours_since_last_shown / decay_hours)
```
This ensures old questions eventually resurface even with high points.

### Minimum per day guarantee
Track `shown_today` set. If fewer than 10 unique questions shown today, force-select from unshown questions before applying weights.

## Code changes

### src/memoloop
- `config_dir` defaults to `~/.config/memoloop`, overridable by `MEMOLOOP_CONFIG_DIR`
- Load intervals from `intervals.conf` (fall back to source defaults if missing)
- Load enabled groups from `pickup.set` (fall back to all groups if missing)
- Load questions from all `.json` files under `questions/<group>/` for enabled groups
- Load/save `answers.json` for point tracking
- Weighted random selection using points + decay
- Daily minimum guarantee
- `ask` updates points based on result

### Tests
- Update `tests/memoloop_test.sh` for new config loading and scoring logic
- Add tests for point updates, weight calculation, decay, daily minimum

## Assumptions

- `~/.config/memoloop/` created on first `setup`
- Existing `data/questions/questions.json` remains as fallback/example but is no longer the source
- Points are per-question-id, stable across restarts via `answers.json`
- `decay_hours` configurable in `intervals.conf` (default 24)

## Open questions (for user)

- Default decay_hours value
- Points floor/ceiling values
- Whether `pickup.set` defaults to "all groups" or empty
- Location of legacy `data/questions/` (keep as example or remove)

## Acceptance

Review this plan. If acceptable, I'll implement in order:
1. Config dir + intervals.conf loading
2. Questions group directory + pickup.set
3. Answer cache + points
4. Weighted selection + daily minimum
5. Tests + commit
