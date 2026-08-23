#!/usr/bin/env bash
# shellcheck shell=bash
# Path-form conversion between the MSYS (Git Bash) world and native Windows
# binaries.
#
# ONE owner of that conversion. A Git Bash home speaks POSIX paths (/tmp/x,
# /c/Users/x) while a native Windows program launched from it resolves only
# Windows paths (C:/Users/x). Every place firstmate hands a path across that
# boundary must go through here, so the rule lives in one file rather than
# being re-derived per call site.
#
# WARNING - converting the wrong value is worse than not converting at all.
# Convert ONLY a value handed to a native, non-MSYS program: go.exe, node.exe,
# a native CLI. Never convert a path an MSYS tool consumes, and never convert
# a path baked into a generated pane hook. The generated grok turn-end hook in
# bin/fm-spawn.sh matches its argument against `/*.turn-ended`; a Windows-form
# path fails that pattern, so the hook exits 0 and the whole turn-end
# continuity layer goes quiet with no error anywhere.
#
# This file is sourced by scripts and has no side effects on source.
#
# cygpath is resolved through `command -v` on every call, so a test can inject
# a fixture ahead of it on PATH. When cygpath is absent, or runs and fails, the
# input is printed unchanged: a partial or empty conversion of a non-empty path
# is never emitted, because a caller cannot tell that apart from a real answer.
#
# Env seam, mainly for tests:
#   FM_PLATFORM_UNAME  replace `uname -s`, so the MSYS branch can be driven on
#                      any host.
# FM_PLATFORM_MSYS caches the probed verdict for this process; empty means the
# verdict has not been taken yet.

FM_PLATFORM_MSYS=${FM_PLATFORM_MSYS:-}

# Print the kernel name this host reports.
fm_platform_uname() {
  printf '%s\n' "${FM_PLATFORM_UNAME:-$(uname -s)}"
}

# True when this shell runs under MSYS/MinGW (Git Bash).
fm_platform_is_msys() {
  if [ -z "$FM_PLATFORM_MSYS" ]; then
    case "$(fm_platform_uname)" in
      MINGW*|MSYS*) FM_PLATFORM_MSYS=1 ;;
      *) FM_PLATFORM_MSYS=0 ;;
    esac
  fi
  [ "$FM_PLATFORM_MSYS" = 1 ]
}

# Print the form a native Windows binary resolves.
#
# cygpath -m yields the mixed form (C:/Users/x): a drive letter with forward
# slashes, so the result needs no escaping inside JSON or a quoted shell word.
fm_path_native() {  # <path>
  local path=$1 cygpath out
  [ -n "$path" ] || return 0
  if fm_platform_is_msys && cygpath=$(command -v cygpath 2>/dev/null); then
    if out=$("$cygpath" -m -- "$path" 2>/dev/null) && [ -n "$out" ]; then
      printf '%s\n' "$out"
      return 0
    fi
  fi
  printf '%s\n' "$path"
}

# Print the POSIX form MSYS tools use.
fm_path_posix() {  # <path>
  local path=$1 cygpath out
  [ -n "$path" ] || return 0
  if fm_platform_is_msys && cygpath=$(command -v cygpath 2>/dev/null); then
    if out=$("$cygpath" -u -- "$path" 2>/dev/null) && [ -n "$out" ]; then
      printf '%s\n' "$out"
      return 0
    fi
  fi
  printf '%s\n' "$path"
}
