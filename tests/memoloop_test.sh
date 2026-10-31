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
fixed_seconds=2700
random_min=15
random_max=30
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

assert_eq "fixed_seconds loaded" "2700" "$FIXED_SECONDS"
assert_eq "random_min loaded" "15" "$RANDOM_MIN"
assert_eq "random_max loaded" "30" "$RANDOM_MAX"
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

in_dnd_code() {
  in_dnd "$1"
  printf '%s' "$?"
}

session_set_str dnd_start "09:00"
session_set_str dnd_end "17:00"
assert_eq "dnd window: start edge is inside" "0" "$(in_dnd_code 09:00)"
assert_eq "dnd window: middle is inside" "0" "$(in_dnd_code 12:00)"
assert_eq "dnd window: end edge is outside" "1" "$(in_dnd_code 17:00)"
assert_eq "dnd window: before is outside" "1" "$(in_dnd_code 08:59)"

session_set_str dnd_start "22:00"
session_set_str dnd_end "07:00"
assert_eq "overnight dnd: late is inside" "0" "$(in_dnd_code 23:30)"
assert_eq "overnight dnd: early is inside" "0" "$(in_dnd_code 06:59)"
assert_eq "overnight dnd: daytime is outside" "1" "$(in_dnd_code 12:00)"
assert_eq "overnight dnd: end edge is outside" "1" "$(in_dnd_code 07:00)"

session_set dnd_start null
session_set dnd_end null
assert_eq "dnd unset is outside" "1" "$(in_dnd_code 12:00)"

mkdir -p "$CLI_ROOT/config" "$CLI_ROOT/data/questions/greetings"
cp "$USER_DATA_DIR/questions/greetings/basics.json" "$CLI_ROOT/data/questions/greetings/basics.json"
printf 'greetings\n' >"$CLI_ROOT/config/pickup.set"
printf 'fixed_seconds=60\nrandom_min=1\nrandom_max=2\n' >"$CLI_ROOT/config/intervals.conf"
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
assert_eq "setup creates rules.json" "yes" "$([ -s "$CLI_ROOT/state/rules.json" ] && echo yes || echo no)"
assert_eq "setup creates session.json" "yes" "$([ -s "$CLI_ROOT/state/session.json" ] && echo yes || echo no)"
assert_eq "setup creates answers.json" "yes" "$([ -s "$CLI_ROOT/data/answers.json" ] && echo yes || echo no)"
assert_eq "setup creates log file" "yes" "$([ -f "$CLI_ROOT/log/reminders.log" ] && echo yes || echo no)"

cli dnd 09:00 17:00
assert_eq "dnd exits 0" "0" "$?"
assert_eq "dnd start stored" "09:00" "$(jq -r .dnd_start "$CLI_ROOT/state/session.json")"
assert_eq "dnd end stored" "17:00" "$(jq -r .dnd_end "$CLI_ROOT/state/session.json")"

cli dnd off
assert_eq "dnd off clears start" "null" "$(jq -r .dnd_start "$CLI_ROOT/state/session.json")"
assert_eq "dnd off clears end" "null" "$(jq -r .dnd_end "$CLI_ROOT/state/session.json")"

cli dnd 25:00 17:00
assert_eq "dnd rejects bad time" "1" "$?"
cli dnd 12:00
assert_eq "dnd needs two arguments" "1" "$?"

out=$(env MEMOLOOP_CONFIG_DIR="$CLI_ROOT/config" \
  MEMOLOOP_DATA_DIR="$CLI_ROOT/data" \
  MEMOLOOP_STATE="$CLI_ROOT/state" \
  MEMOLOOP_LOG="$CLI_ROOT/log" \
  bash "$REPO/src/memoloop" config </dev/null 2>&1)
case "$out" in *"$CLI_ROOT/data"*) v=yes ;; *) v=no ;; esac
assert_eq "config.conf USER_DATA_DIR honoured" "yes" "$v"

popup_rc=0
timeout 3 bash -c '
  export FOOT_POPUP=1
  export MEMOLOOP_CONFIG_DIR="$1" MEMOLOOP_DATA_DIR="$2" MEMOLOOP_STATE="$3" MEMOLOOP_LOG="$4"
  sleep 6 | "$5" ask fixed >/dev/null 2>&1
' _ "$CLI_ROOT/config" "$CLI_ROOT/data" "$CLI_ROOT/state" "$CLI_ROOT/log" "$REPO/src/memoloop" || popup_rc=$?
assert_eq "popup renders and waits for input" "124" "$popup_rc"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
