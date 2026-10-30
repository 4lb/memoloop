# Progress reports

This directory tracks the project across multiple agents and platforms. Each
agent session appends one report file here so the next agent can resume without
re-discovering the state.

## File naming convention

`[date]-[short-description].md`

- `date` = YYMMDD-HHMM (local time of the session)
- `short-description` = lowercase, hyphen-separated, ~2-4 words

Example: `261030-1324-repo-groundwork.md`

## Report conventions

Every report file starts with a short frontmatter block identifying the writer:

```
## Session
- who: <agent name / AI CLI tool, e.g. Kilo (kilo AI CLI tool, runs inside kilo)>
- model: <model id, e.g. kilo/nvidia/nemotron-3.5-super-vl:free>
- platform: <host / OS>
- worktree: <absolute path>
- date: <ISO date>
- timestamp: <YYMMDD-HHMM>
```

Then a concise summary of:
1. What was done this session
2. Files created / modified
3. Commands run (and any that could not be run)
4. Where to resume next (exact next step)
5. Open questions / blockers

Keep reports short and factual. No preamble, no politeness padding. The next
agent should be able to read the latest report and continue immediately.

## Orchestration

Agents running on different platforms append reports here. The latest file is
the source of truth for "where we are". Before starting work, read the most
recent `progress/*.md` file plus `plans/AGENT.md`.
A thin pointer at repo root (`./pickup.md`) redirects agents to the latest
`progress/*.md` snapshot so work can be resumed with a single read.

## Writing progress

When prompted with "write progress", write one snapshot file named
`YYMMDD-HHMM-progress-<short-description>.md` with frontmatter (who/model/
platform/worktree/date/timestamp), what was done, where to resume next, and
open questions/blockers. That's it — write one file when asked.
