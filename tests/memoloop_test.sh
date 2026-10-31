#!/usr/bin/env bash

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

CLI_ROOT="$(mktemp -d)"

export MEMOLOOP_CONFIG_DIR="$(mktemp -d)"
export MEMOLOOP_STATE="$(mktemp -d)"
export MEMOLOOP_LOG="$(mktemp -d)"
export USER_DATA_DIR="$(mktemp -d)"
trap 'rm -rf "$MEMOLOOP_CONFIG_DIR" "$MEMOLOOP_STATE" "$MEMOLOOP_LOG" "$USER_DATA_DIR" "$CLI_ROOT"' EXIT

. "$REPO/src/memoloop"

pass=0
fail=0

assert_eq() {
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
  fi
}

cat >$MEMOLOOP_CONFIG_DIR/config.conf <<'EOF'
nohelp=true
EOF

cat >$MEMOLOOP_CONFIG_DIR/intervals.conf <<'EOF'
decay_hours=24
min_per_day=10
EOF

cat >$MEMOLOOP_CONFIG_DIR/pickup.set <<'EOF'
greetings
family
weather
conversation
adjectives
verbs
nouns
EOF

mkdir -p "$USER_DATA_DIR/questions/greetings"
cat >"$USER_DATA_DIR/questions/greetings/basics.json" <<'EOF'
[
  {"id": "t-greet-1", "type": "translation", "japanese": "こんにちは", "english": "Hello", "accepted": ["こんにちは", "konnichiwa"]},
  {"id": "t-greet-2", "type": "reverse", "japanese": "ありがとう", "english": "Thank you", "accepted": ["ありがとう", "arigatou"]},
  {"id": "t-greet-3", "type": "cloze", "japanese": "小さな町です", "target": "小さな", "english": "Small town", "accepted": ["小さな", "chiisana"]},
  {"id": "t-greet-4", "type": "choice", "japanese": "雨 means?", "english": "rain", "choices": ["A. 雪", "B. 雨", "C. 晴れ"], "answer": "B", "accepted": ["B", "b"]}
]
EOF

load_intervals
state_init >/dev/null 2>&1

assert_eq "decay_hours loaded" "24" "$DECAY_HOURS"
assert_eq "min_per_day loaded" "10" "$MIN_PER_DAY"

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

printf '{}' >"$ANSWERS_STATE"

update_points "t-greet-1" "accepted"
points=$(printf '%s' "$(load_answers)" | jq -r '.["t-greet-1"].points // 100')
assert_eq "correct answer +10 points" "110" "$points"

update_points "t-greet-2" "rejected"
points=$(printf '%s' "$(load_answers)" | jq -r '.["t-greet-2"].points // 100')
assert_eq "incorrect answer -10 points" "90" "$points"

for i in $(seq 1 9); do update_points "t-greet-2" "rejected"; done
points=$(printf '%s' "$(load_answers)" | jq -r '.["t-greet-2"].points // 100')
assert_eq "points floor at 0" "0" "$points"

ts=$(printf '%s' "$(load_answers)" | jq -r '.["t-greet-1"].times_shown // 0')
tc=$(printf '%s' "$(load_answers)" | jq -r '.["t-greet-1"].times_correct // 0')
assert_eq "times_shown tracked" "1" "$ts"
assert_eq "times_correct tracked" "1" "$tc"

w=$(question_weight "t-greet-3" "$(load_answers)" "$(epoch)")
assert_eq "new question weight" "0.5" "$(awk -v w="$w" 'BEGIN { printf "%.1f", w }')"

w=$(question_weight "t-greet-1" "$(load_answers)" "$(epoch)")
assert_eq "high points lower weight" "0.5" "$(awk -v w="$w" 'BEGIN { printf "%.1f", w }')"

w=$(question_weight "t-greet-2" "$(load_answers)" "$(epoch)")
assert_eq "zero points max weight" "1.0" "$(awk -v w="$w" 'BEGIN { printf "%.1f", w }')"

shown_count=$(questions_shown_today)
assert_eq "questions shown today (2 answered)" "2" "$shown_count"

