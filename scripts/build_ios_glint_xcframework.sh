#!/usr/bin/env bash
#
# Build glint.xcframework (iOS device + simulator slices) for on-device
# MP3 / AAC-LC / Opus encode+decode. glint's Dart loader uses
# `DynamicLibrary.process()` on iOS, so the framework only needs to be
# LINKED into Runner (scripts/wire_ios_glint.rb does that) — at launch
# dyld loads it and its `glint_*` symbols become visible to process().
#
# glint is a self-contained, dependency-free clean-room codec suite
# (only links libc++/libSystem), so this is dramatically simpler than the
# CrispASR xcframework build: one static archive per slice, force-loaded
# into a dynamic framework binary. No ggml, no espeak, no CoreML.
#
# Output: $GLINT_DIR/build-apple/glint.xcframework, mirrored into
# CrisperWeaver/ios/Frameworks/glint.xcframework for the wiring step.
#
# Usage: scripts/build_ios_glint_xcframework.sh
# Env:
#   GLINT_DIR           path to sibling glint repo (default: ../glint)
#   IOS_MIN_OS_VERSION  minimum iOS deployment target (default: 13.0)
#   GLINT_MODE          double|fixed|both (default: fixed — matches
#                       glint's own mobile CI; smaller + no FP reliance)
#   CLEAN               "1" to wipe build dirs first (default 0)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GLINT_DIR="${GLINT_DIR:-$(cd "$REPO_ROOT/.." && pwd)/glint}"
IOS_MIN_OS_VERSION="${IOS_MIN_OS_VERSION:-13.0}"
GLINT_MODE="${GLINT_MODE:-fixed}"
CLEAN="${CLEAN:-0}"

if [[ ! -d "$GLINT_DIR" ]]; then
  echo "error: sibling glint repo not at $GLINT_DIR" >&2
  echo "       Clone it: git clone https://github.com/CrispStrobe/glint \"$GLINT_DIR\"" >&2
  exit 1
fi

cd "$GLINT_DIR"
if [[ "$CLEAN" == "1" ]]; then
  echo "==> cleaning previous iOS glint build dirs"
  rm -rf build-ios-sim build-ios-device build-apple
fi

# Configure + build the static libglint.a for one iOS sdk slice.
build_slice() {
  local sdk="$1" bdir="$2"
  local sysroot; sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  echo "==> cmake configure + build: $sdk ($bdir)"
  cmake -S "$GLINT_DIR" -B "$bdir" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sysroot" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_MIN_OS_VERSION" \
    -DCMAKE_BUILD_TYPE=Release \
    -DGLINT_MODE="$GLINT_MODE" \
    -DCMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO \
    >/dev/null
  cmake --build "$bdir" --config Release --target glint_static >/dev/null
}

# Wrap a slice's libglint.a into a glint.framework (dynamic binary, so
# its exports survive dead-stripping and load at launch → process()).
wrap_framework() {
  local bdir="$1" sdk="$2" min_flag="$3"
  local plat_dir="${GLINT_DIR}/${bdir}"
  local static_lib
  static_lib="$(find "$plat_dir" -name 'libglint.a' | head -1)"
  if [[ -z "$static_lib" || ! -f "$static_lib" ]]; then
    echo "error: libglint.a not produced under $plat_dir" >&2
    exit 2
  fi

  local fw="${plat_dir}/framework/glint.framework"
  rm -rf "$fw"
  mkdir -p "$fw/Headers" "$fw/Modules"
  cp "$GLINT_DIR/include/glint/glint.h" "$fw/Headers/glint.h"

  cat > "$fw/Modules/module.modulemap" <<EOF
framework module glint {
    header "glint.h"
    link "c++"
    export *
}
EOF

  cat > "$fw/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>glint</string>
    <key>CFBundleIdentifier</key><string>org.glint.codec</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>glint</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>MinimumOSVersion</key><string>${IOS_MIN_OS_VERSION}</string>
    <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
    <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
</dict>
</plist>
EOF

  echo "==> linking $bdir → glint.framework/glint"
  xcrun -sdk "$sdk" clang++ -dynamiclib \
    -isysroot "$(xcrun --sdk "$sdk" --show-sdk-path)" \
    -arch arm64 \
    $min_flag \
    -Wl,-force_load,"$static_lib" \
    -install_name "@rpath/glint.framework/glint" \
    -o "$fw/glint"

  # Mark iOS device binaries with the platform build version for
  # App Store validation.
  if [[ "$sdk" == "iphoneos" ]] && xcrun vtool 2>/dev/null; then
    xcrun vtool -set-build-version ios "$IOS_MIN_OS_VERSION" "$IOS_MIN_OS_VERSION" \
      -replace -output "$fw/glint" "$fw/glint" 2>/dev/null || true
  fi

  mkdir -p "${plat_dir}/dSYMs"
  xcrun dsymutil "$fw/glint" -o "${plat_dir}/dSYMs/glint.dSYM" 2>/dev/null || true
}

build_slice iphonesimulator build-ios-sim
build_slice iphoneos       build-ios-device
wrap_framework build-ios-sim    iphonesimulator "-mios-simulator-version-min=$IOS_MIN_OS_VERSION"
wrap_framework build-ios-device iphoneos        "-mios-version-min=$IOS_MIN_OS_VERSION"

mkdir -p build-apple
rm -rf build-apple/glint.xcframework
echo "==> xcodebuild -create-xcframework"
xcodebuild -create-xcframework \
  -framework "${GLINT_DIR}/build-ios-sim/framework/glint.framework" \
  -debug-symbols "${GLINT_DIR}/build-ios-sim/dSYMs/glint.dSYM" \
  -framework "${GLINT_DIR}/build-ios-device/framework/glint.framework" \
  -debug-symbols "${GLINT_DIR}/build-ios-device/dSYMs/glint.dSYM" \
  -output "${GLINT_DIR}/build-apple/glint.xcframework"

DEST="$REPO_ROOT/ios/Frameworks/glint.xcframework"
mkdir -p "$REPO_ROOT/ios/Frameworks"
rm -rf "$DEST"
cp -R "${GLINT_DIR}/build-apple/glint.xcframework" "$DEST"

echo
echo "==> done"
echo "    xcframework: $DEST"
echo "    next: ruby scripts/wire_ios_glint.rb (adds it to Runner.xcodeproj),"
echo "          then flutter build ios"
