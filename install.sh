#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

INSTALLER_NAME=memoloop
INSTALLER_INTEGRATION_DESC=' (the script, lib/term.sh, config, niri rules)'
INSTALLER_NO_INTEGRATION_DESC=' install the script only; no config or niri rules'

mode=--user
BIN_ONLY=0
_INSTALLER_NEXT_STEPS=""
rest=()
for arg in "$@"; do
  case "$arg" in
  --user | --system) mode="$arg" ;;
  --overwrite-data) MEMOLOOP_OVERWRITE_DATA=1 ;;
  --purge-data) MEMOLOOP_PURGE_DATA=1 ;;
  *) rest+=("$arg") ;;
  esac
done

if [ "$mode" = "--system" ]; then
  BIN_ONLY=1
  rest+=(--no-integration)
  INSTALLER_BIN_DIR=/usr/local/bin
fi
set -- ${rest[@]+"${rest[@]}"}

CONFIG_DIR="${MEMOLOOP_CONFIG_DIR:-$HOME/.config/memoloop}"
DATA_DIR="${MEMOLOOP_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/memoloop}"
STATE_DIR="${MEMOLOOP_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/memoloop}"
SYSTEMD_DIR="$HOME/.config/systemd/user"
NIRI_DIR="$HOME/.config/niri"
ZSH_ALIASES="$HOME/.config/zsh/my_zsh_aliases"
SERVICE_UNIT="memoloop.service"

. "$SCRIPT_DIR/lib/term.sh"
. "$SCRIPT_DIR/lib/installer.sh"

term_init

INSTALLER_EXTRA_HELP='
MODES
  --user      install under your own home (default)
  --system    install the script and lib into /usr/local (needs sudo);
              binary only, no user service, config or niri rules
  --overwrite-data  replace existing config, pickup set, intervals and questions
  --purge-data      (on uninstall) delete MemoLoop config, data and state

  By default, install and uninstall preserve all user data (config, pickup set,
  intervals, questions, answers, state, log).

HOOKS
  install_tool         copies memoloop and lib/term.sh into <bin>/.. and <bin>/../lib
  install_integration  config, niri rules, data/state migration

Reinstalling also removes a legacy memoloop.service unit; scheduling now lives
in intervald.'

lib_dir() {
  printf '%s/../lib' "$INSTALLER_BIN_DIR"
}

write_default() {
  local dest="$1" tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/memoloop.XXXXXX")
  cat >"$tmp"
  installer_do_section install -m 644 "$tmp" "$dest"
  rm -f "$tmp"
}

install_tool() {
  installer_do_section installer_as_root mkdir -p "$INSTALLER_BIN_DIR" "$(lib_dir)" || installer_die_unwritable
  installer_do_section installer_as_root install -m 755 "$SCRIPT_DIR/src/memoloop" "$INSTALLER_TARGET"
  installer_do_section installer_as_root install -m 644 "$SCRIPT_DIR/lib/term.sh" "$(lib_dir)/term.sh"
}

uninstall_tool() {
  installer_do_section_remove rm -f "$INSTALLER_TARGET"
  installer_do_section_remove rm -f "$(lib_dir)/term.sh"
  installer_do_section_remove rmdir "$(lib_dir)" 2>/dev/null || true
}

