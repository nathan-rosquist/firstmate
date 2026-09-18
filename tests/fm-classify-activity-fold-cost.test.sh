#!/usr/bin/env bash
# tests/fm-classify-activity-fold-cost.test.sh - the cost SHAPE of the routed
# activity fold (status_open_activities in bin/fm-classify-lib.sh).
#
# The defect this pins: the fold ran four command substitutions per status line,
# and its expensive branch was `working` - the most common verb - so its cost was
# lines x 4 forks. Its only caller reads a secondmate's parent-channel activity
# under a fixed wall-clock budget, and on a host where a bare subshell costs tens
# of milliseconds that budget was blown on every poll: 3.3s at 20 lines and 17.7s
# against a 2s budget at 120. The caller's timeout path is well-formed JSON
# carrying available:false, so the whole fleet's routed-activity evidence
# disappeared with no error, no notification and no diagnostic line, and it got
# worse as the log grew - the busiest mate being the most reliably invisible.
#
# The existing suites cover what the fold OUTPUTS; nothing covered what it COSTS,
# which is why a defect this large lived in correct code. These cases pin the
# cost shape instead, through the real public fold over real status files.
#
# The assertion is forks, not wall-clock, so it is honest on a fast CI runner and
# on a slow loaded one alike: a budget in milliseconds only says "this host is
# quick today", while "the fold does not spend a process per status line" is the
# actual invariant, and it is the one that was violated. Forks are counted from
# the CPU the shell charges to its reaped children, which needs no clock at all.
#
# Raising FM_SNAPSHOT_PARENT_ACTIVITY_TIMEOUT is deliberately NOT what makes
# these pass: the defect's cost grew with the log, so every larger constant fails
# again later and just as silently. Case two is what says so - the same per-line
# bound has to hold at four times the window size.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# shellcheck source=bin/fm-classify-lib.sh
. "$ROOT/bin/fm-classify-lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-classify-activity-fold-cost-tests)
TIMES_FILE="$TMP_ROOT/times"

# The shipped parent-activity window (FM_SNAPSHOT_PARENT_ACTIVITY_LINES defaults
# to 256), and four times it. The second size is the point: the defect was
# super-linear in log length, so a bound that holds only at one size would not
# have caught it.
WINDOW_LINES=256
WIDE_LINES=1024

# The fold must stay this many times under one bare subshell per line. The defect
# spent four per line, so it fails this by a factor of 32; the fix spends none,
# so it passes with the whole budget unused. Nothing sits between those.
FORK_BUDGET_MARGIN=8

# --- fork accounting, without a clock ---------------------------------------
#
# `times` line 2 is the CPU charged to this shell's reaped children. A command
# substitution is such a child, so per-line forks show up there in direct
# proportion to the line count, while a fold that forks nothing adds nothing.
#
# It has to be read WITHOUT forking, for two separate reasons: a fork would make
# the measurement pay for itself, and fork() resets a child's CPU accounting, so
# `cs=$(times)` would faithfully report zero every time. `times` is a builtin and
# a redirect does not fork it; `read` is a builtin too.

# Centiseconds in one "<m>m<s>.<frac>s" field, tolerant of how many decimals the
# shell prints.
field_cs() {  # <out-var> <field>
  local t=$2 min whole dec
  case "$t" in
    *m*.*s) ;;
    *) fail "unreadable times field: $t" ;;
  esac
  t=${t%s}
  min=${t%%m*}
  t=${t#*m}
  whole=${t%%.*}
  dec=${t#*.}
  dec="${dec}00"
  dec=${dec:0:2}
  case "$min$whole$dec" in
    ''|*[!0-9]*) fail "unreadable times field: $2" ;;
  esac
  printf -v "$1" '%s' "$(((10#$min * 60 + 10#$whole) * 100 + 10#$dec))"
}

child_cs() {  # <out-var>
  local self children user sys
  times > "$TIMES_FILE"
  { read -r self; read -r children; } < "$TIMES_FILE"
  : "$self"
  field_cs user "${children%% *}"
  field_cs sys "${children##* }"
  printf -v "$1" '%s' "$((user + sys))"
}

# Child CPU charged by exactly <reps> bare command substitutions. No exec, so
# this prices the fork itself - the precise shape of the per-line calls the fold
# used to make - rather than any program's work.
forks_cost() {  # <out-var> <reps>
  local before after i=0 x
  child_cs before
  while [ "$i" -lt "$2" ]; do
    x=$( : )
    i=$((i + 1))
  done
  : "$x"
  child_cs after
  printf -v "$1" '%s' "$((after - before))"
}

# Child CPU the fold charges for <status-file>, with its output redirected rather
# than captured so the measurement does not fork on the fold's behalf.
fold_cost() {  # <out-var> <status-file> <out-file>
  local before after
  child_cs before
  status_open_activities "$2" > "$3"
  child_cs after
  printf -v "$1" '%s' "$((after - before))"
}

