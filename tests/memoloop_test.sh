#!/usr/bin/env bash
# Tests for the memoloop prototype scheduling and answer-matching logic.
#
# Sources src/memoloop (command dispatcher is guarded so nothing runs on
# source) with MEMOLOOP_STATE redirected to a temporary directory, then
# exercises the pure functions directly.
#
# Run: ./tests/memoloop_test.sh

set -u

SELF_DIR() {
	_sd=${BASH_SOURCE[0]}
	while [ -L "$_sd" ]; do
		_sd_l=$(readlink "$_sd")
		case "$_sd_l" in
		/*) _sd=$_sd_l ;;
		*) _sd=$(dirname -- "$_sd")/$_sd_l ;;
		esac
	done
	(CDPATH='' cd -- "$(dirname -- "$_sd")" && pwd -P)
}
REPO=$(SELF_DIR)
unset -f SELF_DIR

export MEMOLOOP_STATE="$(mktemp -d)"
export MEMOLOOP_LOG="$(mktemp -d)"
trap 'rm -rf "$MEMOLOOP_STATE" "$MEMOLOOP_LOG"' EXIT

# shellcheck source=../src/memoloop
. "$REPO/../src/memoloop"

# Create the state files the functions read/write.
state_init >/dev/null 2>&1

pass=0
fail=0

assert_eq() { # $1 desc $2 expected $3 actual
	if [ "$2" = "$3" ]; then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
		printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
	fi
}

rc() { # run $1.., print exit code
	"$@"
	printf '%s' "$?"
}

# ---------------------------------------------------------------- intervals

fixed_sec=$(rule_interval_seconds fixed)
assert_eq "fixed interval seconds" "2700" "$fixed_sec"

random_ok=1
for _ in $(seq 1 200); do
	sec=$(rule_interval_seconds random)
	if [ "$sec" -lt 900 ] || [ "$sec" -gt 1800 ]; then
		random_ok=0
		break
	fi
done
assert_eq "random interval always in 1800-2400s" "1" "$random_ok"

# ---------------------------------------------------------------- schedule_recalc / due_rules

now=$(epoch)
schedule_recalc fixed
schedule_recalc random
for id in fixed random; do
	nd=$(rule_next_due "$id")
	assert_eq "$id next_due in future" "0" $([ "$nd" -gt "$now" ] && echo 0 || echo 1)
done

rules_set_next_due fixed $((now - 100))
rules_set_next_due random $((now + 100000))
due=$(due_rules)
assert_eq "due_rules returns fixed only" "fixed" "$due"

schedule_recalc fixed
schedule_recalc random

# ---------------------------------------------------------------- pause / resume / dnd

cmd_pause
assert_eq "pause sets paused=true" "true" "$(session_get paused)"
cmd_resume
assert_eq "resume sets paused=false" "false" "$(session_get paused)"

cmd_dnd 09:00 17:00
assert_eq "dnd start stored" "09:00" "$(session_get dnd_start)"
assert_eq "dnd end stored" "17:00" "$(session_get dnd_end)"

session_set dnd_start "null"
session_set dnd_end "null"
assert_eq "no DND → in_dnd returns 1" "1" "$(rc in_dnd)"

start_hm=$(date +%H:%M)
end_hm=$(date -d '+1 minute' +%H:%M)
session_set dnd_start "\"$start_hm\""
session_set dnd_end "\"$end_hm\""
assert_eq "current minute inside DND → in_dnd returns 0" "0" "$(rc in_dnd)"

session_set dnd_start "null"
session_set dnd_end "null"

# ---------------------------------------------------------------- answer matching

assert_eq "normalize lowercase" "hai" "$(normalize "HAI")"
assert_eq "normalize trim" "hai" "$(normalize "  hai  ")"

accepted='はい
hai
konnichiwa'
match() { # $1 candidate → 0 if matches any accepted line
	local cand="$1" a
	cand=$(normalize "$cand")
	while IFS= read -r a; do
		[ -z "$a" ] && continue
		if [ "$cand" = "$(normalize "$a")" ]; then return 0; fi
	done <<<"$accepted"
	return 1
}

assert_eq "hai matches accepted" "0" "$(rc match hai)"
assert_eq "HAI matches accepted (case)" "0" "$(rc match HAI)"
assert_eq " trimmed hai matches accepted" "0" "$(rc match " hai ")"
assert_eq "nope does not match" "1" "$(rc match nope)"

# ---------------------------------------------------------------- question file loads

qcount=$(jq 'length' "$QUESTIONS")
assert_eq "question set is non-empty" "0" $([ "$qcount" -gt 0 ] && echo 0 || echo 1)
all_have_jp=1
while IFS= read -r line; do
	[ -n "$line" ] || continue
	jp=$(printf '%s' "$line" | jq -r '.japanese')
	[ -n "$jp" ] || all_have_jp=0
done < <(jq -c '.[]' "$QUESTIONS")
assert_eq "every question has japanese text" "1" "$all_have_jp"

# ---------------------------------------------------------------- summary

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
	exit 1
fi
exit 0
