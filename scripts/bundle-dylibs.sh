#!/bin/bash
# Make limusic.app self-contained: copy every dylib libmpv needs into
# Contents/Frameworks, rewrite all install names to @executable_path/../Frameworks,
# drop duplicate LC_RPATHs, then ad-hoc re-sign.
#
# Without this the .app only runs on the build machine: the binary links
# libmpv.2.dylib by absolute path, and libmpv in turn links ~40 more dylibs
# (all of ffmpeg, libass, libplacebo, uchardet) the same way.
#
# The dylib graph is taken from an IINA .dmg — IINA ships exactly the mpv stack
# Homebrew ships, pre-relocated to @rpath, universal (x86_64 + arm64), and it
# needs no sudo and no Homebrew to obtain.
#
# Usage: scripts/bundle-dylibs.sh <path-to-limusic.app> <path-to-IINA.app>
set -euo pipefail

APP="${1:?usage: bundle-dylibs.sh <limusic.app> <IINA.app>}"
IINA="${2:?usage: bundle-dylibs.sh <limusic.app> <IINA.app>}"
SRC="$IINA/Contents/Frameworks"
FW="$APP/Contents/Frameworks"

[ -d "$APP" ] || { echo "ERROR: no app bundle at $APP"; exit 1; }
[ -d "$SRC" ] || { echo "ERROR: no IINA frameworks at $SRC"; exit 1; }

BIN="$APP/Contents/MacOS/$(plutil -extract CFBundleExecutable raw "$APP/Contents/Info.plist")"
[ -x "$BIN" ] || { echo "ERROR: no executable at $BIN"; exit 1; }
echo "app: $APP"
echo "bin: $BIN"

rm -rf "$FW"
mkdir -p "$FW"

# 1. Copy the full framework set. libmpv's own install name is @rpath/libmpv.2.dylib,
#    so it must sit next to its friends under Contents/Frameworks.
cp -a "$SRC"/*.dylib "$FW"/
echo "copied $(ls "$FW" | wc -l | tr -d ' ') dylibs"

# 2. Rewrite every dylib: its own id, and every @rpath / absolute dependency, to the
#    executable-relative path.
for f in "$FW"/*.dylib; do
  base="$(basename "$f")"
  install_name_tool -id "@executable_path/../Frameworks/$base" "$f" 2>/dev/null || true
  otool -L "$f" | awk 'NR>1 {print $1}' | while IFS= read -r dep; do
    case "$dep" in
      @rpath/*)
        install_name_tool -change "$dep" "@executable_path/../Frameworks/${dep#@rpath/}" "$f" ;;
      /usr/local/*|/opt/homebrew/*)
        install_name_tool -change "$dep" "@executable_path/../Frameworks/$(basename "$dep")" "$f" ;;
    esac
  done
done

# 3. The app binary: point its deps at the bundled copies.
for dep in $(otool -L "$BIN" | awk 'NR>1 {print $1}'); do
  case "$dep" in
    @rpath/*) install_name_tool -change "$dep" "@executable_path/../Frameworks/${dep#@rpath/}" "$BIN" ;;
    /usr/local/*|/opt/homebrew/*) install_name_tool -change "$dep" "@executable_path/../Frameworks/$(basename "$dep")" "$BIN" ;;
  esac
done

# 4. Collapse duplicate LC_RPATH entries — dyld refuses to load a Mach-O that lists
#    one rpath twice, and the failure is invisible to otool -L and codesign --verify.
dedupe_rpaths() {
  local f="$1"
  otool -l "$f" 2>/dev/null \
    | awk '/LC_RPATH/{g=1; next} g&&/^[[:space:]]*path /{sub(/^[[:space:]]*path /,""); sub(/ \(offset [0-9]+\)$/,""); print; g=0}' \
    | sort | uniq -d | while IFS= read -r dup; do
        echo "  duplicate rpath in $(basename "$f"): $dup"
        install_name_tool -delete_rpath "$dup" "$f" 2>/dev/null || true
      done
}
for f in "$FW"/*.dylib "$BIN"; do dedupe_rpaths "$f"; done

# 5. Sign. arm64 macOS refuses unsigned Mach-O outright; on x86_64 this is what makes
#    the bundle verifiable. Rewriting install names invalidated the linker's signature.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

# 6. Guard: nothing may still point outside the bundle.
echo '--- external references (should be empty; /usr/lib and /System are fine) ---'
find "$APP" -type f -print0 | while IFS= read -r -d '' f; do
  otool -L "$f" 2>/dev/null | awk 'NR>1 {print $1}' \
    | grep -E '^(/opt/homebrew|/usr/local|@rpath)' | sed "s|^|${f#$APP/} <- |"
done || true
echo '--- done ---'