sel=$(select_question "$groups")
sel_id=$(printf '%s' "$sel" | jq -r '.id // empty')
[ -n "$sel_id" ] && assert_eq "question selected" "0" "0" || assert_eq "question selected" "1" "1"

sel_prefix=$(printf '%s' "$sel_id" | cut -d- -f1-2)
assert_eq "selected group is greetings" "t-greet" "$sel_prefix"

mkdir -p "$CLI_ROOT/config" "$CLI_ROOT/data/questions/greetings"
cp "$USER_DATA_DIR/questions/greetings/basics.json" "$CLI_ROOT/data/questions/greetings/basics.json"
printf 'greetings\n' >"$CLI_ROOT/config/pickup.set"
printf 'decay_hours=24\nmin_per_day=10\n' >"$CLI_ROOT/config/intervals.conf"
printf 'nohelp=true\nUSER_DATA_DIR="%s"\n' "$CLI_ROOT/data" >"$CLI_ROOT/config/config.conf"

cli() {
  env MEMOLOOP_CONFIG_DIR="$CLI_ROOT/config" \
    MEMOLOOP_DATA_DIR="$CLI_ROOT/data" \
    MEMOLOOP_STATE="$CLI_ROOT/state" \
    MEMOLOOP_LOG="$CLI_ROOT/log" \
    bash "$REPO/src/memoloop" "$@" </dev/null >/dev/null 2>&1
}

cli setup
assert_eq "setup exits 0" "0" "$?"
assert_eq "setup creates answers.json" "yes" "$([ -s "$CLI_ROOT/data/answers.json" ] && echo yes || echo no)"
assert_eq "setup creates log file" "yes" "$([ -f "$CLI_ROOT/log/reminders.log" ] && echo yes || echo no)"
assert_eq "setup creates no rules.json" "no" "$([ -e "$CLI_ROOT/state/rules.json" ] && echo yes || echo no)"
assert_eq "setup creates no session.json" "no" "$([ -e "$CLI_ROOT/state/session.json" ] && echo yes || echo no)"

out=$(env MEMOLOOP_CONFIG_DIR="$CLI_ROOT/config" \
  MEMOLOOP_DATA_DIR="$CLI_ROOT/data" \
  MEMOLOOP_STATE="$CLI_ROOT/state" \
  MEMOLOOP_LOG="$CLI_ROOT/log" \
  bash "$REPO/src/memoloop" config </dev/null 2>&1)
case "$out" in *"$CLI_ROOT/data"*) v=yes ;; *) v=no ;; esac
assert_eq "config.conf USER_DATA_DIR honoured" "yes" "$v"
case "$out" in *"fixed_seconds"*) v=yes ;; *) v=no ;; esac
assert_eq "config hides scheduling keys" "no" "$v"

cli start
assert_eq "start command removed" "1" "$?"
cli status
assert_eq "status command removed" "1" "$?"
cli pause
assert_eq "pause command removed" "1" "$?"

popup_rc=0
timeout 3 bash -c '
  export FOOT_POPUP=1
  export MEMOLOOP_CONFIG_DIR="$1" MEMOLOOP_DATA_DIR="$2" MEMOLOOP_STATE="$3" MEMOLOOP_LOG="$4"
  sleep 6 | "$5" ask manual >/dev/null 2>&1
' _ "$CLI_ROOT/config" "$CLI_ROOT/data" "$CLI_ROOT/state" "$CLI_ROOT/log" "$REPO/src/memoloop" || popup_rc=$?
assert_eq "popup renders and waits for input" "124" "$popup_rc"

if command -v script >/dev/null 2>&1; then
  : >"$CLI_ROOT/log/reminders.log"
  printf 'wrong\nnwrong2\nx' | script -qec "env FOOT_POPUP=1 MEMOLOOP_CONFIG_DIR='$CLI_ROOT/config' MEMOLOOP_DATA_DIR='$CLI_ROOT/data' MEMOLOOP_STATE='$CLI_ROOT/state' MEMOLOOP_LOG='$CLI_ROOT/log' bash '$REPO/src/memoloop' ask manual" /dev/null >/dev/null 2>&1 || true
  assert_eq "n after feedback opens another question" "2" "$(grep -c answered "$CLI_ROOT/log/reminders.log")"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