# A routed parent log of <lines> working events across a handful of phases, which
# is both the realistic shape and the fold's most expensive branch.
write_activity_log() {  # <path> <lines>
  local f=$1 n=$2 i=0
  : > "$f"
  while [ "$i" -lt "$n" ]; do
    printf 'working [key=phase%s]: step %s under way on the parent channel\n' \
      "$((i % 9))" "$i" >> "$f"
    i=$((i + 1))
  done
}

# Forks per line are a ratio, so the calibration only has to be above the clock
# tick the host charges CPU in. Grow the sample until it is, rather than assuming
# any particular machine speed.
CAL_REPS=64
CAL_COST=0
while :; do
  forks_cost CAL_COST "$CAL_REPS"
  [ "$CAL_COST" -ge 10 ] && break
  [ "$CAL_REPS" -ge 4096 ] && break
  CAL_REPS=$((CAL_REPS * 2))
done
[ "$CAL_COST" -ge 10 ] \
  || fail "could not price a subshell on this host ($CAL_REPS forks charged ${CAL_COST}cs); the fork bound below would be vacuous"

# fold_cs <= (cal_cs / reps) * lines / margin, kept in integers.
assert_under_fork_budget() {  # <fold-cs> <lines> <label>
  local fold=$1 lines=$2 label=$3
  [ "$((fold * FORK_BUDGET_MARGIN * CAL_REPS))" -le "$((CAL_COST * lines))" ] \
    || fail "$label: the fold charged ${fold}cs of child CPU over $lines lines, against a budget of one subshell per line (${CAL_COST}cs per $CAL_REPS forks) with a ${FORK_BUDGET_MARGIN}x margin - it is forking per status line again"
}

# The records the fold must still produce, whatever it costs: nine phases, each
# left holding its own most recent working event, in most-recently-opened-last
# order - so the last nine lines of the log, in the order they were written.
# Asserting this is what stops a fold that returns early - or does nothing at all
# - from passing the cost cases for free.
assert_fold_output() {  # <out-file> <lines> <label>
  local f=$1 lines=$2 label=$3 got want n i
  want=''
  i=$((lines - 9))
  while [ "$i" -lt "$lines" ]; do
    n=$((i % 9))
    want="${want}phase${n}"$'\t'"working"$'\t'"step $i under way on the parent channel"$'\n'
    i=$((i + 1))
  done
  got=$(cat "$f")
  [ "$got" = "${want%$'\n'}" ] \
    || fail "$label: the fold's records changed
got:
$got
want:
${want%$'\n'}"
}

# The fold reads a whole parent-activity window without spending a process per
# status line. This is the case that fails on the defect, by a factor of 32.
test_activity_fold_spends_no_process_per_line() {
  local dir cost
  dir="$TMP_ROOT/window"
  mkdir -p "$dir"
  write_activity_log "$dir/parent.status" "$WINDOW_LINES"
  fold_cost cost "$dir/parent.status" "$dir/out"
  assert_fold_output "$dir/out" "$WINDOW_LINES" "window fold"
  assert_under_fork_budget "$cost" "$WINDOW_LINES" "window fold"
  pass "a full parent-activity window folds without a process per status line"
}

# The same bound at four times the window. A fold whose per-line cost is a fork
# passes nothing here either, and - the point - a fix that only bought headroom
# inside one budget would come apart exactly here, as the log grows.
test_activity_fold_cost_does_not_grow_with_the_log() {
  local dir cost
  dir="$TMP_ROOT/wide"
  mkdir -p "$dir"
  write_activity_log "$dir/parent.status" "$WIDE_LINES"
  fold_cost cost "$dir/parent.status" "$dir/out"
  assert_fold_output "$dir/out" "$WIDE_LINES" "wide fold"
  assert_under_fork_budget "$cost" "$WIDE_LINES" "wide fold"
  pass "the per-line bound still holds four windows deep, so the cost is flat in log length"
}

# The parent-activity reader pipes its window in on stdin rather than naming a
# file, so the streaming form is the one that actually ships. It must be the same
# fold, at the same cost and with the same records.
test_streaming_form_takes_the_same_path() {
  local dir before after cost
  dir="$TMP_ROOT/stream"
  mkdir -p "$dir"
  write_activity_log "$dir/parent.status" "$WINDOW_LINES"
  child_cs before
  status_open_activities - < "$dir/parent.status" > "$dir/out"
  child_cs after
  cost=$((after - before))
  assert_fold_output "$dir/out" "$WINDOW_LINES" "streaming fold"
  assert_under_fork_budget "$cost" "$WINDOW_LINES" "streaming fold"
  pass "the streamed form the parent-activity reader uses folds at the same bound"
}

test_activity_fold_spends_no_process_per_line
test_activity_fold_cost_does_not_grow_with_the_log
test_streaming_form_takes_the_same_path
