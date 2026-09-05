#!/usr/bin/env bash
# Shared no-mistakes axi run attribution primitives.
#
# ONE owner for the branch+code-identity matching rule that decides whether a
# no-mistakes run belongs to a given worktree, used by fm-crew-state.sh
# (read-only current-state reporting) and fm-teardown.sh (pre-teardown run
# abort, see its "Fix 1" header comment). Getting this wrong in either
# direction is unsafe: a false negative hides a genuinely parked run, and a
# false positive lets teardown act on a run it does not own.
#
# Bounded call to `no-mistakes "$@"` in dir $1, timeout $2 seconds. The bounded
# form preserves stdout, stderr, and exit status; the checked form discards
# stderr, while fm_nm_run keeps the fail-open query contract for read-only callers.
fm_nm_run_bounded() {  # <dir> <timeout_secs> <args...>
  local dir=$1 timeout_secs=$2 have_timeout=none
  shift 2
  if command -v timeout >/dev/null 2>&1; then have_timeout=timeout
  elif command -v gtimeout >/dev/null 2>&1; then have_timeout=gtimeout
  elif command -v perl >/dev/null 2>&1; then have_timeout=perl
  fi
  case "$have_timeout" in
    timeout)  ( cd "$dir" && timeout "$timeout_secs" no-mistakes "$@" ) ;;
    gtimeout) ( cd "$dir" && gtimeout "$timeout_secs" no-mistakes "$@" ) ;;
    perl)     ( cd "$dir" && perl -e 'my $t = shift; my $pid = fork; die "fork failed" unless defined $pid; if (!$pid) { setpgrp(0, 0); exec @ARGV } local $SIG{ALRM} = sub { kill "TERM", -$pid; select undef, undef, undef, 0.2; kill "KILL", -$pid; exit 124 }; alarm $t; waitpid $pid, 0; exit($? >> 8)' "$timeout_secs" no-mistakes "$@" ) ;;
    *)        return 1 ;;
  esac
}

fm_nm_run_checked() {  # <dir> <timeout_secs> <args...>
  fm_nm_run_bounded "$@" 2>/dev/null
}

fm_nm_run() {  # <dir> <timeout_secs> <args...>
  fm_nm_run_checked "$@" || true
}

fm_nm_trim() {
  local s=${1:-}
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

fm_nm_strip_quotes() {
  local s
  s=$(fm_nm_trim "${1:-}")
  case "$s" in
    \"*\") s=${s#\"}; s=${s%\"} ;;
  esac
  fm_nm_trim "$s"
}

# Scalar value of a TOON key in captured `axi status` output $1.
fm_nm_field() {  # <toon-output> <key>
  printf '%s\n' "$1" | sed -n "s/^[[:space:]]*$2:[[:space:]]*\(.*\)/\1/p" | head -1
}

# Classify run head $2 against worktree $1's code identity. Echoes one word:
#   match        - equal commits (short or full SHA), or the worktree HEAD is an
#                  ancestor of the run head (pipeline fix commits on the same
#                  history advanced the run tip past local HEAD)
#   mismatch     - resolvable here and proven to be different history: the run
#                  head is a strict ancestor of the worktree HEAD (local work
#                  advanced outside the run), or the two have diverged (the
#                  branch tip was rewritten)
#   unresolvable - the run head names a commit this worktree cannot resolve, so
#                  there is no evidence either way. The routine cause is a
#                  pipeline-side head whose fix commits were pushed but never
#                  fetched into the crew worktree.
#   none         - no head to bind at all: an absent or empty head field, or a
#                  worktree whose own HEAD cannot be read
# The `unresolvable` and `none` cases are deliberately distinct: absent evidence
# about a real commit is weaker than having no commit named at all, and callers
# that may prefer a live run over a stale one need to tell them apart.
fm_nm_head_verdict() {  # <worktree> <run_head>
  local wt=$1 run_head=$2 local_full run_full
  [ -n "$run_head" ] || { printf 'none'; return 0; }
  local_full=$(git -C "$wt" rev-parse HEAD 2>/dev/null) || { printf 'none'; return 0; }
  run_full=$(git -C "$wt" rev-parse --verify "${run_head}^{commit}" 2>/dev/null) \
    || { printf 'unresolvable'; return 0; }
  [ "$run_full" = "$local_full" ] && { printf 'match'; return 0; }
  if git -C "$wt" merge-base --is-ancestor "$local_full" "$run_full" 2>/dev/null; then
    printf 'match'
  else
    printf 'mismatch'
  fi
}

# 0 only when run head $2 is proven to be worktree $1's own code identity, i.e.
# the `match` verdict above. Every weaker verdict rejects, so a caller that only
# asks this question never attributes a run on absent or ambiguous evidence.
fm_nm_head_matches_worktree() {  # <worktree> <run_head>
  [ "$(fm_nm_head_verdict "$1" "$2")" = match ]
}
