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
#   scripts/build_macos_appstore.sh --lite --package-only # signed CI artifact
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
PACKAGE_ONLY=0
FLAVOR=full
for arg in "$@"; do
  case "$arg" in
    --upload) DO_UPLOAD=1 ;;
    --skip-build) DO_BUILD=0 ;;
    --lite) FLAVOR=lite ;;
    --package-only) PACKAGE_ONLY=1 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done
if [[ $PACKAGE_ONLY -eq 1 && $DO_UPLOAD -eq 1 ]]; then
  echo "!! --package-only cannot be combined with --upload" >&2
  exit 2
fi

cd "$(dirname "$0")/.."
# Flutter names the product from pubspec (`crisper_weaver`), NOT the display
# name. `scripts/build_macos.sh` already resolves it this way; guessing
# "CrisperWeaver.app" here silently found nothing.
APP="build/macos/Build/Products/Release/crisper_weaver.app"
OUT_PKG="crisper_weaver-macos-appstore.pkg"
if [[ "$FLAVOR" == "lite" ]]; then
  BUNDLE_ID="com.crispstrobe.crisperweaver.lite"
  APPSTORE_APP_ID="${LITE_APPSTORE_APP_ID:-}"
  OUT_PKG="crisper_weaver-lite-macos-appstore.pkg"
fi
# Lite always requires a fresh build: a manually rebuilt Flutter executable
# could invalidate the source build's flavor stamp without updating the stamp.
if [[ "$FLAVOR" == "lite" && $DO_BUILD -eq 0 ]]; then
  echo "!! --lite cannot be combined with --skip-build; Lite requires a fresh build" >&2
  exit 2
fi
# The full app's existing skip-build workflow requires a matching build stamp.
FLAVOR_STAMP="build/macos/Build/Products/Release/.cw-flavor"
if [[ $DO_BUILD -eq 0 ]] && [[ ! -f "$FLAVOR_STAMP" || "$(cat "$FLAVOR_STAMP")" != "$FLAVOR" ]]; then
  echo "!! --skip-build requires an existing, matching $FLAVOR build stamp" >&2
  exit 2
fi
if [[ $PACKAGE_ONLY -eq 0 && "$FLAVOR" == "lite" && -z "$APPSTORE_APP_ID" ]]; then
  echo "!! set LITE_APPSTORE_APP_ID to the separate Lite App Store Connect app ID" >&2
  exit 2
fi

VERSION=$(grep '^version:' pubspec.yaml | head -1 | sed 's/version: //' | cut -d+ -f1)
BUILD_NO=$(grep '^version:' pubspec.yaml | head -1 | sed 's/version: //' | cut -d+ -f2)
echo "==> CrisperWeaver [$FLAVOR] ${VERSION} (${BUILD_NO}) — Mac App Store"

# A store build must not contain the non-commercial models, and it inherits
# the environment of build_macos.sh, which would honour this.
if [[ "${CW_NONCOMMERCIAL_MODELS:-0}" != "0" ]]; then
  echo "!! CW_NONCOMMERCIAL_MODELS is set — refusing a store build with non-commercial models" >&2
  exit 2
fi

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
  rm -f "$FLAVOR_STAMP"
  CW_FLAVOR="$FLAVOR" scripts/build_macos.sh release
  printf '%s\n' "$FLAVOR" > "$FLAVOR_STAMP"
fi
if [[ ! -d "$APP" ]]; then
  echo "!! app not found: $APP" >&2
  ls -d build/macos/Build/Products/Release/*.app 2>/dev/null >&2 || true
  exit 2
fi

if [[ "$FLAVOR" == "lite" ]]; then
  # Keep the regular app's identity and preferences separate. The executable
  # name remains crisper_weaver so existing dylib and smoke checks still apply.
  LITE_APP="build/macos/Build/Products/Release/lite/CrisperWeaver Lite.app"
  mkdir -p "$(dirname "$LITE_APP")"
  rm -rf "$LITE_APP"
  ditto "$APP" "$LITE_APP"
  APP="$LITE_APP"
fi

# Exercise the actual executable and bundled dylibs while the normal build's
# ad-hoc signature is still locally launchable. An Apple Distribution-signed
# Mac App Store bundle is intentionally rejected by Gatekeeper until Apple
# supplies a TestFlight/App Store receipt, so launching it after signing would
# produce SIGKILL/137 even when the artifact is correct.
echo "==> startup smoke test (before distribution signing)"
scripts/smoke_macos_app.sh "$APP"

echo "==> embedding provisioning profile"
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"

# Refuse an expired or mismatched profile before spending minutes signing.
PROFILE_PLIST=$(mktemp)
SIGN_ENTITLEMENTS=$(mktemp)
trap 'rm -f "$PROFILE_PLIST" "$SIGN_ENTITLEMENTS"' EXIT
cp "$ENTITLEMENTS" "$SIGN_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Set :com.apple.application-identifier ${TEAM_ID}.${BUNDLE_ID}" "$SIGN_ENTITLEMENTS"
security cms -D -i "$PROFILE" >"$PROFILE_PLIST"
PROFILE_APP_ID=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$PROFILE_PLIST")
PROFILE_EXPIRY=$(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "$PROFILE_PLIST")
if [[ "$PROFILE_APP_ID" != "${TEAM_ID}.${BUNDLE_ID}" ]]; then
  echo "!! profile is for $PROFILE_APP_ID, expected ${TEAM_ID}.${BUNDLE_ID}" >&2
  exit 2
fi
echo "   profile: $PROFILE_APP_ID (expires $PROFILE_EXPIRY)"

# Sign inside-out. Every Mach-O under the bundle must carry the same Team ID
# or library validation refuses to load it at launch.
echo "==> signing nested code (inside-out)"
while IFS= read -r -d '' item; do
  if ! codesign --force --timestamp --options runtime \
      --keychain "$SIGN_KEYCHAIN" \
      --sign "$APP_SIGN" "$item" >/dev/null 2>&1; then
    echo "   !! FAILED $(basename "$item")" >&2
    exit 1
  fi
  echo "   signed $(basename "$item")"
done < <(find "$APP/Contents" \
  \( -name '*.dylib' -o -name '*.so' -o -name '*.framework' \) -print0)

echo "==> signing app bundle"
codesign --force --timestamp --options runtime \
  --keychain "$SIGN_KEYCHAIN" \
  --entitlements "$SIGN_ENTITLEMENTS" \
  --sign "$APP_SIGN" "$APP"

echo "==> verifying"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements - --xml "$APP" >/dev/null
CW_EXPECTED_BUNDLE_ID="$BUNDLE_ID" scripts/verify_macos_release.sh --require-distribution "$APP"

echo "==> building signed installer package"
rm -f "$OUT_PKG"
productbuild --component "$APP" /Applications \
  --keychain "$SIGN_KEYCHAIN" --sign "$PKG_SIGN" "$OUT_PKG"
ls -lh "$OUT_PKG"

if [[ $PACKAGE_ONLY -eq 1 ]]; then
  echo "==> signed package ready: $OUT_PKG (validation/upload omitted)"
  exit 0
fi

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
