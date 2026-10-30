# --- vendored from cli-utilities/installer.sh, cksum 4257143474 12052; do not edit ---
#!/bin/sh
#
# installer.sh -- the shared installer.  Sourced, never executed.
#
# Every tool in this repository has the same installer interface, and an
# interface that six programs each implement separately is six implementations
# that will drift.  This is the one implementation, vendored into each tool the
# way term.sh is, and check.sh holds it to being current.
#
# The division is deliberate and narrow.  This file owns everything that is the
# same for every tool: the flags, the escalation to sudo, the refusal when that
# fails, --dry-run, and the wording of a failure.  A tool owns everything that
# is different for it: what to install, and what to change outside itself.  It
# says the second part by defining the hooks below and nothing else.
#
# The reason for the split is that these two halves fail differently.  The
# first half failing is a flag that does not exist, and it is found the first
# time anybody runs it.  The second half failing is a config file edited
# wrongly on a machine nobody is sitting at, so the parts that touch a file
# say what they are about to do before they do it.
#
# POSIX sh, for the reason term.sh is: the consumers are shell scripts and the
# repository keeps no toolchain to speak of.  Every name is prefixed, because
# an installer runs in the same shell as a tool's own variables and a library
# that defined `action` or `target` would break them.

set -u

# The interface, as a list, so that the parser, the usage text and the check in
# conventions/check.sh all read one thing.  A flag written into the help but not
# here is a flag no check ever asks for; a flag here but not in the help is a
# flag nobody finds.  Both are the same mistake -- the interface written down
# twice, and the two copies disagreeing quietly.
#
# Long flags, and the aliases each one answers to.  A tool is free to add flags
# of its own on top: desk-reminder has --user and --system, which are not in
# here because they are not everybody's.
INSTALLER_FLAGS="--uninstall --reinstall --dry-run,-n --no-integration --install-path,-h,--help"

# A tool says what is different about it through these, before it calls
# installer_run.  All are overridable because the common case is the plain one
# and a tool should not have to restate the default to get it.
: "${INSTALLER_INTEGRATION_DESC:=}"
: "${INSTALLER_NO_INTEGRATION_DESC:= install the tool only, touch no config}"
: "${INSTALLER_EXTRA_HELP:=}"

# Load term.sh from the lib directory.  install.sh sets SCRIPT_DIR before
# sourcing installer.sh, so term.sh is at $SCRIPT_DIR/lib/term.sh.
. "$SCRIPT_DIR/lib/term.sh"

# Initialize the terminal renderer.  This must happen before any output.
term_init

# --- basic output helpers ---

# Say what is about to happen to a file a tool edits rather than creates.
installer_plan() { # $1 message
	term_notice "$1"
}

# Print a command and, unless --dry-run, run it.  Uses "added" marker.
# If called within a section (via installer_do_section), does not print immediately.
installer_do() { # $@ command
	[ -n "${_install_rows:-}" ] && {
		installer_section_add "$*"
		[ "${INSTALLER_DRY:-0}" -eq 0 ] || return 0
		"$@"
		return 0
	}
	term_added "$*"
	[ "${INSTALLER_DRY:-0}" -eq 0 ] || return 0
	"$@"
}

# Print a removal command and, unless --dry-run, run it.  Uses "removed" marker.
installer_remove() { # $@ command
	installer_section_add "$*"
	[ "${INSTALLER_DRY:-0}" -eq 0 ] || return 0
	"$@"
}

# Report an outcome; in --dry-run say what would have happened.
# Two-line summary: status line + path line
installer_result() { # $1 real message, $2 dry-run message
	if [ "${INSTALLER_DRY:-0}" -eq 0 ]; then
		term_ok "$INSTALLER_NAME" "$1
path: $INSTALLER_TARGET"
	else
		term_notice "(dry-run) would $2"
	fi
}

# Run a command that writes into the binary directory, escalating to sudo only
# when the directory is one this user cannot write to.
installer_as_root() { # $@ command
	[ "${INSTALLER_DRY:-0}" -eq 0 ] || {
		term_added "$*"
		return 0
	}
	if mkdir -p "$INSTALLER_BIN_DIR" 2>/dev/null && [ -w "$INSTALLER_BIN_DIR" ]; then
		"$@"
		return $?
	fi
	command -v sudo >/dev/null 2>&1 || return 1
	sudo "$@"
}

# Refuse, loudly, having installed nothing.
installer_die_unwritable() {
	term_rows_box "$TERM_ERROR" "$TERM_ERROR" \
		"install.sh: cannot write to $INSTALLER_BIN_DIR" "$TERM_MARK_ERROR" \
		"sudo was tried and did not work, or is not installed." \
		"install somewhere you can write:" \
		"    ./install.sh --install-path ~/.local/bin"
	exit 1
}

# --- grouped output for install/uninstall phases ---

# Collect install rows into a temp file, then render as one box
_install_rows=""

