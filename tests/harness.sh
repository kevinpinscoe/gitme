# Sourced into bash or zsh by tests/run.sh -- see that file for usage.
# Arguments: GITME_SCRIPT ROOT (fixture directory prepared by run.sh).
# SC1090: the script under test is passed in. SC2034: the GITME_* variables are read by gitme.
# shellcheck disable=SC1090,SC2034
GITME_SCRIPT="$1"; ROOT="$2"
SHELL_NAME="${ZSH_VERSION:+zsh $ZSH_VERSION}${BASH_VERSION:+bash $BASH_VERSION}"

# Caller options that gitme must leave untouched.
if [[ -n "${ZSH_VERSION-}" ]]; then
  setopt extendedglob; unsetopt globsubst
  opts_before="$(setopt)"
else
  shopt -s nocasematch
  opts_before="$(shopt -p) $-"
fi

. "$GITME_SCRIPT"
GITME_CACHE_DIR="$ROOT/c"; GITME_CACHE_FILE="$ROOT/c/cache"; GITME_IGNORE="$ROOT/c/ignore"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf 'PASS %s\n' "$1"; }
bad() { fail=$((fail+1)); printf 'FAIL %s -- %s\n' "$1" "$2"; }

# t NAME EXPECTED_DIR EXPECTED_RC STDIN SEARCH [GREP_IN_OUTPUT]
t() {
  local name="$1" want_dir="$2" want_rc="$3" input="$4" search="$5" want_out="${6-}" rc out
  cd "$ROOT/start" || return
  out="$ROOT/out.txt"
  gitme "$search" > "$out" 2>&1 <<< "$input"
  rc=$?
  if [[ "$PWD" != "$want_dir" ]]; then bad "$name" "PWD=$PWD want=$want_dir"; return; fi
  if [[ "$rc" != "$want_rc" ]]; then bad "$name" "rc=$rc want=$want_rc"; return; fi
  if [[ -n "$want_out" ]] && ! grep -qF -- "$want_out" "$out"; then bad "$name" "output lacks: $want_out"; return; fi
  ok "$name"
}

R="$ROOT/r"
t "exact+partial: menu, choose 1 (exact first)"   "$R/a/youtrack"                 0 "1" youtrack "1) $R/a/youtrack"
t "exact+partial: menu, choose 2 (partial second)" "$R/b b/youtrack.kevininscoe.com" 0 "2" youtrack "2) $R/b b/youtrack.kevininscoe.com"
t "menu: invalid then valid"                        "$R/a/youtrack"                 0 "9
1" youtrack "Invalid selection."
t "menu: cancel with EOF stays put"                 "$ROOT/start"                   1 "" youtrack
t "single name match jumps directly"               "$R/c/solo repo"                0 "" "solo"  "Found one match: $R/c/solo repo"
t "path with spaces: exact match"                  "$R/c/solo repo"                0 "" "SOLO REPO"
t "case-insensitive name match"                    "$R/d/GitMe-Tool"               0 "" "gitme-TOOL"
t "URL fallback when no name matches"              "$R/e/other"                    0 "" "SpecialHost.Example:O"
t "URL ignored when a name matches"                "$R/f/specialhost-name"         0 "" "specialhost-name"
t "no match"                                        "$ROOT/start"                   1 "" "zzz-nothing" "No matching repositories found."
t "glob chars in search are literal"               "$ROOT/start"                   1 "" "y*k"
printf '%s\n' "$R/g/ignored*  " > "$GITME_IGNORE"
t "ignore-file glob excludes repo"                 "$ROOT/start"                   1 "" "ignoredrepo"
: > "$GITME_IGNORE"
t "ignore cleared: repo found again"               "$R/g/ignoredrepo"              0 "" "ignoredrepo"

# Rebuild the cache from GITME_DIRS (two bases, one containing a space).
cd "$ROOT/start" || exit 1
GITME_DIRS="$ROOT/scan one:$ROOT/missing:$ROOT/scan2" _gitme_build_cache > "$ROOT/out.txt" 2>&1
if grep -qF "Cache rebuilt: 2 repositories found." "$ROOT/out.txt" \
   && grep -qF "$ROOT/scan one/repo x	https://example.com/X.git" "$GITME_CACHE_FILE" \
   && grep -qF "$ROOT/scan2/y" "$GITME_CACHE_FILE"; then ok "rebuild cache: colon list, spaces, missing dir"
else bad "rebuild cache" "$(cat "$ROOT/out.txt"; cat "$GITME_CACHE_FILE")"; fi
t "rebuilt cache: path with spaces + URL"          "$ROOT/scan one/repo x"         0 "" "example.com/x"

if gitme --version | grep -q "0.0.6"; then ok "--version"; else bad "--version" "wrong version"; fi

if [[ -n "${ZSH_VERSION-}" ]]; then opts_after="$(setopt)"; else opts_after="$(shopt -p) $-"; fi
if [[ "$opts_before" == "$opts_after" ]]; then ok "caller shell options unchanged"; else bad "caller options" "changed"; fi
for v in dir repo pattern base rest name_lc url_lc search_lc remote_url matches; do
  if [[ -n "${ZSH_VERSION-}" ]]; then (( ${+parameters[$v]} )) && bad "no leaked variable $v" "set"
  else declare -p "$v" >/dev/null 2>&1 && bad "no leaked variable $v" "set"; fi
done

printf 'RESULT %s: %d passed, %d failed\n' "$SHELL_NAME" "$pass" "$fail"

[[ $fail -eq 0 ]]
