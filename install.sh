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
	--overwrite-data) MEMOLOOP_OVERWRITE_DATA=1 ;;
	--purge-data) MEMOLOOP_PURGE_DATA=1 ;;
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
	CACHE_DIR="$HOME/.local/share/memoloop"
	USER_DATA_DIR="$HOME/.local/share/memoloop"
	ZSH_ALIASES="$HOME/.config/zsh/my_zsh_aliases"
	SUDO=""
	;;
--system)
	INSTALLER_BIN_DIR="/usr/local/bin"
	INSTALLER_LIB_DIR="$INSTALLER_BIN_DIR/../lib"
	SYSTEMD_DIR="/etc/systemd/system"
	CONFIG_DIR="/etc/memoloop"
	CACHE_DIR="/var/lib/memoloop"
	USER_DATA_DIR="/var/lib/memoloop"
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
  --overwrite-data  replace existing MemoLoop config, pickup set and questions during install
  --purge-data      (on uninstall) also delete MemoLoop config and cache

  By default, install and uninstall preserve all user data (config, pickup set,
  questions, answers). Use --overwrite-data or --purge-data only when you
  explicitly want to replace/remove user data.

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
Environment=MEMOLOOP_CACHE_DIR=%h/.local/share/memoloop

[Install]
WantedBy=graphical-session.target
UNITEOF

	installer_do_section installer_as_root install -m 644 "$svc_tmp" "$SYSTEMD_DIR/$SERVICE_UNIT"
	rm -f "$svc_tmp"

	installer_do_section installer_as_root mkdir -p "$USER_DATA_DIR"
	installer_do_section installer_as_root mkdir -p "$CONFIG_DIR"

	# intervals.conf goes into user data directory per plan
	if [ ! -f "$USER_DATA_DIR/intervals.conf" ] || [ "${MEMOLOOP_OVERWRITE_DATA:-}" = "1" ]; then
		local conf_tmp
		conf_tmp=$(mktemp "${TMPDIR:-/tmp}/memoloop-intervals.XXXXXX")
		cat >"$conf_tmp" <<'CONFEOF'
fixed_seconds=2700
random_min=15
random_max=30
decay_hours=24
min_per_day=10
CONFEOF
		installer_do_section installer_as_root install -m 644 "$conf_tmp" "$USER_DATA_DIR/intervals.conf"
		rm -f "$conf_tmp"
	fi

	if [ ! -f "$CONFIG_DIR/conf.conf" ] || [ "${MEMOLOOP_OVERWRITE_DATA:-}" = "1" ]; then
		local conf_tmp
		conf_tmp=$(mktemp "${TMPDIR:-/tmp}/memoloop-conf.XXXXXX")
		cat >"$conf_tmp" <<'CONFEOF'
nohelp=true
USER_DATA_DIR="$HOME/.local/share/memoloop"
CONFEOF
		installer_do_section installer_as_root install -m 644 "$conf_tmp" "$CONFIG_DIR/conf.conf"
		rm -f "$conf_tmp"
	fi

	if [ ! -f "$CONFIG_DIR/pickup.set" ] || [ "${MEMOLOOP_OVERWRITE_DATA:-}" = "1" ]; then
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

	# Existing question sets are user data. Replace them only on explicit request.
	if [ "${MEMOLOOP_OVERWRITE_DATA:-}" = "1" ] && [ -d "$USER_DATA_DIR/questions" ]; then
		installer_do_section installer_as_root rm -rf "$USER_DATA_DIR/questions"
	fi

	# Copy questions from data/ starter kit if available, otherwise create defaults.
	if [ ! -d "$USER_DATA_DIR/questions" ]; then
		installer_do_section installer_as_root mkdir -p "$USER_DATA_DIR"
		installer_do_section installer_as_root cp -r "$SCRIPT_DIR/data/questions" "$USER_DATA_DIR/questions"
	fi

	installer_do_section installer_as_root mkdir -p "$(dirname "$ZSH_ALIASES")"
	# Mark only the alias block created by this installer. Never claim an
	# existing user alias, because uninstall must leave it untouched.
	if [ ! -f "$ZSH_ALIASES" ] || ! grep -qF "alias memoloop=" "$ZSH_ALIASES"; then
		alias_tmp=$(mktemp "${TMPDIR:-/tmp}/memoloop-alias.XXXXXX")
		cat >"$alias_tmp" <<ALIASEOF