installer_section_begin() { # $1 title, $2 frame colour, $3 marker
	_install_title="$1"
	_install_frame="$2"
	_install_marker="$3"
	_install_rows=$(mktemp "${TMPDIR:-/tmp}/installer_rows.XXXXXX")
	: >"$_install_rows"
}

installer_section_add() { # $1 text
	[ -n "$_install_rows" ] && printf '%s\n' "$1" >>"$_install_rows"
}

installer_section_end() { # $1 final message
	[ -s "$_install_rows" ] || {
		rm -f "$_install_rows"
		_install_rows=""
		return 0
	}
	term_rows_box_file "$_install_frame" "$_install_frame" "$_install_title" "$_install_marker" "$_install_rows"
	rm -f "$_install_rows"
	_install_rows=""
}

# --- install phase ---

installer_do_install() {
	installer_section_begin "installing $INSTALLER_NAME" "$TERM_ADD" "$TERM_MARK_ADD"

	# bin dir creation (use section API so it's grouped)
	installer_do_section installer_as_root mkdir -p "$INSTALLER_BIN_DIR" || installer_die_unwritable

	# tool-specific install
	if command -v install_tool >/dev/null 2>&1; then
		install_tool_section
	fi

	# integration
	if [ "$INSTALLER_INTEGRATE" -eq 1 ] && command -v install_integration >/dev/null 2>&1; then
		install_integration_section
	fi

	installer_section_end "$INSTALLER_NAME"

	# Success + next steps in one box
	if [ -n "$_INSTALLER_NEXT_STEPS" ]; then
		old_ifs="$IFS"
		IFS=$'\n'
		# shellcheck disable=SC2086
		term_rows_box "$TERM_OK" "$TERM_OK" "$INSTALLER_NAME" "$TERM_MARK_OK" "installed" $_INSTALLER_NEXT_STEPS
		IFS="$old_ifs"
	else
		term_ok "$INSTALLER_NAME" "installed"
	fi
}

# Helper for tools that want to add to the install section
install_tool_section() { # $1 section file
	install_tool "$_install_rows"
}

# Default install_tool (backward compat)
install_tool() { # [$1 section file (rows temp file)]
	# If called with section file, use it; otherwise direct call
	if [ $# -eq 1 ]; then
		_install_rows="$1"
		installer_do_section installer_as_root install -m 755 "$SCRIPT_DIR/$INSTALLER_NAME" "$INSTALLER_TARGET"
	else
		[ "${INSTALLER_DRY:-0}" -eq 0 ] && installer_as_root install -m 755 "$SCRIPT_DIR/$INSTALLER_NAME" "$INSTALLER_TARGET"
		installer_section_add "install -m 755 $SCRIPT_DIR/$INSTALLER_NAME $INSTALLER_TARGET"
	fi
}

# --- uninstall phase ---

installer_do_uninstall() {
	installer_section_begin "uninstalling $INSTALLER_NAME" "$TERM_DEL" "$TERM_MARK_DEL"

	# integration first
	if [ "$INSTALLER_INTEGRATE" -eq 1 ] && command -v uninstall_integration >/dev/null 2>&1; then
		uninstall_integration_section
	fi

	# tool-specific uninstall
	if command -v uninstall_tool >/dev/null 2>&1; then
		uninstall_tool_section
	fi

	installer_section_end "$INSTALLER_NAME"
	term_ok "$INSTALLER_NAME" "uninstalled"
}

# Helper for tools that want to add to the uninstall section
uninstall_tool_section() {
	uninstall_tool "$_install_rows"
}

# Default uninstall_tool (backward compat)
uninstall_tool() { # [$1 section file (rows temp file)]
	# If called with section file, use it; otherwise direct call
	if [ $# -eq 1 ]; then
		_install_rows="$1"
		installer_do_section_remove rm -f "$INSTALLER_TARGET"
	else
		[ "${INSTALLER_DRY:-0}" -eq 0 ] && installer_remove rm -f "$INSTALLER_TARGET"
		installer_section_add "rm -f $INSTALLER_TARGET"
	fi
}

# Integration section helpers (tools can override)
install_integration_section() {
	install_integration "$_install_rows"
}

uninstall_integration_section() {
	uninstall_integration "$_install_rows"
}

# Default no-op for backward compat
install_integration() { :; }
uninstall_integration() { :; }

# --- section API for tools ---
#
# Backward-compatible API:
#   installer_do_section "message"              - prints message only
#   installer_do_section "message" cmd args...  - prints message, runs cmd
#   installer_do_section cmd args...            - runs cmd, prints cmd as msg
#
# Heuristic: if $1 is a known command verb, treat all args as command.
# Otherwise $1 is message, ${@:2} is optional command.

installer_do_section() { # [$1 message] [cmd args...]
	# Known command verbs that indicate "this is a command, not a message"
	case "$1" in
	installer_as_root | install | rm | mkdir | sed | awk | grep | systemctl | systemctl_run | mv | cp | ln | chmod | chown | tee | cat | echo | printf | awk | bash | sh)
		# It's a command: print it as message, then run it
		installer_section_add "$*"
		[ "${INSTALLER_DRY:-0}" -eq 0 ] || return 0
		"$@"
		;;
	*)
		# First arg is a message
		installer_section_add "$1"
		shift
		[ $# -eq 0 ] && return 0
		[ "${INSTALLER_DRY:-0}" -eq 0 ] || return 0
		"$@"
		;;
	esac
}

# Add a removal command to current section (no immediate output).  Uses "removed" marker.
installer_do_section_remove() { # $@ command
	# Same heuristic for removal commands
	case "$1" in
	installer_as_root | rm | rmdir | sed | awk | grep | systemctl | systemctl_run | mv | cp | ln | chmod | chown | tee | cat | echo | printf | awk | bash | sh)
		installer_section_add "$*"
		[ "${INSTALLER_DRY:-0}" -eq 0 ] || return 0
		"$@"
		;;
	*)
		installer_section_add "$1"
		shift
		[ $# -eq 0 ] && return 0
		[ "${INSTALLER_DRY:-0}" -eq 0 ] || return 0
		"$@"
		;;
	esac
}

