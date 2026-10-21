#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Fetch the ICC profiles of the Epson SC-F100 from Epson's official macOS driver.
#
# The profiles are copyrighted (c) Seiko Epson and therefore not shipped with this project.
# This script downloads the macOS driver directly from Epson, verifies its checksum, unpacks only
# the two profiles and verifies them as well. It needs neither macOS nor network access beyond Epson.
#
# Usage: fetch-icc.sh [TARGET_DIR]            (default: /usr/share/scf100-sublimation/profiles)
#        fetch-icc.sh --dmg FILE [TARGET_DIR] use an already downloaded driver (.dmg)
#
# Needs: curl, 7-Zip (7z/7zz; reads DMG and xar), bsdtar (libarchive; reads the cpio payload)
# Driver EPIJDataManager 13.45, checked 2026-10-19.
set -euo pipefail

URL="https://download.epson-europe.com/pub/download/6773/epson677363eu.dmg"
DMG_SHA="2443f5fc23af14218f296930894a4fc139e29f1c5dd4f539134780e5541676be"
SUBPKG="SC-F100_Series.W.Machine_106_and_later.pkg"
SUBPATH="Library/Printers/EPSON/InkjetPrinter2/ICCProfiles/EP2004LI1.profiles/Contents/Resources"
declare -A PROFILES=(
  [rigid.icc]="Epson_SC-F100_Series_GeneralPurpose(Rigid).icc ab947b7f88a6a4c4c33ab8c8761959476e1f25df4bbd243bfd0efec76fe57418"
  [textile.icc]="Epson_SC-F100_Series_GeneralPurpose(Textile).icc 600d92e174dada962274eeb19c066faf696a4b4ccbde3a075b9d408a9a9a026e"
)

# Messages in German for a German locale, otherwise English (install.sh passes SCF100_LANG on)
case "${SCF100_LANG:-${LC_ALL:-${LC_MESSAGES:-${LANGUAGE:-${LANG:-}}}}}" in de|de_*|de.*|de:*) LANGUAGE_=de ;; *) LANGUAGE_=en ;; esac
t() { if [ "$LANGUAGE_" = de ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }
die() { echo "$(t FEHLER ERROR): $*" >&2; exit 1; }

DMG=""
if [ "${1:-}" = "--dmg" ]; then
  [ $# -ge 2 ] || die "--dmg $(t "braucht eine Datei" "needs a file")"
  DMG="$2"; shift 2
fi
TARGET="${1:-/usr/share/scf100-sublimation/profiles}"

SEVENZIP=$(command -v 7z || command -v 7zz || true)   # 7-Zip is called 7z or 7zz depending on the distribution
[ -n "$SEVENZIP" ] || die "$(t "7-Zip (7z/7zz) fehlt" "7-Zip (7z/7zz) is missing")"
for w in bsdtar sha256sum $([ -n "$DMG" ] || echo curl); do
  command -v "$w" >/dev/null || die "$w $(t fehlt "is missing")"
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if [ -z "$DMG" ]; then
  DMG="$WORK/driver.dmg"
  echo "$(t "Lade den macOS-Treiber von Epson (65 MB) ..." "Downloading the macOS driver from Epson (65 MB) ...")"
  curl -fL --progress-bar --retry 2 -o "$DMG" "$URL"
fi
echo "$DMG_SHA  $DMG" | sha256sum -c --quiet - \
  || die "$(t "Prüfsumme des Treibers stimmt nicht - anderer Stand bei Epson?" "driver checksum does not match - has Epson changed the download?")"

echo "$(t "Entpacke ..." "Unpacking ...")"
"$SEVENZIP" x -y -o"$WORK/dmg" "$DMG" >/dev/null
PKG=$(find "$WORK/dmg" -name "*.pkg" -type f | head -1)
[ -n "$PKG" ] || die "$(t "kein .pkg im DMG gefunden" "no .pkg found in the DMG")"
"$SEVENZIP" x -y -o"$WORK/pkg" "$PKG" "$SUBPKG/Payload" >/dev/null
mkdir -p "$WORK/x"
# Extract only the profiles; if bsdtar rejects the pattern, extract everything (pipefail makes || apply)
"$SEVENZIP" x -so "$WORK/pkg/$SUBPKG/Payload" | bsdtar -x -C "$WORK/x" -f - "./$SUBPATH/*.icc" 2>/dev/null \
  || "$SEVENZIP" x -so "$WORK/pkg/$SUBPKG/Payload" | bsdtar -x -C "$WORK/x" -f -

mkdir -p "$TARGET"
for name in "${!PROFILES[@]}"; do
  read -r source sha <<<"${PROFILES[$name]}"
  file=$(find "$WORK/x" -name "$source" -type f | head -1)
  [ -n "$file" ] || die "$source $(t "nicht im Treiber gefunden" "not found in the driver")"
  echo "$sha  $file" | sha256sum -c --quiet - || die "$(t "Prüfsumme stimmt nicht" "checksum does not match"): $source"
  install -m 644 "$file" "$TARGET/$name"
  echo "OK  $TARGET/$name  ($source)"
done
