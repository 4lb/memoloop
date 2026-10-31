# memoloop — progress snapshot

## Active items (done)
- [x] cleanup-before-install option in install.sh (`--clean`)
- [x] install missing/basic question sets without overwriting edited user question data
- [x] config/data directory split:
  - `config.conf` + (future config) in `~/.config/memoloop/`
  - `questions/` + `pickup.set` + `answers.json` in `~/.local/share/memoloop/` (XDG data dir)
- [x] align memoloop to read `config.conf` (was mismatched `intervals.conf`)
- [x] align tests to new paths — 19/19 passing

## Open / environment
- `foot` popup doesn't render in this headless sandbox (exits instantly;
  harmless `wayland.c: xdg-toplevel-icon` warning). Ask logic runs correctly
  under `FOOT_POPUP=1 memoloop ask`.
- New question set files (`data/questions/{grammar,kana,kanji,vocabulary}/`)
  are untracked in the working tree; not committed.

## Commands
- `./install.sh [--clean] [--dry-run] [--no-integration] [--purge-data] [--help]`
- `./install.sh --uninstall` removes integration; keeps user data unless `--purge-data`
- fix: window not showing on error - fix die(), launch_popup(), cmd_ask() terminal handling, and config directory initialization
