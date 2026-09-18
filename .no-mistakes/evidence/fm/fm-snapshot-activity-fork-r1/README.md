# Live validation: the routed-activity fold no longer blows the parent-activity budget

Branch `fm/fm-snapshot-activity-fork-r1`, base `f1fc96e`, target `b452807`.
Host: Windows 11 Pro / Cygwin bash 5.3 — a host where a bare fork costs tens of
milliseconds, which is why the defect is visible here at all.

Everything below was driven against the real product: `bin/fm-fleet-snapshot.sh`
and `bin/fm-bearings-snapshot.sh` over a fixture fleet home whose registered
secondmate has a routed parent-channel activity log. "base" runs are the same
product with only `bin/fm-classify-lib.sh` reverted to the base commit.

| file | what it shows |
| --- | --- |
| `parent-activity-read-cost.txt` | The read cost, timed as the snapshot runs it: base 7.2 s / 32.3 s / 69.9 s at 20 / 120 / 256 lines, versus 3.19 s / 2.89 s / 3.12 s after the fix. Same 9 records every time. The cost is now flat in log length. |
| `snapshot-base-timeout10.txt` | Pre-fix `fm-fleet-snapshot.sh --json`: at 20 lines `available:true`; at 256 lines `available:false, reasons:["timeout"]`, zero records, snapshot otherwise normal — the silent drop. |
| `snapshot-fixed-timeout10.txt` | Post-fix, same fixture and budget: `available:true` at both sizes, all nine phase keys published. |
| `bearings-base-256.txt` / `bearings-fixed-256.txt` | The operator-visible Bearings report for the same fleet: `omitted[9]` carrying "secondmate parent activity evidence unavailable for 1 record(s)" before, `omitted[8]` without it after. |
| `raising-the-constant-is-not-the-fix.txt` | Adversarial: budget raised 10x to 20 s over a 1024-line window. Pre-fix still times out; post-fix publishes the whole window. A larger constant is not a fix. |
| `fold-cost-suite-fails-before-the-fix.txt` | The new regression suite run against the pre-fix classifier: `not ok - wide fold ... it is forking per status line again`. It passes on the fixed classifier, so it fails before and passes after. |
| `base-vs-fixed-semantics-differential.txt` | `status_open_activities`, `status_open_decisions` and `status_open_decisions_incremental`, named-file and streaming forms, byte-identical pre-fix vs post-fix over two crafted corpora (both key positions, malformed and empty slugs, corr tags, mid-note key prose, closing verbs, blank lines, reopening). |
| `drop-rewrite-adversarial-corpus.txt` | Adversarial for the `_fm_decision_drop` rewrite specifically: prefix-sharing keys (`phase1`/`phase10`/`phase100`, `a`/`ab`), the open set emptying and refilling, an empty note. Byte-identical to pre-fix. |
| `changed-file-selection.txt` | `bin/fm-test-run.sh --list --changed` with `bin/fm-classify-lib.sh` modified now selects both `fm-classify-activity-fold-cost.test.sh` and `fm-classify-decision-key.test.sh` alongside the watcher family. |
| `snapshot-fixed-shipped-2s-windows.txt` | The known residual: at the shipped 2 s budget this Cygwin host still times out post-fix. `parent-activity-read-cost.txt` attributes that to three jq startups (~1.7 s) and bash startup plus sourcing the classifier (~0.4 s); the fold itself is ~0.24 s of the 3.12 s. Separately filed as residual budget headroom and out of scope here. |

## Reproducing

`drive-parent-activity.sh <bin-dir> <activity-timeout-s> <lines...>` and
`drive-bearings-report.sh` (same arguments) build the fixture fleet and drive the
real product. `fold-cost-table.sh` times the snapshot's own parent-activity child
script. A "base" bin dir is made with
`cp -r bin /tmp/pa/bin-base && git show f1fc96e:bin/fm-classify-lib.sh > /tmp/pa/bin-base/fm-classify-lib.sh`,
and `/tmp/pa/child.sh` is the child script extracted verbatim from
`bounded_parent_activities_json`.