install_integration() {
  installer_do_section mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$STATE_DIR" "$STATE_DIR/log"

  if [ -f "$SYSTEMD_DIR/$SERVICE_UNIT" ]; then
    installer_do_section systemctl --user stop "$SERVICE_UNIT" 2>/dev/null || true
    installer_do_section_remove systemctl --user disable "$SERVICE_UNIT" 2>/dev/null || true
    installer_do_section_remove rm -f "$SYSTEMD_DIR/$SERVICE_UNIT"
    installer_do_section_remove systemctl --user daemon-reload
  fi

  if [ -f "$DATA_DIR/intervals.conf" ] && [ ! -f "$CONFIG_DIR/intervals.conf" ]; then
    installer_do_section mv "$DATA_DIR/intervals.conf" "$CONFIG_DIR/intervals.conf"
  fi

  if [ ! -f "$CONFIG_DIR/intervals.conf" ] || [ "${MEMOLOOP_OVERWRITE_DATA:-}" = "1" ]; then
    installer_do_section install -m 644 "$SCRIPT_DIR/data/intervals.conf" "$CONFIG_DIR/intervals.conf"
  fi

  if [ ! -f "$CONFIG_DIR/config.conf" ] || [ "${MEMOLOOP_OVERWRITE_DATA:-}" = "1" ]; then
    installer_do_section install -m 644 "$SCRIPT_DIR/data/config.conf" "$CONFIG_DIR/config.conf"
  fi

  if [ ! -f "$CONFIG_DIR/pickup.set" ] || [ "${MEMOLOOP_OVERWRITE_DATA:-}" = "1" ]; then
    installer_do_section install -m 644 "$SCRIPT_DIR/data/pickup.set" "$CONFIG_DIR/pickup.set"
  fi

  if [ "${MEMOLOOP_OVERWRITE_DATA:-}" = "1" ] && [ -d "$DATA_DIR/questions" ]; then
    installer_do_section rm -rf "$DATA_DIR/questions"
  fi

  if [ ! -d "$DATA_DIR/questions" ]; then
    installer_do_section cp -r "$SCRIPT_DIR/data/questions" "$DATA_DIR/questions"
  fi

  local legacy old_state old_log
  old_state="${XDG_STATE_HOME:-$HOME/.local/state}"
  old_log="$HOME/.local/log"
  for legacy in current.json result.json; do
    if [ -f "$old_state/$legacy" ] && [ ! -f "$STATE_DIR/$legacy" ]; then
      installer_do_section mv "$old_state/$legacy" "$STATE_DIR/$legacy"
    fi
  done
  if [ -f "$old_log/reminders.log" ] && [ ! -f "$STATE_DIR/log/reminders.log" ]; then
    installer_do_section mv "$old_log/reminders.log" "$STATE_DIR/log/reminders.log"
  fi

  installer_do_section mkdir -p "$NIRI_DIR"
  if [ -f "$NIRI_DIR/memoloop.kdl" ] && ! cmp -s "$SCRIPT_DIR/niri/memoloop.kdl" "$NIRI_DIR/memoloop.kdl"; then
    installer_do_section cp "$NIRI_DIR/memoloop.kdl" "$NIRI_DIR/memoloop.kdl.bak"
  fi
  installer_do_section install -m 644 "$SCRIPT_DIR/niri/memoloop.kdl" "$NIRI_DIR/memoloop.kdl"
  if [ -f "$NIRI_DIR/config.kdl" ] && ! grep -qF 'include optional=true "memoloop.kdl"' "$NIRI_DIR/config.kdl"; then
    installer_do_section sh -c "printf '%s\n' '// >>> memoloop managed include >>>' 'include optional=true \"memoloop.kdl\"' '// <<< memoloop managed include <<<' >>'$NIRI_DIR/config.kdl'"
  fi

  if command -v niri >/dev/null 2>&1 && pgrep -x niri >/dev/null 2>&1; then
    installer_do_section sh -c "niri msg action load-config-file --path '$NIRI_DIR/config.kdl'" || true
  fi

  _INSTALLER_NEXT_STEPS="Config:   $CONFIG_DIR
Data:     $DATA_DIR
State:    $STATE_DIR
Run:      memoloop --help
Popup:    MOD+N (niri) or memoloop ask
Interval: intervald status"
}

uninstall_integration() {
  installer_do_section systemctl --user stop "$SERVICE_UNIT" 2>/dev/null || true
  installer_do_section_remove systemctl --user disable "$SERVICE_UNIT" 2>/dev/null || true
  installer_do_section_remove rm -f "$SYSTEMD_DIR/$SERVICE_UNIT"
  installer_do_section_remove systemctl --user daemon-reload

  if [ -f "$ZSH_ALIASES" ] && grep -qF '# >>> memoloop managed alias >>>' "$ZSH_ALIASES"; then
    installer_do_section_remove sed -i '/^# >>> memoloop managed alias >>>$/,/^# <<< memoloop managed alias <<<$/{d;}' "$ZSH_ALIASES"
  fi

  installer_do_section_remove rm -f "$NIRI_DIR/memoloop.kdl"
  if [ -f "$NIRI_DIR/config.kdl" ] && grep -qF '// >>> memoloop managed include >>>' "$NIRI_DIR/config.kdl"; then
    installer_do_section_remove sed -i '\|^// >>> memoloop managed include >>>$|,\|^// <<< memoloop managed include <<<$|{d;}' "$NIRI_DIR/config.kdl"
    installer_do_section_remove sh -c "niri msg action load-config-file --path '$NIRI_DIR/config.kdl'" || true
  fi

  if [ "${MEMOLOOP_PURGE_DATA:-}" = "1" ]; then
    installer_do_section_remove rm -rf "$CONFIG_DIR" "$DATA_DIR" "$STATE_DIR"
  else
    installer_do_section_remove "kept: $CONFIG_DIR"
    installer_do_section_remove "kept: $DATA_DIR"
    installer_do_section_remove "kept: $STATE_DIR"
  fi
}

installer_run "$@"

if [ "$BIN_ONLY" -eq 1 ]; then
  term_status "system install" "$TERM_MARK_PLAIN" "binary only · no config or niri rules were created"
fi
