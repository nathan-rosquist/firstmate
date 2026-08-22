# Generated ship-brief delivery contracts (bin/fm-brief.sh at 017b7eb)

Each section below is the verbatim 'Delivery contract' block from a freshly generated brief.

## mode=no-mistakes (data/evidence-no-mistakes/brief.md)

    Delivery contract: mode=no-mistakes
    The task is complete only when committed on your branch.
    When you believe it is complete, append `done: {summary}` to the status file and stop.
    Firstmate will then instruct you to run /no-mistakes to validate and ship a PR.
    
    You drive no-mistakes by responding to its gates, not by implementing fixes.
    Follow the guidance no-mistakes itself provides for the mechanics: it loads when you invoke /no-mistakes, and `no-mistakes axi run --help` plus the `help` lines in each `axi` response are authoritative and version-matched to the installed binary.
    When starting no-mistakes, make `--intent` preserve all relevant content from this brief's `# Task` section plus every later accepted Firstmate requirement, clarification, constraint, exclusion, and supersession, carrying only each requirement's current accepted form; retain direct requirements instead of substituting a diff summary, and exclude generic operational, status, delivery, and other scaffold boilerplate unless it is task-specific.
    Give that intent the shape of short paragraphs and bullets, never one dense block of prose, while still preserving every requirement above; that is a requirement about the intent's shape, not text to copy into it.
    Do not hand-edit, commit, or fix findings yourself while a run is active - the pipeline applies every fix.
    

## mode=direct-PR (data/evidence-direct-PR/brief.md)

    Delivery contract: mode=direct-PR
    This task ships **direct-PR**: you raise the PR yourself, without the no-mistakes pipeline.
    The task is complete only when committed on your branch.
    When it is implemented and committed, push your branch and open a PR with `gh-axi`, then append `done: PR {url}` to the status file and stop.
    Write the PR description as short paragraphs and bullets, never one dense block of prose; that is a requirement about the description's shape, not text to copy into it.
    Do NOT run /no-mistakes. The configured merge authority decides whether to merge the PR; firstmate relays the outcome.

## mode=local-only (data/evidence-local-only/brief.md)

    Delivery contract: mode=local-only
    This task ships **local-only**: no remote, no PR, no pipeline.
    The task is complete only when committed on your branch `fm/evidence-local-only`. Do NOT push, do NOT open a PR, do NOT merge.
    Keep your branch a clean fast-forward onto the current default branch - if `main` has advanced, rebase onto it so the eventual merge stays a fast-forward.
    When it is implemented and committed, append `done: ready in branch fm/evidence-local-only` to the status file and stop.
    The configured merge authority approves the ready branch, then firstmate merges it into local `main` through the guarded fast-forward path.