# The hook a tool provides when it has nothing to integrate.
installer_no_integration() { :; }

# Parse the flags, then dispatch.  This is the only entry point.
installer_run() {
	INSTALLER_ACTION=install
	INSTALLER_DRY=0
	INSTALLER_INTEGRATE=1

	# PREFIX is honoured rather than second-guessed.
	[ -n "${INSTALLER_BIN_DIR:-}" ] || INSTALLER_BIN_DIR="${PREFIX:-$HOME/.local}/bin"
	[ -n "${INSTALLER_TARGET:-}" ] || INSTALLER_TARGET="$INSTALLER_BIN_DIR/$INSTALLER_NAME"

	while [ $# -gt 0 ]; do
		case "$1" in
		--uninstall)
			INSTALLER_ACTION=uninstall
			shift
			;;
		--reinstall)
			INSTALLER_ACTION=reinstall
			shift
			;;
		--dry-run | -n)
			INSTALLER_DRY=1
			shift
			;;
		--no-integration)
			INSTALLER_INTEGRATE=0
			shift
			;;
		--install-path)
			[ $# -ge 2 ] || {
				term_bad "install.sh: --install-path needs a directory" ""
				exit 2
			}
			INSTALLER_BIN_DIR=$2
			INSTALLER_TARGET="$INSTALLER_BIN_DIR/$INSTALLER_NAME"
			shift 2
			;;
		--install-path=*)
			INSTALLER_BIN_DIR=${1#--install-path=}
			[ -n "$INSTALLER_BIN_DIR" ] || {
				term_bad "install.sh: --install-path needs a directory" ""
				exit 2
			}
			INSTALLER_TARGET="$INSTALLER_BIN_DIR/$INSTALLER_NAME"
			shift
			;;
		-h | --help)
			installer_usage
			exit 0
			;;
		*)
			term_bad "Unknown option: $1" "Use --help for the list."
			exit 2
			;;
		esac
	done

	case "$INSTALLER_ACTION" in
	install) installer_do_install ;;
	uninstall) installer_do_uninstall ;;
	reinstall) installer_do_reinstall ;;
	esac
}

installer_do_reinstall() {
	if [ "$INSTALLER_DRY" -eq 0 ]; then
		# Custom box with neutral frame, different markers per row
		term_header "$TERM_NEUTRAL" "Reinstall $INSTALLER_NAME?" ""
		echo ""
		printf '%s%s%s %s%s\n' "$TERM_INDENT" "$TERM_NEG" "$TERM_MARK_NEG" \
			"This removes $INSTALLER_TARGET first." "$TERM_RESET"
		printf '%s%s %s%s\n' "$TERM_INDENT" "$TERM_MARK_PLAIN" \
			"Press 'y' to confirm or 'n' to cancel." "$TERM_RESET"
		echo ""
		term_footer "$TERM_NEUTRAL"
		echo ""
		read -r installer_ans
		case "$installer_ans" in
		y | Y) ;;
		*)
			term_notice "aborted"
			exit 1
			;;
		esac
	fi
	installer_do_uninstall
	installer_do_install
}

installer_usage() {
	cat <<EOF
Usage: ./install.sh [OPTIONS]

  (no options)         install $INSTALLER_NAME
  --uninstall          remove it${INSTALLER_INTEGRATION_DESC}
  --reinstall          uninstall, then install
  --dry-run, -n        show what would have happened, touch nothing
  --no-integration     $INSTALLER_NO_INTEGRATION_DESC
  --install-path DIR   where the executable goes
                       (default: \${PREFIX:-\$HOME/.local}/bin)

A directory you cannot write to is installed through sudo.  If that fails the
installer says so and exits non-zero, having installed nothing.
$INSTALLER_EXTRA_HELP
EOF
}
