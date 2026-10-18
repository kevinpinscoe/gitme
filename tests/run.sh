#!/usr/bin/env bash
# Regression tests for gitme under bash and zsh.
#
# Usage:
#   bash tests/run.sh                  # every bash and zsh found on this host
#   bash tests/run.sh /bin/zsh         # only the shells named
#   GITME_SCRIPT=/path/to/gitme bash tests/run.sh
#
# gitme is sourced into each shell and called in that same shell, so the
# tests see the caller's real $PWD, shell options and variables. The fixture
# lives in a temporary directory and is removed on exit. Works from any
# current directory. Exits non-zero if any case fails or no shell ran.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITME_SCRIPT="${GITME_SCRIPT:-$HERE/../gitme}"
[[ -f "$GITME_SCRIPT" ]] || { echo "gitme script not found: $GITME_SCRIPT" >&2; exit 2; }
GITME_SCRIPT="$(cd "$(dirname "$GITME_SCRIPT")" && pwd)/$(basename "$GITME_SCRIPT")"

if [[ $# -gt 0 ]]; then
  shells=("$@")
else
  shells=()
  for s in /bin/bash "$(command -v bash 2>/dev/null)" /bin/zsh "$(command -v zsh 2>/dev/null)"; do
    [[ -n "$s" && -x "$s" ]] || continue
    real="$(cd "$(dirname "$s")" && pwd -P)/$(basename "$s")"
    [[ " ${shells[*]-} " == *" $real "* ]] || shells+=("$real")
  done
fi

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/gitme-tests.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
# Resolve symlinks (macOS /tmp -> /private/tmp) so $PWD comparisons match.
ROOT="$(cd "$ROOT" && pwd -P)"

mkdir -p "$ROOT/start" "$ROOT/c"
R="$ROOT/r"
for d in "a/youtrack" "b b/youtrack.kevininscoe.com" "c/solo repo" "d/GitMe-Tool" "e/other" \
         "f/specialhost-name" "g/ignoredrepo"; do mkdir -p "$R/$d"; done
{
  printf '%s\t%s\n' "$R/a/youtrack" "git@github.com:x/youtrack.git"
  printf '%s\t%s\n' "$R/b b/youtrack.kevininscoe.com" "ssh://git@host/yt.git"
  printf '%s\t%s\n' "$R/c/solo repo" ""
  printf '%s\t%s\n' "$R/d/GitMe-Tool" "https://example.org/tool.git"
  printf '%s\t%s\n' "$R/e/other" "git@SpecialHost.example:o.git"
  printf '%s\t%s\n' "$R/f/specialhost-name" "git@specialhost.example:f.git"
  printf '%s\t%s\n' "$R/g/ignoredrepo" ""
  printf '%s\t%s\n' "$R/gone" "deleted-dir-should-be-skipped"
} > "$ROOT/c/cache.base"
mkdir -p "$ROOT/scan one/repo x" "$ROOT/scan2/y"
git -C "$ROOT/scan one/repo x" init -q
git -C "$ROOT/scan one/repo x" remote add origin https://example.com/X.git
git -C "$ROOT/scan2/y" init -q

status=0; ran=0
for sh in "${shells[@]}"; do
  if [[ ! -x "$sh" ]]; then echo "skip: $sh not executable" >&2; status=1; continue; fi
  cp "$ROOT/c/cache.base" "$ROOT/c/cache"; : > "$ROOT/c/ignore"
  echo "=== $sh"
  # Single quotes are intended: the child shell expands $1..$3.
  # shellcheck disable=SC2016
  case "$(basename "$sh")" in
    zsh*) "$sh" -f -c '. "$1" "$2" "$3"' _ "$HERE/harness.sh" "$GITME_SCRIPT" "$ROOT" ;;
    *)    "$sh" --norc --noprofile -c '. "$1" "$2" "$3"' _ "$HERE/harness.sh" "$GITME_SCRIPT" "$ROOT" ;;
  esac || status=1
  ran=$((ran+1))
done

[[ $ran -gt 0 ]] || { echo "no shells ran" >&2; exit 2; }
exit $status
