#!/usr/bin/env bash
# Builds Debian's wmbattery 2.56 with the power-draw patch and installs it under a prefix (default ~/.local).
# The system package is never touched. Run ./install.sh --help for the options.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PREFIX="${PREFIX:-$HOME/.local}"
POOL="https://deb.debian.org/debian/pool/main/w/wmbattery"
DSC="wmbattery_2.56-1.dsc"
PATCH_FILE="$HERE/patches/0001-show-power-draw-instead-of-the-plug-icon.patch"
SOURCE_DIR="" DRY=0 UNINSTALL=0 INSTALL_DEPS=0 KEEP=0

usage() {
  cat <<USAGE
Usage: ./install.sh [options]
  --prefix DIR       install into DIR (default: \$HOME/.local); the program goes to DIR/bin/wmbattery
  --uninstall        remove what this script installed
  --install-deps     install the build tools and libraries with 'sudo apt-get install' (Debian and derivatives)
  --source-dir DIR   use the already downloaded wmbattery_2.56-1.dsc / .orig.tar.gz / .debian.tar.xz in DIR
  --keep-build       keep the temporary build directory
  --dry-run          show what would be done, change nothing
  -h, --help         this help
USAGE
}
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="${2:?--prefix needs a directory}"; shift ;;
    --uninstall) UNINSTALL=1 ;;
    --install-deps) INSTALL_DEPS=1 ;;
    --source-dir) SOURCE_DIR="${2:?--source-dir needs a directory}"; shift ;;
    --keep-build) KEEP=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
say() { printf '%s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
run() { if [ "$DRY" = 1 ]; then say "[dry-run] $*"; else "$@"; fi; }

if [ "$UNINSTALL" = 1 ]; then
  run rm -f "$PREFIX/bin/wmbattery" "$PREFIX/share/man/man1/wmbattery.1"
  run rm -rf "$PREFIX/share/icons/wmbattery"
  say "Removed. If the Dock launches 'wmbattery' by name it now finds the system one (/usr/bin/wmbattery) again."
  exit 0
fi

# --- build dependencies ---------------------------------------------------------------------------
missing=()
for tool in gcc make pkg-config patch dpkg-source sha256sum tar; do have "$tool" || missing+=("$tool"); done
[ "$SOURCE_DIR" = "" ] && ! have curl && missing+=(curl)
if have pkg-config; then
  for lib in x11 xext xpm upower-glib; do pkg-config --exists "$lib" 2>/dev/null || missing+=("lib:$lib"); done
fi
if [ "${#missing[@]}" -gt 0 ]; then
  say "Missing: ${missing[*]}"
  pkgs="build-essential pkgconf patch curl libx11-dev libxext-dev libxpm-dev libupower-glib-dev"
  if [ "$INSTALL_DEPS" = 1 ] && have apt-get; then run sudo apt-get install -y $pkgs
  else say "Install them with:  sudo apt install $pkgs   (or re-run with --install-deps)"; [ "$DRY" = 1 ] || exit 1; fi
fi

# --- get and check the source ---------------------------------------------------------------------
WORK=$(mktemp -d)
[ "$KEEP" = 1 ] || trap 'rm -rf "$WORK"' EXIT
say "Working in $WORK"
if [ "$DRY" = 1 ]; then
  say "[dry-run] would fetch $DSC and its two tarballs from ${SOURCE_DIR:-$POOL}, verify their SHA-256 sums, unpack,"
  say "[dry-run] apply $(basename "$PATCH_FILE"), then ./configure --prefix=$PREFIX && make && make install"
  exit 0
fi
fetch() {
  if [ -n "$SOURCE_DIR" ]; then cp "$SOURCE_DIR/$1" "$WORK/$1"; else curl -fsSL --retry 2 -o "$WORK/$1" "$POOL/$1"; fi
}
fetch "$DSC"
# the .dsc lists the SHA-256 sum of every file; check what we downloaded against it before unpacking anything
files=$(awk '/^Checksums-Sha256:/{s=1; next} /^[A-Za-z]/{s=0} s{print $3}' "$WORK/$DSC")
for f in $files; do
  fetch "$f"
  want=$(awk -v f="$f" '/^Checksums-Sha256:/{s=1; next} /^[A-Za-z]/{s=0} s && $3==f{print $1}' "$WORK/$DSC")
  got=$(sha256sum "$WORK/$f" | cut -d' ' -f1)
  [ "$want" = "$got" ] || { say "Checksum mismatch for $f (wanted $want, got $got)"; exit 1; }
done
say "Source checksums verified."
(cd "$WORK" && dpkg-source --no-check -x "$DSC" >/dev/null)
SRC=$(find "$WORK" -maxdepth 1 -mindepth 1 -type d -name 'wmbattery-*' | head -n 1)
[ -n "$SRC" ] || { say "could not unpack the source"; exit 1; }

# --- patch, build, install ------------------------------------------------------------------------
cd "$SRC"
patch -p1 --dry-run -s < "$PATCH_FILE" >/dev/null || { say "The patch does not apply to this source."; exit 1; }
patch -p1 -s < "$PATCH_FILE"
say "Patch applied. Building ..."
./configure --prefix="$PREFIX" >/dev/null
make -j"$(nproc 2>/dev/null || echo 2)" >/dev/null
make install >/dev/null
say ""
say "Installed: $PREFIX/bin/wmbattery"
case ":$PATH:" in
  *":$PREFIX/bin:"*) say "$PREFIX/bin is on your PATH; make sure it comes before /usr/bin so this build is the one that runs." ;;
  *) say "Note: $PREFIX/bin is not on your PATH. Put it in front of /usr/bin, or start it by full path." ;;
esac
say "To see it: stop the running one (pkill -x wmbattery) and start wmbattery again; a docked copy"
say "goes back into its Dock slot. Window Maker starts it by name at login, so the new build is used from then on."
