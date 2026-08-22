# Snapshot title strip: before vs after

Input backlog row (markdown-backlog path, annotations mid-line with trailing prose):

```
## Queued
- [ ] mid-line-annotations - Revisit the Windows build lane (repo: litany) (kind: ship) (hold: time gate: revisit on/after 2026-08-20) (hold-until: 2026-08-20) then re-run the smoke pass
- [ ] unannotated - Plain title with no annotations at all
```

## Snapshot JSON records

### BEFORE the fix (base commit 1202c5e)
```json
{
  "id": "mid-line-annotations",
  "title": "Revisit the Windows build lane (repo: litany) (kind: ship) (hold: time gate: revisit on/after 2026-08-20) (hold-until: 2026-08-20) then re-run the smoke pass",
  "repo": "litany",
  "kind": "ship",
  "hold_reason": "time gate: revisit on/after 2026-08-20",
  "hold_until": "2026-08-20"
}
{
  "id": "unannotated",
  "title": "Plain title with no annotations at all",
  "repo": null,
  "kind": null,
  "hold_reason": null,
  "hold_until": null
}
```

### AFTER the fix (target commit d29b619)
```json
{
  "id": "mid-line-annotations",
  "title": "Revisit the Windows build lane then re-run the smoke pass",
  "repo": "litany",
  "kind": "ship",
  "hold_reason": "time gate: revisit on/after 2026-08-20",
  "hold_until": "2026-08-20"
}
{
  "id": "unannotated",
  "title": "Plain title with no annotations at all",
  "repo": null,
  "kind": null,
  "hold_reason": null,
  "hold_until": null
}
```

## Fleet view (end-user render of the Queued section)

### BEFORE the fix
```
## Queued
| ID | Title | Repo | Kind | Blocked By | Artifact |
| --- | --- | --- | --- | --- | --- |
| mid-line-annotations | Revisit the Windows build lane (repo: litany) (kind: ship) (hold: time gate: revisit on/after 2026-08-20) (hold-until: 2026-08-20) then re-run the smoke pass | litany | ship | - | - |
| unannotated | Plain title with no annotations at all | - | - | - | - |

## Done
```

### AFTER the fix
```
## Queued
| ID | Title | Repo | Kind | Blocked By | Artifact |
| --- | --- | --- | --- | --- | --- |
| mid-line-annotations | Revisit the Windows build lane then re-run the smoke pass | litany | ship | - | - |
| unannotated | Plain title with no annotations at all | - | - | - | - |

## Done
```
