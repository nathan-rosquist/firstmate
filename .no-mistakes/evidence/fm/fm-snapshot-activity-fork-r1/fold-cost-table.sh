#!/usr/bin/env bash
# Times the parent-activity child script exactly as bin/fm-fleet-snapshot.sh runs
# it (bounded_parent_activities_json), against the pre-fix and post-fix classifier.
set -u
WT=C:/Users/nathan.rosquist/.no-mistakes/worktrees/20139a6921be/01M2TY5353E1WGP7ANGEETTTHR
printf '%-7s %-6s %-7s %-9s %s\n' lib lines rc cost_ms records_in_window
for lib in base fixed; do
  d=/tmp/pa/bin-base/fm-classify-lib.sh
  [ "$lib" = fixed ] && d="$WT/bin/fm-classify-lib.sh"
  for n in 20 120 256; do
    f=/tmp/pa/cost-$n.status
    if [ ! -f "$f" ]; then
      i=0
      while [ "$i" -lt "$n" ]; do
        printf 'working [key=phase%s]: step %s under way on the parent channel\n' "$((i % 9))" "$i"
        i=$((i + 1))
      done > "$f"
    fi
    s=$(date +%s%N)
    out=$(bash /tmp/pa/child.sh "$d" "$f" 256 65536 8 gnu 2>/dev/null); rc=$?
    e=$(date +%s%N)
    printf '%-7s %-6s %-7s %-9s %s\n' "$lib" "$n" "$rc" "$(( (e - s) / 1000000 ))" \
      "$(printf '%s' "$out" | jq -r '.records_in_window // "n/a"')"
  done
done
