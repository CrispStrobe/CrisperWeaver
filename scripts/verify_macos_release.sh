#!/usr/bin/env bash
# Verify the exact macOS app that will be packaged or distributed.
set -euo pipefail

REQUIRE_DISTRIBUTION=0
if [[ "${1:-}" == "--require-distribution" ]]; then
  REQUIRE_DISTRIBUTION=1
  shift
fi

APP="${1:-build/macos/Build/Products/Release/crisper_weaver.app}"
[[ -d "$APP" ]] || { echo "error: app not found: $APP" >&2; exit 2; }

INFO="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/crisper_weaver"
[[ -f "$INFO" && -x "$EXECUTABLE" ]] || {
  echo "error: incomplete app bundle: $APP" >&2
  exit 2
}

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")
MIN_OS=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO")
[[ "$BUNDLE_ID" == "com.crispstrobe.crisperweaver" ]] || {
  echo "error: unexpected bundle id: $BUNDLE_ID" >&2
  exit 1
}

codesign --verify --deep --strict --verbose=1 "$APP"

MAIN_ARCHS=$(lipo -archs "$EXECUTABLE")
[[ "$MAIN_ARCHS" == "arm64" ]] || {
  echo "error: main executable architectures are '$MAIN_ARCHS'; expected arm64 only" >&2
  echo "       Bundled inference engines do not currently support Intel Macs." >&2
  exit 1
}

version_at_most() {
  awk -v actual="$1" -v maximum="$2" 'BEGIN {
    split(actual, a, "."); split(maximum, m, ".")
    for (i = 1; i <= 3; i++) {
      av = (a[i] == "" ? 0 : a[i]) + 0
      mv = (m[i] == "" ? 0 : m[i]) + 0
      if (av < mv) exit 0
      if (av > mv) exit 1
    }
    exit 0
  }'
}

MACHO_COUNT=0
while IFS= read -r -d '' item; do
  if file "$item" | grep -Fq 'Mach-O'; then
    MACHO_COUNT=$((MACHO_COUNT + 1))
    ARCHS=$(lipo -archs "$item")
    case " $ARCHS " in
      *' arm64 '*) ;;
      *) echo "error: $item does not contain arm64 (architectures: $ARCHS)" >&2; exit 1 ;;
    esac
    while read -r ITEM_MIN_OS; do
      [[ -n "$ITEM_MIN_OS" ]] || continue
      if ! version_at_most "$ITEM_MIN_OS" "$MIN_OS"; then
        echo "error: $item requires macOS $ITEM_MIN_OS but app declares $MIN_OS" >&2
        exit 1
      fi
    done < <(vtool -show-build "$item" 2>/dev/null | awk '$1 == "minos" { print $2 }')
    codesign --verify --strict "$item"
    if [[ $REQUIRE_DISTRIBUTION -eq 1 ]]; then
      TEAM=$(codesign -dvv "$item" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -1)
      [[ "$TEAM" == "N9XSJ4M3GT" ]] || {
        echo "error: $item has TeamIdentifier '${TEAM:-missing}'" >&2
        exit 1
      }
    fi
  fi
done < <(find "$APP/Contents" -type f -print0)

[[ $MACHO_COUNT -gt 0 ]] || { echo "error: no Mach-O files found" >&2; exit 1; }

echo "macOS release verification OK: $VERSION ($BUILD), $MACHO_COUNT Mach-O files"
