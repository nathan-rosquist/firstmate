#!/usr/bin/env bash
# Drives the real product surface - bin/fm-fleet-snapshot.sh --json - over a fleet
# home whose registered secondmate has a routed parent-channel activity log of N
# status lines, and prints the routed-activity evidence the snapshot publishes.
#
# usage: drive-parent-activity.sh <bin-dir> <activity-timeout-seconds> <lines...>
set -u
WT=C:/Users/nathan.rosquist/.no-mistakes/worktrees/20139a6921be/01M2TY5353E1WGP7ANGEETTTHR
BIN=${1:-$WT/bin}
TMO=${2:-2}
WIN=${FM_SNAPSHOT_PARENT_ACTIVITY_LINES:-256}
shift 2 || true
SIZES=${*:-20 256}

. "$WT/tests/lib.sh"
. "$WT/bin/fm-secondmate-registry-lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-parent-activity-drive)
export FM_ROOT_OVERRIDE="$TMP_ROOT/fixture-root"; mkdir -p "$FM_ROOT_OVERRIDE"

printf 'snapshot bin: %s\nFM_SNAPSHOT_PARENT_ACTIVITY_TIMEOUT=%s (shipped default is 2)
FM_SNAPSHOT_PARENT_ACTIVITY_LINES=%s (shipped default is 256)\n\n' "$BIN" "$TMO" "$WIN"

for n in $SIZES; do
  home="$TMP_ROOT/home-$n"; mate="$TMP_ROOT/mate-$n"
  mkdir -p "$home/state" "$home/data" "$home/projects" "$home/config"
  mkdir -p "$mate/state" "$mate/data" "$mate/config" "$mate/projects" "$mate/bin"
  printf '# Firstmate fixture\n' > "$mate/AGENTS.md"
  printf 'domain-alpha\n' > "$mate/.fm-secondmate-home"
  printf -- '- domain-alpha - sample rollout (home: %s; scope: sample rollout; projects: sample; added 2026-07-13)\n' \
    "$mate" > "$home/data/secondmates.md"
  fm_write_secondmate_meta "$home/state/domain-alpha.meta" "$mate" "firstmate:fm-domain-alpha" sample
  printf '## In flight\n\n## Queued\n\n## Done\n' > "$mate/data/backlog.md"

  # The routed parent-channel activity log: n working events across 9 phase keys.
  i=0
  while [ "$i" -lt "$n" ]; do
    printf 'working [key=phase%s]: step %s under way on the parent channel\n' \
      "$((i % 9))" "$i"
    i=$((i + 1))
  done > "$home/state/domain-alpha.status"

  fb=$(fm_fakebin "$home")
  printf '#!/usr/bin/env bash\nexit 1\n' > "$fb/tmux"; chmod +x "$fb/tmux"

  s=$(date +%s%N)
  json=$(PATH="$fb:$PATH" FM_HOME="$home" FM_SNAPSHOT_NOW=2026-07-11T18:00:00Z \
    FM_SNAPSHOT_NOW_EPOCH=1783792800 FM_SNAPSHOT_PARENT_ACTIVITY_TIMEOUT="$TMO" FM_SNAPSHOT_PARENT_ACTIVITY_LINES="$WIN" \
    "$BIN/fm-fleet-snapshot.sh" --json 2>/dev/null)
  e=$(date +%s%N)
  rec=$(printf '%s' "$json" | jq -c '.secondmate_current.records[] | select(.id == "domain-alpha")')
  printf -- '--- %s routed status lines (snapshot wall %s ms) ---\n' "$n" "$(( (e - s) / 1000000 ))"
  printf 'activity_scan   : %s\n' "$(printf '%s' "$rec" | jq -c '.parent_event.activity_scan')"
  printf 'open_activities : %s\n' "$(printf '%s' "$rec" | jq -c '[.parent_event.open_activities[]? | "\(.key)=\(.verb)"]')"
  printf '\n'
done
