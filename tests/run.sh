#!/usr/bin/env bash
# Tests: a real build of the patched wmbattery into a throwaway prefix, install / uninstall, and a privacy scan.
# Set WMBATTERY_SOURCE_DIR to a folder holding the three source files to avoid downloading them.
set -uo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FAILS=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

echo "static checks"
check "install.sh and this script parse" 'bash -n "$REPO/install.sh" && bash -n "$REPO/tests/run.sh"'
check "the patch touches only wmbattery.c" '[ "$(grep -c "^+++ " "$REPO"/patches/*.patch)" = 1 ] && grep -q "^+++ b/wmbattery.c" "$REPO"/patches/*.patch'

echo "real build"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ARGS=(--prefix "$T/prefix")
[ -n "${WMBATTERY_SOURCE_DIR:-}" ] && ARGS+=(--source-dir "$WMBATTERY_SOURCE_DIR")
"$REPO/install.sh" "${ARGS[@]}" > "$T/build.out" 2>&1
check "install.sh succeeds" '[ -x "$T/prefix/bin/wmbattery" ] || { tail -15 "$T/build.out"; false; }'
check "checksums were verified" 'grep -q "Source checksums verified" "$T/build.out"'
check "the program reports its version" '"$T/prefix/bin/wmbattery" -v 2>&1 | grep -qi wmbattery'
check "the binary contains the power code" 'grep -aq "power_now" "$T/prefix/bin/wmbattery"'
check "icons were installed next to it" '[ -f "$T/prefix/share/icons/wmbattery/face.xpm" ]'
"$REPO/install.sh" --uninstall --prefix "$T/prefix" > /dev/null 2>&1
check "--uninstall removes the program and icons" '[ ! -e "$T/prefix/bin/wmbattery" ] && [ ! -e "$T/prefix/share/icons/wmbattery" ]'

echo "a tampered source is refused"
if [ -n "${WMBATTERY_SOURCE_DIR:-}" ]; then
  mkdir "$T/bad" && cp "$WMBATTERY_SOURCE_DIR"/wmbattery_2.56* "$T/bad/" && echo x >> "$T/bad/wmbattery_2.56.orig.tar.gz"
  "$REPO/install.sh" --prefix "$T/p2" --source-dir "$T/bad" > "$T/bad.out" 2>&1
  check "checksum mismatch stops the install" 'grep -q "Checksum mismatch" "$T/bad.out" && [ ! -e "$T/p2/bin/wmbattery" ]'
else ok "skipped (set WMBATTERY_SOURCE_DIR to run it)"; fi

echo "privacy: nothing about the machine that runs these tests is in the repository"
cd "$REPO"; files=$(git ls-files 2>/dev/null || find . -type f -not -path './.git/*')
scan() { hits=$(echo "$files" | xargs grep -nIE -e "$2" 2>/dev/null | grep -v '^tests/run.sh:' | grep -v '^LICENSE:' | grep -vE '^patches/.*:[0-9]+:@@' || true)
  if [ -z "$hits" ]; then ok "$1"; else fail "$1"; echo "$hits" | head -5 | sed 's/^/        /'; fi; }
scan "no absolute home directories" '(/home/[a-z_][a-z0-9_-]*|/Users/[A-Za-z0-9_-]+|/root/)'
scan "no e-mail addresses"          '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
scan "no tokens or private keys"    '(ghp_|gho_|github_pat_|BEGIN [A-Z ]*PRIVATE KEY)'
[ -z "${PRIVACY_TERMS:-}" ] || scan 'none of $PRIVACY_TERMS' "$PRIVACY_TERMS"
echo; if [ "$FAILS" = 0 ]; then echo "all tests passed"; else echo "$FAILS test(s) failed"; exit 1; fi
