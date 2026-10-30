# memoloop

MemoLoop — Linux prototype of a Japanese desktop language-learning app.

Project: directory `a-memoloop`, name `memoloop` (MemoLoop).
PopLoop — the quick-popup feature (marketing / internal naming).
Resume: `read ./pickup.md`

## Status

Prototype in development — see [`plans/AGENT.md`](plans/AGENT.md) for the
product plan, [`plans/first-steps.md`](plans/first-steps.md) for the build
stages, and [`plans/app-plan.md`](plans/app-plan.md) for the revised product
plan. This directory tree holds the groundwork only; the full implementation
has not been written yet.

## Reference projects (do not modify, no runtime dependency)

- `t-linux/cli-utilities/utilities/glyph-key` — popup terminal that accepts
  input, displays Japanese text correctly, and reflects its current state.
- `t-linux/cli-utilities/utilities/desk-reminder` — interval scheduling and
  reminder behavior.

## Directory tree

- `plans/` — product and technical plans
- `src/` — prototype source (entry script)
- `lib/` — self-contained terminal renderer (own copy, like glyph-key's)
- `data/questions/` — local sample Japanese question set
- `docs/` — run and configuration instructions
- `tests/` — basic automated tests
- `state/` — runtime state (gitignored)
- `log/` — runtime logs (gitignored)