# >>> memoloop managed alias >>>
alias memoloop='$INSTALLER_TARGET'
# <<< memoloop managed alias <<<
ALIASEOF
		installer_do_section sh -c "cat '$alias_tmp' >> '$ZSH_ALIASES'"
		rm -f "$alias_tmp"
	fi

	installer_do_section installer_as_root mkdir -p "$HOME/.config/niri"
	installer_do_section installer_as_root install -m 644 "$SCRIPT_DIR/niri/memoloop.kdl" "$HOME/.config/niri/memoloop.kdl"
	if [ -f "$HOME/.config/niri/config.kdl" ] && ! grep -qF 'include optional=true "memoloop.kdl"' "$HOME/.config/niri/config.kdl"; then
		niri_inc_tmp=$(mktemp "${TMPDIR:-/tmp}/memoloop-niri.XXXXXX")
		cat >"$niri_inc_tmp" <<'NIRIEOF'
// >>> memoloop managed include >>>
include optional=true "memoloop.kdl"
// <<< memoloop managed include <<<
NIRIEOF
		installer_do_section sh -c "cat '$niri_inc_tmp' >> '$HOME/.config/niri/config.kdl'"
		rm -f "$niri_inc_tmp"
	fi

	# Enable and start the systemd user service
	installer_do_section installer_as_root systemctl --user daemon-reload
	installer_do_section installer_as_root systemctl --user enable "$SERVICE_UNIT"
	installer_do_section installer_as_root systemctl --user start "$SERVICE_UNIT"

	# Reload niri config if running
	if command -v niri >/dev/null 2>&1 && pgrep -x niri >/dev/null 2>&1; then
		installer_do_section sh -c "niri msg action load-config-file --path '$HOME/.config/niri/config.kdl'"
	fi

	# Next steps shown after installation completes
	_INSTALLER_NEXT_STEPS="Config:   $CONFIG_DIR
Cache:    $CACHE_DIR
Alias:    memoloop  →  $INSTALLER_TARGET
Run:      memoloop --help
Popup:    MOD+N (niri) or memoloop ask
Service:  systemctl --user status $SERVICE_UNIT"
}

uninstall_integration() {
	installer_remove rm -f "$SYSTEMD_DIR/$SERVICE_UNIT"

	# Remove config and cache only if --purge-data is explicitly given.
	# By default, all user data is preserved.
	if [ "${MEMOLOOP_PURGE_DATA:-}" = "1" ]; then
		installer_remove rm -rf "$CONFIG_DIR"
		installer_remove rm -rf "$CACHE_DIR"
	fi

	# Remove only the exact block created by this installer. Unmarked/pre-existing
	# aliases are user-owned and must survive uninstall.
	if [ -f "$ZSH_ALIASES" ] && grep -qF '# >>> memoloop managed alias >>>' "$ZSH_ALIASES"; then
		installer_remove sed -i '/^# >>> memoloop managed alias >>>$/,/^# <<< memoloop managed alias <<<$/{d;}' "$ZSH_ALIASES"
	fi

	installer_remove rm -f "$HOME/.config/niri/memoloop.kdl"
	# Same ownership rule for Niri: remove only our marked include block.
	if [ -f "$HOME/.config/niri/config.kdl" ] && grep -qF '// >>> memoloop managed include >>>' "$HOME/.config/niri/config.kdl"; then
		installer_remove sed -i '\|^// >>> memoloop managed include >>>$|,\|^// <<< memoloop managed include <<<$|{d;}' "$HOME/.config/niri/config.kdl"
	fi
}

installer_run "$@"
