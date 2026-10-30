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
	--uninstall) mode="--uninstall" ;;
	--reinstall) mode="--reinstall" ;;
	--dry-run | -n) MEMOLOOP_DRY=1 ;;
	--no-integration) MEMOLOOP_NO_INTEGRATE=1 ;;
	--install-path)
		shift
		INSTALLER_BIN_DIR="$1"
		;;
	--purge-data) MEMOLOOP_PURGE_DATA=1 ;;
	--clean | --cleanup | --clean-install) MEMOLOOP_CLEAN=1 ;;
	--help | -h) MEMOLOOP_HELP=1 ;;
	*) rest+=("$1") ;;
	esac
	shift
done
set -- "${rest[@]+"${rest[@]}"}"

if [ "${MEMOLOOP_HELP:-}" = "1" ]; then
	cat <<'EOF'
Usage: ./install.sh [options]

MODES
  --user            install under your own home (default)
  --system          install system-wide, with sudo
  --uninstall       remove memoloop (keeps user data in ~/.config/memoloop/)
  --reinstall       uninstall then install
  --dry-run         show what would be done, touch nothing
  --no-integration  install the script only; no unit, config, alias or niri
  --install-path DIR  where the script goes
  --purge-data      also remove user data (~/.config/memoloop/, ~/.local/share/memoloop/) on uninstall
  --clean           remove config/cache before install (cleanup-before-install)

The zsh alias is appended to ~/.config/zsh/my_zsh_aliases (--user) or
/etc/zsh/zshrc (--system) only if it is not already there.
User data in ~/.config/memoloop/ and ~/.local/share/memoloop/ is preserved
on uninstall unless --purge-data is also given.
EOF
	exit 0
fi

case "$mode" in
--user | --uninstall | --reinstall)
	INSTALLER_BIN_DIR="$HOME/.local/bin"
	INSTALLER_LIB_DIR="$INSTALLER_BIN_DIR/../lib"
	SYSTEMD_DIR="$HOME/.config/systemd/user"
	CONFIG_DIR="$HOME/.config/memoloop"
	CACHE_DIR="$HOME/.local/share/memoloop"
	ZSH_ALIASES="$HOME/.config/zsh/my_zsh_aliases"
	SUDO=""
	;;
--system)
	INSTALLER_BIN_DIR="/usr/local/bin"
	INSTALLER_LIB_DIR="$INSTALLER_BIN_DIR/../lib"
	SYSTEMD_DIR="/etc/systemd/system"
	CONFIG_DIR="/etc/memoloop"
	CACHE_DIR="/var/lib/memoloop"
	ZSH_ALIASES="/etc/zsh/zshrc"
	SUDO="sudo"
	;;
esac

INSTALLER_TARGET="$INSTALLER_BIN_DIR/memoloop"
SERVICE_UNIT="memoloop.service"
ALIAS_LINE="alias memoloop='$INSTALLER_TARGET'"

. "$SCRIPT_DIR/lib/term.sh"
. "$SCRIPT_DIR/lib/installer.sh"

term_init

install_tool() {
	installer_do_section installer_as_root mkdir -p "$INSTALLER_LIB_DIR" || installer_die_unwritable
	installer_do_section installer_as_root install -m 755 "$SCRIPT_DIR/src/memoloop" "$INSTALLER_TARGET"
	installer_do_section installer_as_root install -m 644 "$SCRIPT_DIR/lib/term.sh" "$INSTALLER_LIB_DIR/term.sh"
}

