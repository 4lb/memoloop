#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

INSTALLER_NAME=memoloop

INSTALLER_INTEGRATION_DESC=' (the script, lib/term.sh, systemd user service, config and zsh alias)'
INSTALLER_NO_INTEGRATION_DESC=' install the script only; no systemd unit, config or alias'

mode="--user"
rest=()
while [ $# -gt 0 ]; do
	case "$1" in
	--user) mode="--user" ;;
	--system) mode="--system" ;;
	*) rest+=("$1") ;;
	esac
	shift
done
set -- "${rest[@]+"${rest[@]}"}"

case "$mode" in
--user)
	INSTALLER_BIN_DIR="$HOME/.local/bin"
	INSTALLER_LIB_DIR="$INSTALLER_BIN_DIR/../lib"
	SYSTEMD_DIR="$HOME/.config/systemd/user"
	CONFIG_DIR="$HOME/.config/memoloop"
	CACHE_DIR="$HOME/.cache/memoloop"
	ZSH_ALIASES="$HOME/.config/zsh/my_zsh_aliases"
	SUDO=""
	;;
--system)
	INSTALLER_BIN_DIR="/usr/local/bin"
	INSTALLER_LIB_DIR="$INSTALLER_BIN_DIR/../lib"
	SYSTEMD_DIR="/etc/systemd/system"
	CONFIG_DIR="/etc/memoloop"
	CACHE_DIR="/var/cache/memoloop"
	ZSH_ALIASES="/etc/zsh/zshrc"
	SUDO="sudo"
	;;
esac

INSTALLER_TARGET="$INSTALLER_BIN_DIR/memoloop"
SERVICE_UNIT="memoloop.service"
ALIAS_NAME="memoloop"
ALIAS_LINE="alias memoloop='$INSTALLER_TARGET ask'"

. "$SCRIPT_DIR/lib/term.sh"
. "$SCRIPT_DIR/lib/installer.sh"

term_init

INSTALLER_EXTRA_HELP='
MODES
  --user      install under your own home (default)
  --system    install system-wide, with sudo

  These choose four directories rather than one, so they are not another name
  for --install-path: a system-wide install puts the unit in /etc/systemd and
  the config in /etc as well as the script in /usr/local/bin.

HOOKS
  install_tool      copies memoloop and lib/term.sh to the bin/lib directories
  install_integration creates the systemd user unit, memoloop config and zsh alias

The zsh alias is appended to $HOME/.config/zsh/my_zsh_aliases (--user) or
/etc/zsh/zshrc (--system) only if it is not already there.'

install_tool() {
	installer_do_section installer_as_root mkdir -p "$INSTALLER_LIB_DIR" || installer_die_unwritable
	installer_do_section installer_as_root install -m 755 "$SCRIPT_DIR/src/memoloop" "$INSTALLER_TARGET"
	installer_do_section installer_as_root install -m 644 "$SCRIPT_DIR/lib/term.sh" "$INSTALLER_LIB_DIR/term.sh"
}

uninstall_tool() {
	installer_do_section_remove rm -f "$INSTALLER_TARGET"
	installer_do_section_remove rm -f "$INSTALLER_LIB_DIR/term.sh"
	installer_do_section_remove rmdir "$INSTALLER_LIB_DIR" 2>/dev/null || true
}

install_integration() {
	local svc_tmp
	svc_tmp=$(mktemp "${TMPDIR:-/tmp}/memoloop.service.XXXXXX")
	cat >"$svc_tmp" <<'UNITEOF'
[Unit]
Description=MemoLoop Japanese study reminders
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/memoloop watch
Restart=on-failure
RestartSec=30
Environment=MEMOLOOP_CONFIG_DIR=%h/.config/memoloop
Environment=MEMOLOOP_CACHE_DIR=%h/.cache/memoloop

[Install]
WantedBy=graphical-session.target
UNITEOF

	installer_do_section installer_as_root mkdir -p "$SYSTEMD_DIR"
	installer_do_section installer_as_root install -m 644 "$svc_tmp" "$SYSTEMD_DIR/$SERVICE_UNIT"
	rm -f "$svc_tmp"

	installer_do_section installer_as_root mkdir -p "$CONFIG_DIR"
	if [ ! -f "$CONFIG_DIR/intervals.conf" ]; then
		local conf_tmp
		conf_tmp=$(mktemp "${TMPDIR:-/tmp}/memoloop-intervals.XXXXXX")
		cat >"$conf_tmp" <<'CONFEOF'
fixed_seconds=2700
random_min=15
random_max=30
decay_hours=24
min_per_day=10
nohelp=false
CONFEOF
		installer_do_section installer_as_root install -m 644 "$conf_tmp" "$CONFIG_DIR/intervals.conf"
		rm -f "$conf_tmp"
	fi

	if [ ! -f "$CONFIG_DIR/pickup.set" ]; then
		local pickup_tmp
		pickup_tmp=$(mktemp "${TMPDIR:-/tmp}/memoloop-pickup.XXXXXX")
		cat >"$pickup_tmp" <<'PICKUPEOF'
greetings
family
weather
conversation
adjectives
verbs
nouns
PICKUPEOF
		installer_do_section installer_as_root install -m 644 "$pickup_tmp" "$CONFIG_DIR/pickup.set"
		rm -f "$pickup_tmp"
	fi

	installer_do_section installer_as_root mkdir -p "$(dirname "$ZSH_ALIASES")"
	if [ ! -f "$ZSH_ALIASES" ] || ! grep -qF "alias memoloop=" "$ZSH_ALIASES"; then
		installer_do_section sh -c "cat >> '$ZSH_ALIASES' <<'EOF'

alias memoloop='$INSTALLER_TARGET'
EOF"
	fi

	installer_do_section installer_as_root mkdir -p "$HOME/.config/niri"
	installer_do_section installer_as_root install -m 644 "$SCRIPT_DIR/niri/memoloop.kdl" "$HOME/.config/niri/memoloop.kdl"
	if [ -f "$HOME/.config/niri/config.kdl" ] && ! grep -qF 'include optional=true "memoloop.kdl"' "$HOME/.config/niri/config.kdl"; then
		niri_inc_tmp=$(mktemp "${TMPDIR:-/tmp}/memoloop-niri.XXXXXX")
		printf 'include optional=true "memoloop.kdl"\n' >"$niri_inc_tmp"
		installer_do_section sh -c "cat '$niri_inc_tmp' >> '$HOME/.config/niri/config.kdl'"
		rm -f "$niri_inc_tmp"
	fi
}

uninstall_integration() {
	installer_remove rm -f "$SYSTEMD_DIR/$SERVICE_UNIT"
	installer_remove rm -rf "$CONFIG_DIR"
	installer_remove rm -rf "$CACHE_DIR"
	if [ -f "$ZSH_ALIASES" ] && grep -qF "alias memoloop=" "$ZSH_ALIASES"; then
		installer_remove sed -i '/^# memoloop$/,+1d' "$ZSH_ALIASES"
	fi
	installer_remove rm -f "$HOME/.config/niri/memoloop.kdl"
	if [ -f "$HOME/.config/niri/config.kdl" ]; then
		installer_remove sed -i '/^include optional=true "memoloop.kdl"$/d' "$HOME/.config/niri/config.kdl"
	fi
}

installer_run "$@"
