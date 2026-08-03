#!/usr/bin/env bash
#
# Mac App Store / TestFlight build.
#
# Produces a sandboxed, Distribution-signed .app wrapped in an
# Installer-signed .pkg, and optionally uploads it to App Store Connect.
#
#   scripts/build_macos_appstore.sh            # build + sign + validate
#   scripts/build_macos_appstore.sh --upload   # ... and upload to ASC
#   scripts/build_macos_appstore.sh --skip-build   # re-sign an existing build
#
# WHY THIS IS NOT `scripts/build_macos.sh`
#
# The direct-download .app and the App Store .app are different products
# built from the same source, and they cannot share a signing pass:
#
#   - The direct build is NOT sandboxed and sets
#     `com.apple.security.cs.disable-library-validation`, so a user can drop
#     their own libwhisper.dylib next to the app. The App Store forbids both.
#     That feature does not exist in this build, by construction.
#   - Sandboxed apps reach the filesystem only through what the user picks.
#     Model downloads land in the app container, which is fine; anything that
#     assumed a free-roaming path will not work here.
#   - Every nested dylib must be signed by the same Team ID, because library
#     validation is ON. `build_macos.sh` ad-hoc signs them, which is correct
#     for a direct build and fatal for this one — hence the re-sign pass below.
#
# Signing identities are read from SIGN_KEYCHAIN (default: the exportable
# brickwright-build keychain), never login.keychain-db.
#
# Requires in that keychain:
#   "Apple Distribution: … (N9XSJ4M3GT)"                  signs the .app
#   "3rd Party Mac Developer Installer: … (N9XSJ4M3GT)"   signs the .pkg
set -euo pipefail

TEAM_ID="N9XSJ4M3GT"
BUNDLE_ID="com.crispstrobe.crisperweaver"
APP_SIGN="Apple Distribution: Christian Ströbele (${TEAM_ID})"
PKG_SIGN="3rd Party Mac Developer Installer: Christian Ströbele (${TEAM_ID})"
ENTITLEMENTS="macos/Runner/AppStore.entitlements"
PROFILE="${MAC_PROFILE:-}"
APPSTORE_APP_ID="${APPSTORE_APP_ID:-6789600762}"
# Pin the keychain explicitly. Without --keychain, codesign searches the
# default list and can land on login.keychain-db, whose private keys are NOT
# exportable/usable non-interactively: it either prompts (no human on a CI
# runner) or fails with "User canceled". The signing identities live in the
# dedicated exportable keychain; CI overrides this with its own.
SIGN_KEYCHAIN="${SIGN_KEYCHAIN:-$HOME/Library/Keychains/brickwright-build.keychain-db}"
API_KEY="9RMU3C7422"
API_ISSUER="5f618ba3-98ef-42ad-835c-fbbef6c76cf5"

DO_BUILD=1
DO_UPLOAD=0
for arg in "$@"; do
  case "$arg" in
    --upload) DO_UPLOAD=1 ;;
    --skip-build) DO_BUILD=0 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

cd "$(dirname "$0")/.."
APP="build/macos/Build/Products/Release/CrisperWeaver.app"
OUT_PKG="crisper_weaver-macos-appstore.pkg"

VERSION=$(grep '^version:' pubspec.yaml | head -1 | sed 's/version: //' | cut -d+ -f1)
BUILD_NO=$(grep '^version:' pubspec.yaml | head -1 | sed 's/version: //' | cut -d+ -f2)
echo "==> CrisperWeaver ${VERSION} (${BUILD_NO}) — Mac App Store"

if [[ -z "$PROFILE" ]]; then
  echo "!! set MAC_PROFILE to the .provisionprofile path" >&2; exit 2
fi
[[ -f "$PROFILE" ]] || { echo "!! profile not found: $PROFILE" >&2; exit 2; }

if [[ $DO_BUILD -eq 1 ]]; then
  # Delegates to the normal macOS build: it compiles CrispASR's
  # libwhisper.dylib with every backend and then runs
  # bundle_macos_dylibs.sh. A bare `flutter build macos` skips the bundler
  # and produces an app whose backend list is silently empty.
  echo "==> scripts/build_macos.sh release"
  scripts/build_macos.sh release
fi
[[ -d "$APP" ]] || { echo "!! app not found: $APP" >&2; exit 2; }

echo "==> embedding provisioning profile"
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"

# Sign inside-out. Every Mach-O under the bundle must carry the same Team ID
# or library validation refuses to load it at launch.
echo "==> signing nested code (inside-out)"
find "$APP/Contents" \( -name '*.dylib' -o -name '*.so' -o -name '*.framework' \) -print0 \
  | while IFS= read -r -d '' item; do
      codesign --force --timestamp --options runtime \
        --keychain "$SIGN_KEYCHAIN" \
        --sign "$APP_SIGN" "$item" >/dev/null 2>&1 \
        && echo "   signed $(basename "$item")" \
        || echo "   !! FAILED $(basename "$item")"
    done

echo "==> signing app bundle"
codesign --force --timestamp --options runtime \
  --keychain "$SIGN_KEYCHAIN" \
  --entitlements "$ENTITLEMENTS" \
  --sign "$APP_SIGN" "$APP"

echo "==> verifying"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements - --xml "$APP" >/dev/null

echo "==> building signed installer package"
rm -f "$OUT_PKG"
productbuild --component "$APP" /Applications \
  --keychain "$SIGN_KEYCHAIN" --sign "$PKG_SIGN" "$OUT_PKG"
ls -lh "$OUT_PKG"

echo "==> validating with App Store Connect"
xcrun altool --validate-app -f "$OUT_PKG" --type macos \
  --apple-id "$APPSTORE_APP_ID" \
  --apiKey "$API_KEY" --apiIssuer "$API_ISSUER" || {
    echo "!! validation failed — not uploading" >&2; exit 1; }

if [[ $DO_UPLOAD -eq 1 ]]; then
  echo "==> uploading to App Store Connect"
  xcrun altool --upload-package "$OUT_PKG" --type macos \
    --apple-id "$APPSTORE_APP_ID" --bundle-id "$BUNDLE_ID" \
    --bundle-version "$BUILD_NO" --bundle-short-version-string "$VERSION" \
    --apiKey "$API_KEY" --apiIssuer "$API_ISSUER"
  echo "==> uploaded. Processing takes a few minutes."
else
  echo "==> validated only. Re-run with --upload to submit."
fi
