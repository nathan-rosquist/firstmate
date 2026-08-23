# Running Firstmate on Windows

Audience: operator, current behavior.

Firstmate runs natively on Windows under Git Bash or MSYS2.
It does not need WSL, and it is not run through WSL.
Everything below assumes a 64-bit x86 Windows 10 or 11 host and the Git Bash shell that ships with Git for Windows.

The supported runtime backend on Windows is Herdr.
The reference tmux backend has no native Windows build, so tmux is not an option here.
[`herdr-backend.md`](herdr-backend.md) owns that backend's own setup, safety boundaries, and limits, and this page owns only what Windows changes.

## The one setting you must get right

Set `MSYS=winsymlinks:sys` in the environment of every Firstmate process.

Firstmate's entire lock layer is built from symbolic links.
Under the Git Bash default, `ln -s` reports success and creates a **directory copy** instead of a link, so `readlink` returns nothing and no lock can ever be proved owned.
The failure is silent rather than loud: locks never succeed, the supervision cycle never starts, and a supervision checkpoint then reports a quiet fleet because it cannot tell "nothing happened" from "nothing ran".
Residue accumulates as ever-deeper `<lock>.steal.steal...` directories, which eventually exceed the Windows path limit.

The repository ships this variable in its `.claude/settings.json` environment block, so a Claude session started in a checkout that has it is already correct.
A home that predates that block must add it.
Confirm the setting is live before trusting supervision:

```sh
ln -s "$PWD" /tmp/fm-symlink-probe && readlink /tmp/fm-symlink-probe
```

A path on the second line means links work.
Empty output means they do not, whatever the exit status said.

Do not use `winsymlinks:nativestrict`.
Without Windows Developer Mode enabled it aborts the shell rather than degrading.

## Line endings

Git for Windows ships `core.autocrlf=true` in its system configuration, so a fresh clone checks every file out with CRLF line endings.
Shell scripts with CRLF fail to lint and fail to run.
This repository pins LF for tracked text through `.gitattributes`, and a clone should also carry `core.autocrlf=false` locally:

```sh
git config --local core.autocrlf false
```

An existing checkout that already has CRLF on disk keeps working, but convert it before running the linter there.

## Toolchain

Install the pinned tools with the repository's own installers rather than a package manager, so the versions and checksums match the ones CI verifies:

```sh
bin/fm-install-herdr.sh <destination-directory>
bin/fm-install-treehouse.sh <destination-directory>
bin/fm-install-shellcheck.sh <destination-directory>
bin/fm-install-actionlint.sh <destination-directory>
```

Each script header owns its exact release asset, checksum, download bound, and post-install version gate.
All four carry a Windows arm and select it from `uname`.

`jq`, `perl`, and `unzip` come with Git for Windows and are all required.
`python3` is optional and only affects the features named under "Supported limits" below.

The Herdr installer pins 0.8.2 on every platform because that is the earliest stable release carrying a Windows asset.
The Treehouse installer needed no version bump, because its existing pin already publishes Windows assets.

## Herdr pane shell

Set Herdr's default pane shell to Git Bash, in `%APPDATA%/herdr/config.toml`:

```toml
[terminal]
default_shell = "C:/Program Files/Git/usr/bin/bash.exe"
```

Check it with `herdr config check`.
Existing panes keep whatever shell they were created with, so recreate them after changing this.

This is not cosmetic.
Firstmate proves a pane's shell is idle and childless before closing it, and that proof only recognizes a real POSIX shell.
A PowerShell pane fails the proof permanently, which leaves quarantined workspaces behind on every cleanup.

## Supported limits

These are current, measured Windows limits rather than defects awaiting a fix.
Each degrades to a documented fallback rather than failing silently.

- Windows cannot host remote second mates, because it cannot serve as a `--remote` target.
- Herdr's `terminal attach` is unsupported, so use `bin/fm-peek.sh` and `bin/fm-send.sh` rather than attaching.
- Windows Python has no `AF_UNIX`, so native event subscription and presentation-space ordering fall back to polling and flat placement.
- A `noacl` NTFS mount cannot create a directory at mode 700, so the presentation lock namespace accepts the mode it can get after probing for the capability, while its directory, symbolic-link, and owner checks stay unconditional on every platform.
- MSYS `ps` supports no `-o` selectors, so process reads are served from `bin/fm-winproc-lib.sh` in native Windows process-id space, and signalling uses `/usr/bin/kill -W` by absolute path because the shell builtin has no `-W` flag.
- `/usr/bin/kill -W` cannot address a process outside the MSYS runtime at all. That is a safety property rather than a gap, because the signalling path can never reach a process the adapter did not itself resolve.
- Herdr reports no live working directory for a pane on Windows, so Firstmate acquires each task worktree directly with a Treehouse lease instead of reading it back off the terminal. That path is used on every platform, not only this one.
- The downloaded binaries are unsigned, so SmartScreen may warn if they are launched from Explorer. Fetching them with the installers above does not mark them, so they run without a prompt.

## Verification entry points

The Windows lane's measured evidence, including the exact live-suite results and the four adapter paths that carry the platform's differences, lives in [`verification/runtime-backends.md`](verification/runtime-backends.md#windows-x86_64).

Run the linter before treating any script change as done:

```sh
bin/fm-lint.sh
```

It refuses to run under any ShellCheck or actionlint version other than its pins, which the installers above provide.

## Troubleshooting

**A session reports that it cannot locate the harness process in its ancestry, and stays read-only.**
The session lock walks the process ancestry, which needs the Windows process bridge in `bin/fm-winproc-lib.sh`.
A checkout that does not carry that file cannot take the lock and correctly refuses to mutate anything.
Update the checkout rather than working around the refusal.

**Supervision reports a quiet fleet while work is clearly outstanding.**
Check the symbolic-link probe under "The one setting you must get right".
A supervision checkpoint cannot distinguish a completed quiet cycle from a cycle that never started, so a broken lock layer presents as silence.

**The linter reports failures on files you did not touch.**
Check for CRLF line endings first, under "Line endings".

**A spawn refuses because it could not lease a worktree.**
Treehouse must be installed and on `PATH`, and the project must have a Treehouse pool.
`treehouse status` reports the pool for the repository it is run in.