uninstall_tool() {
	installer_remove rm -f "$INSTALLER_TARGET"
	installer_remove rm -f "$INSTALLER_LIB_DIR/term.sh"
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

	installer_do_section installer_as_root mkdir -p "$SYSTEMD_DIR"
	installer_do_section installer_as_root install -m 644 "$svc_tmp" "$SYSTEMD_DIR/$SERVICE_UNIT"
	rm -f "$svc_tmp"

	installer_do_section installer_as_root mkdir -p "$CONFIG_DIR"
	if [ "${MEMOLOOP_CLEAN:-}" = "1" ]; then
		installer_do_section installer_as_root rm -rf "$CONFIG_DIR" "$CACHE_DIR"
	fi
	installer_do_section installer_as_root mkdir -p "$CONFIG_DIR"
	if [ ! -f "$CONFIG_DIR/config.conf" ]; then
		local conf_tmp
		conf_tmp=$(mktemp "${TMPDIR:-/tmp}/memoloop-config.XXXXXX")
		cat >"$conf_tmp" <<'CONFEOF'
fixed_seconds=2700
random_min=15
random_max=30
decay_hours=24
min_per_day=10
nohelp=true
CONFEOF
		installer_do_section installer_as_root install -m 644 "$conf_tmp" "$CONFIG_DIR/config.conf"
		rm -f "$conf_tmp"
	fi

	if [ ! -f "$CACHE_DIR/pickup.set" ]; then
		installer_do_section installer_as_root mkdir -p "$CACHE_DIR"
		local pickup_tmp
		pickup_tmp=$(mktemp "${TMPDIR:-/tmp}/memoloop-pickup.XXXXXX")
		cat >"$pickup_tmp" <<'PICKUPEOF'
kanji
vocabulary
grammar
kana
PICKUPEOF
		installer_do_section installer_as_root install -m 644 "$pickup_tmp" "$CACHE_DIR/pickup.set"
		rm -f "$pickup_tmp"
	fi

	# Install missing/basic question sets without overwriting edited user data
	if [ -d "$SCRIPT_DIR/data/questions" ]; then
		src_questions="$SCRIPT_DIR/data/questions"
	else
		src_questions=""
	fi

	if [ -n "$src_questions" ]; then
		installer_do_section installer_as_root mkdir -p "$CACHE_DIR/questions"
		for group_dir in "$src_questions"/*/; do
			[ -d "$group_dir" ] || continue
			group_name=$(basename "$group_dir")
			installer_do_section installer_as_root mkdir -p "$CACHE_DIR/questions/$group_name"
			for qfile in "$group_dir"*.json; do
				[ -f "$qfile" ] || continue
				qbase=$(basename "$qfile")
				if [ ! -f "$CACHE_DIR/questions/$group_name/$qbase" ]; then
					installer_do_section installer_as_root install -m 644 "$qfile" "$CACHE_DIR/questions/$group_name/$qbase"
				fi
			done
		done
	elif [ ! -d "$CONFIG_DIR/questions" ]; then
		installer_do_section installer_as_root mkdir -p "$CACHE_DIR/questions/greetings"
		local q_tmp
		q_tmp=$(mktemp "${TMPDIR:-/tmp}/memoloop-questions.XXXXXX")
		cat >"$q_tmp" <<'QEOF'
[
  {"id": "greet-001", "type": "translation", "japanese": "こんにちは", "english": "Hello / Good afternoon", "accepted": ["こんにちは", "konnichiwa"], "note": "Standard daytime greeting."},
  {"id": "greet-002", "type": "translation", "japanese": "ありがとうございます", "english": "Thank you", "accepted": ["ありがとうございます", "arigatou gozaimasu", "arigatou", "ありがとう"], "note": "Thank you (polite)."},
  {"id": "greet-003", "type": "reverse", "japanese": "こんにちは", "english": "Hello / Good afternoon", "accepted": ["こんにちは", "konnichiwa"], "note": "Translate this English to Japanese: Hello / Good afternoon"},
  {"id": "greet-004", "type": "choice", "japanese": "小さい means?", "english": "small", "choices": ["A. big", "B. small", "C. new"], "answer": "B", "accepted": ["B", "b"], "note": "小さい (chiisai) = small."}
]
QEOF
		installer_do_section installer_as_root install -m 644 "$q_tmp" "$CONFIG_DIR/questions/greetings/basics.json"
		rm -f "$q_tmp"
	fi

	installer_do_section installer_as_root mkdir -p "$(dirname "$ZSH_ALIASES")"
	if [ ! -f "$ZSH_ALIASES" ] || ! grep -qF "alias memoloop=" "$ZSH_ALIASES"; then
		installer_do_section sh -c "cat >> '$ZSH_ALIASES' <<'EOF'

# memoloop
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

	installer_do_section installer_as_root systemctl --user daemon-reload
	installer_do_section installer_as_root systemctl --user enable "$SERVICE_UNIT"
	installer_do_section installer_as_root systemctl --user start "$SERVICE_UNIT"

	if command -v niri >/dev/null 2>&1 && pgrep -x niri >/dev/null 2>&1; then
		installer_do_section sh -c "niri msg action load-config-file --path '$HOME/.config/niri/config.kdl'"
	fi

	_INSTALLER_NEXT_STEPS="Config:   $CONFIG_DIR
Cache:    $CACHE_DIR
Alias:    memoloop  →  $INSTALLER_TARGET
Run:      memoloop --help
Popup:    MOD+N (niri) or memoloop ask
Service:  systemctl --user status $SERVICE_UNIT"
}

uninstall_integration() {
	installer_remove rm -f "$SYSTEMD_DIR/$SERVICE_UNIT"
	if [ -f "$ZSH_ALIASES" ] && grep -qF "alias memoloop=" "$ZSH_ALIASES"; then
		installer_remove sed -i '/^alias memoloop=/d' "$ZSH_ALIASES"
		installer_remove sed -i '/^# memoloop$/d' "$ZSH_ALIASES"
	fi
	installer_remove rm -f "$HOME/.config/niri/memoloop.kdl"
	if [ -f "$HOME/.config/niri/config.kdl" ]; then
		installer_remove sed -i '/^include optional=true "memoloop.kdl"$/d' "$HOME/.config/niri/config.kdl"
	fi
	if [ "${MEMOLOOP_PURGE_DATA:-}" = "1" ]; then
		installer_remove rm -rf "$CONFIG_DIR"
		installer_remove rm -rf "$CACHE_DIR"
	fi
}

case "$mode" in
--uninstall | --reinstall) installer_run "$mode" "$@" ;;
*) installer_run "$@" ;;
esac
