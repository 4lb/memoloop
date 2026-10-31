# Memoloop Repository Audit

**Date**: 2026-10-30
**Purpose**: Unravel the current state of the repository, reconcile progress snapshots with actual code, and propose fixes.

---

## Repository State Overview

- **Branch**: `main`, 2 commits behind `origin/main`
- **Modified files**: `data/questions/questions.json`, `install.sh`
- **Untracked files**: `install.sh.bak`, `data/intervals.conf`, `data/pickup.set`, `data/questions/grammar/`, `data/questions/kana/`, `data/questions/kanji/`, `data/questions/vocabulary/`
- **Stale runtime state**: `state/pidfile` contains PID 3446834

---

## Issues Found

### 1. Stale `state/pidfile` from old daemon management

**Location**: `state/pidfile` contains PID 3446834

**Progress snapshot claim** (261030-1734 - systemd-unification):
> - Removed `PID_FILE` and all standalone pid management code
> - Only ONE instance runs (the systemd service), no duplicate daemons

**Actual code state**: While `cmd_start` and `cmd_stop` in `src/memoloop` now use `systemctl --user start/stop`, the `state/pidfile` still exists with a stale PID from the old daemon-based management. The `PID_FILE` variable reference still exists in the code paths. This inconsistency should be cleaned up — the pidfile and its associated code should be removed entirely since start/stop now use systemctl.

**Fix**: Remove `state/pidfile` and clean up any pidfile references in `src/memoloop`. The `cmd_start`/`cmd_stop` should rely solely on `systemctl --user`.

---

### 2. `install.sh --uninstall` does NOT remove all traces by default

**Location**: `install.sh:219-239`, `uninstall_integration()` function

**Progress snapshot claim** (261030-1746 - uninstall-fix):
> Fixed install.sh --uninstall to properly remove ALL traces of memoloop
> Fully tested: install → verify everything present → uninstall → verify everything removed (0 traces remaining)

**Actual code state**: The `uninstall_integration()` function only removes config/cache when `MEMOLOOP_PURGE_DATA=1` is explicitly passed. By default, it preserves user config, pickup.set, and questions — keeping "traces" behind. The `--purge-data` flag was added later (seen in git history `a3f8f33`), but the default uninstall behavior still keeps user data.

**Discrepancy**: The snapshot claims "0 traces remaining" after uninstall, but the actual code requires `--purge-data` to achieve that. Without the flag, config dir, cache dir, and zsh alias survive uninstall.

**Fix**: Either:
- Make the default uninstall remove all traces (remove the `MEMOLOOP_PURGE_DATA` guard), OR
- Update the progress snapshot to document that `--purge-data` is required for a complete uninstall

---

### 3. Untracked `install.sh.bak` backup file

**Location**: `install.sh.bak` (untracked)

This is a backup of the original `install.sh` before the `--purge-data`/`--overwrite-data` flags were added. It's leftover from previous agent work and should be removed. It serves no purpose in the repo and could cause confusion.

**Fix**: Delete `install.sh.bak`.

---

### 4. `data/questions/questions.json` format changes

**Location**: `data/questions/questions.json`

**Git diff shows**: Accepted answers were reformatted from simple values/arrays to nested JSON arrays. Example:

```diff
-    "accepted": ["ありがとう", "arigatou", "arigato", "ありがとうござい", "arigatou gozaimasu"],
+    "accepted": [
+      "ありがとう",
+      "arigatou",
+      "arigato",
+      "ありがとうござい",
+      "arigatou gozaimasu"
+    ],
```

The reformatting is consistent throughout the file, and tests pass (19/19), but the change may have been unnecessary and could introduce subtle issues if any code path expects the previous flat format.

**Fix**: No functional fix needed — tests pass. Document the format change if desired, or revert if the nested format causes issues elsewhere.

---

### 5. Untracked data files `data/intervals.conf` and `data/pickup.set`

**Location**: `data/intervals.conf`, `data/pickup.set`

These files exist in the data directory but are not tracked by git. They appear to be created by the install script running outside the repo (not via `./install.sh` within the repo). They contain:

- `intervals.conf`: `fixed_seconds=2700`, `random_min=15`, `random_max=30`, `decay_hours=24`, `min_per_day=10`
- `pickup.set`: lists 7 question groups (greetings, family, weather, conversation, adjectives, verbs, nouns)

These are user data files that should either be tracked (if they're part of the initial setup) or excluded via `.gitignore`. Currently `.gitignore` only ignores `state/`, `log/`, and editor files, not `data/`.

**Fix**: Either add these to `.gitignore` or commit them as part of the prototype's default data. Given the `.gitignore` comment "Runtime state and logs (kept inside the repo for the prototype, but never committed)", these data files should likely be added to `.gitignore` or the `.gitignore` updated to cover `data/` as runtime state.

---

### 6. `install.sh` has new `--purge-data` and `--overwrite-data` flags

**Location**: `install.sh:17-22`, `install.sh:223-226`, `install.sh:148-150`

These flags were added in commit `a3f8f33` (`a3f8f33 NOHELP defaults to true`) and subsequent commits. They change the behavior of `install` and `uninstall`:

- `--purge-data`: On uninstall, also delete config and cache directories
- `--overwrite-data`: During install, replace existing config, pickup.set, and questions

These are improvements, but they change the contract documented in earlier progress snapshots (e.g., 261030-1714). The flags are functional and tests pass, but the progression of changes should be noted.

**Fix**: No code fix needed — the flags are working correctly. Document in the audit.

---

### 7. Niri config not present in current environment

**Location**: `~/.config/niri/config.kdl` (not found)

The install script creates niri integration (config.kdl include + memoloop.kdl), but no niri config was found in the current environment. This is expected if memoloop was never installed via the script in this environment, or if the config was cleaned up.

**Fix**: Not a code issue — expected if not installed. Document for future installs.

---

## Summary of Changes Needed

| # | File | Issue | Fix |
|---|------|-------|-----|
| 1 | `state/pidfile` | Stale PID from old daemon mgmt | Delete the file; clean up pidfile references in `src/memoloop` |
| 2 | `install.sh` | Uninstall doesn't remove traces by default | Either remove `MEMOLOOP_PURGE_DATA` guard for default uninstall, or update snapshot docs |
| 3 | `install.sh.bak` | Untracked backup file | Delete |
| 4 | `data/questions/questions.json` | Format change (arrays vs flat) | No fix needed; tests pass |
| 5 | `data/intervals.conf`, `data/pickup.set` | Untracked data files | Add to `.gitignore` or commit as default data |
| 6 | `install.sh` | New `--purge-data`/`--overwrite-data` flags | Document; functional, tests pass |
| 7 | `~/.config/niri/config.kdl` | Not present | Expected; not a repo issue |

---