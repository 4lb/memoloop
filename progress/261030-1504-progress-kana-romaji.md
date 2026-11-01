## Session
- who: Kilo (kilo AI CLI tool, runs inside kilo)
- model: kilo/nvidia/nemotron-3.5-super-vl:free
- platform: linux (CachyOS, niri 26.04, Wayland)
- worktree: /mnt/r/projects/a-memoloop
- date: 2026-10-30
- timestamp: 261030-1504

## What was done

Improved question quality per user feedback:

1. **Choice questions**: Options are now English-only (A. big / B. small / C. new) instead of revealing the kanji answer. Note line hidden for choice type to prevent answer leakage.

2. **Reverse translation questions**: Added kana + romaji to accepted answers for all reverse questions. E.g. for 'family' (家族): accepted = [家族, かぞく, kazoku]. Applied to all groups: greetings, family, weather, conversation, adjectives, verbs, nouns.

3. **Pretty-printed all JSON question files** with `jq .` for readability.

4. Tests: 19 passed, 0 failed.

5. Committed b35bae5 and pushed to origin main.

## Files modified (in repo)

- data/questions/questions.json — legacy file, kana+romaji added to reverse questions, English-only choice options, pretty-printed
- src/memoloop — choice type no longer displays note line
- progress/261030-1504-progress-kana-romaji.md — this snapshot
- progress/pickup.md — updated pointer

## Files modified (outside repo, ~/.config/memoloop/)

- questions/*/*.json — all 7 group files, kana+romaji added to reverse, pretty-printed

## Where to resume next

- Consider adding more question patterns (fill-in-multiple-blanks, matching)
- Consider per-rule enable/disable
- Consider `config` subcommands to edit intervals/pickup.set interactively

## Open questions / blockers

- None blocking.