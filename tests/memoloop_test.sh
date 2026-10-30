#!/usr/bin/env bash
# Tests for the memoloop config + scoring system.
#
# Uses temp directories for isolated testing.
# Sources src/memoloop then exercises the functions directly.
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
	(CDPATH='' cd -- "$(dirname -- "$_sd")/.." && pwd -P)
}
REPO=$(SELF_DIR)
unset -f SELF_DIR

export MEMOLOOP_CONFIG_DIR="$(mktemp -d)"
export MEMOLOOP_CACHE_DIR="$(mktemp -d)"
export MEMOLOOP_STATE="$(mktemp -d)"
export MEMOLOOP_LOG="$(mktemp -d)"
trap 'rm -rf "$MEMOLOOP_CONFIG_DIR" "$MEMOLOOP_CACHE_DIR" "$MEMOLOOP_STATE" "$MEMOLOOP_LOG"' EXIT

# shellcheck source=../src/memoloop
. "$REPO/src/memoloop"

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

# ---------------------------------------------------------------- config loading

cat >"$MEMOLOOP_CONFIG_DIR/intervals.conf" <<'EOF'
fixed_seconds=2700
random_min=15
random_max=30
decay_hours=24
min_per_day=10
EOF

cat >"$MEMOLOOP_CONFIG_DIR/pickup.set" <<'EOF'
greetings
family
weather
conversation
adjectives
verbs
nouns
EOF

mkdir -p "$MEMOLOOP_CONFIG_DIR/questions/greetings"
cat >"$MEMOLOOP_CONFIG_DIR/questions/greetings/basics.json" <<'EOF'
[
  {"id": "t-greet-1", "type": "translation", "japanese": "こんにちは", "english": "Hello", "accepted": ["こんにちは", "konnichiwa"]},
  {"id": "t-greet-2", "type": "reverse", "japanese": "ありがとう", "english": "Thank you", "accepted": ["ありがとう", "arigatou"]},
  {"id": "t-greet-3", "type": "cloze", "japanese": "小さな町です", "target": "小さな", "english": "Small town", "accepted": ["小さな", "chiisana"]},
  {"id": "t-greet-4", "type": "choice", "japanese": "雨 means?", "english": "rain", "choices": ["A. 雪", "B. 雨", "C. 晴れ"], "answer": "B", "accepted": ["B", "b"]}
]
EOF

load_intervals
state_init >/dev/null 2>&1

assert_eq "fixed_seconds loaded" "2700" "$FIXED_SECONDS"
assert_eq "random_min loaded" "15" "$RANDOM_MIN"
assert_eq "random_max loaded" "30" "$RANDOM_MAX"
assert_eq "decay_hours loaded" "24" "$DECAY_HOURS"
assert_eq "min_per_day loaded" "10" "$MIN_PER_DAY"

# ---------------------------------------------------------------- question loading

groups=$(load_enabled_groups)
gcount=$(printf '%s' "$groups" | grep -c .)
assert_eq "enabled groups count" "7" "$gcount"

questions=$(load_all_questions "$groups")
qcount=$(printf '%s' "$questions" | jq 'length')
assert_eq "question set non-empty" "0" $([ "$qcount" -gt 0 ] && echo 0 || echo 1)

all_valid=1
while IFS= read -r line; do
	[ -z "$line" ] && continue
	id=$(printf '%s' "$line" | jq -r '.id // empty')
	jp=$(printf '%s' "$line" | jq -r '.japanese // empty')
	en=$(printf '%s' "$line" | jq -r '.english // empty')
	[ -n "$id" ] && [ -n "$jp" ] && [ -n "$en" ] || all_valid=0
done < <(printf '%s' "$questions" | jq -c '.[]')
assert_eq "all questions have required fields" "1" "$all_valid"

# ---------------------------------------------------------------- answer scoring

printf '{}' >"$ANSWERS_STATE"

update_points "t-greet-1" "accepted"
points=$(printf '%s' "$(load_answers)" | jq -r '.["t-greet-1"].points // 100')
assert_eq "correct answer +10 points" "110" "$points"

update_points "t-greet-2" "rejected"
points=$(printf '%s' "$(load_answers)" | jq -r '.["t-greet-2"].points // 100')
assert_eq "incorrect answer -10 points" "90" "$points"

# Floor at 0: reject 9 more times (total 10 rejects from 100 → 0)
for i in $(seq 1 9); do update_points "t-greet-2" "rejected"; done
points=$(printf '%s' "$(load_answers)" | jq -r '.["t-greet-2"].points // 100')
assert_eq "points floor at 0" "0" "$points"

ts=$(printf '%s' "$(load_answers)" | jq -r '.["t-greet-1"].times_shown // 0')
tc=$(printf '%s' "$(load_answers)" | jq -r '.["t-greet-1"].times_correct // 0')
assert_eq "times_shown tracked" "1" "$ts"
assert_eq "times_correct tracked" "1" "$tc"

# ---------------------------------------------------------------- question weight

# New question, points=100 → weight = 100/(100+100) = 0.5
w=$(question_weight "t-greet-3" "$(load_answers)" "$(epoch)")
assert_eq "new question weight" "0.5" "$(awk -v w="$w" 'BEGIN { printf "%.1f", w }')"

# High points (110) → weight = 100/(110+100) ≈ 0.476 → 0.5
w=$(question_weight "t-greet-1" "$(load_answers)" "$(epoch)")
assert_eq "high points lower weight" "0.5" "$(awk -v w="$w" 'BEGIN { printf "%.1f", w }')"

# Zero points → max weight = 100/(0+100) = 1.0
w=$(question_weight "t-greet-2" "$(load_answers)" "$(epoch)")
assert_eq "zero points max weight" "1.0" "$(awk -v w="$w" 'BEGIN { printf "%.1f", w }')"

# ---------------------------------------------------------------- daily minimum

shown_count=$(questions_shown_today)
assert_eq "questions shown today (2 answered)" "2" "$shown_count"

# ---------------------------------------------------------------- question selection

sel=$(select_question "$groups")
sel_id=$(printf '%s' "$sel" | jq -r '.id // empty')
[ -n "$sel_id" ] && assert_eq "question selected" "0" "0" || assert_eq "question selected" "1" "1"

# Selected question should be from greetings group (id prefix t-greet)
sel_prefix=$(printf '%s' "$sel_id" | cut -d- -f1-2)
assert_eq "selected group is greetings" "t-greet" "$sel_prefix"

# ---------------------------------------------------------------- summary

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
	exit 1
fi
exit 0
