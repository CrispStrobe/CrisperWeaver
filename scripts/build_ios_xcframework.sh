#!/usr/bin/env bash
#
# Build crispasr.xcframework with iOS-only slices (device + simulator).
#
# This is the slim, dev-machine alternative to
# CrispASR/build-xcframework.sh, which builds 7 Apple platform slices
# (iOS, macOS, visionOS, tvOS, all device + simulator). The full script
# eats 30-60 min and 7-20 GB of disk. Production iOS builds and the
# release IPA happen in CI (.github/workflows); this script exists so a
# single dev machine can sideload-test on a connected iPhone/iPad
# without paying the full multi-platform tax.
#
# Output: $CRISPASR_DIR/build-apple/crispasr.xcframework with two
# slices (ios-arm64, ios-arm64_x86_64-simulator). Drag that into
# Runner.xcodeproj with "Embed & Sign" — the framework's install_name
# is @rpath/crispasr.framework/crispasr, which matches the third
# candidate the package:crispasr loader tries.
#
# Usage: scripts/build_ios_xcframework.sh
#
# Env:
#   CRISPASR_DIR          path to sibling CrispASR repo
#                         (default: ../CrispASR)
#   IOS_MIN_OS_VERSION    minimum iOS deployment target (default: 13.0,
#                         matching CrisperWeaver's Podfile)
#   COREML                "ON"/"OFF" (default: ON) — wires the .mlmodelc
#                         encoder for whisper backends, ~2-3× faster on
#                         the Apple Neural Engine.
#   CLEAN                 "1" to wipe build dirs first, "0" (default) to
#                         resume from existing cmake caches.
#   ESPEAK_NG             "1"/"ON" to cross-build libespeak-ng (+libucd)
#                         for iOS and link it into the framework so kokoro
#                         phonemizes in-process instead of shelling out to
#                         a non-existent `espeak-ng` binary (kokoro's iOS
#                         limitation). Default "OFF" — the build is then
#                         byte-for-byte identical to before. When ON the
#                         script also stages the real espeak-ng-data tree
#                         as the `assets/espeak-ng-data.tar.gz` Flutter
#                         asset (replacing the repo's placeholder) so the
#                         phoneme tables ship with the dev build. Every
#                         espeak step is non-fatal: on any failure it warns
#                         and falls back to the no-espeak build so the
#                         xcframework still gets produced.
#   ESPEAK_NG_REF         espeak-ng git ref to build (default "master" —
#                         tagged releases lack the cross-compile data
#                         bypass; see the Android CI step for the why).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CRISPASR_DIR="${CRISPASR_DIR:-$(cd "$REPO_ROOT/.." && pwd)/CrispASR}"
IOS_MIN_OS_VERSION="${IOS_MIN_OS_VERSION:-13.0}"
COREML="${COREML:-ON}"
CLEAN="${CLEAN:-0}"
ESPEAK_NG="${ESPEAK_NG:-OFF}"
ESPEAK_NG_REF="${ESPEAK_NG_REF:-master}"

if [[ ! -d "$CRISPASR_DIR" ]]; then
  echo "error: sibling CrispASR repo not at $CRISPASR_DIR" >&2
  echo "       Clone it: git clone https://github.com/CrispStrobe/CrispASR \"$CRISPASR_DIR\"" >&2
  exit 1
fi

CRISPEMBED_DIR="${CRISPEMBED_DIR:-$(cd "$REPO_ROOT/.." && pwd)/CrispEmbed}"
if [[ ! -d "$CRISPEMBED_DIR" ]]; then
  echo "error: sibling CrispEmbed repo not at $CRISPEMBED_DIR" >&2
  echo "       Clone it: git clone https://github.com/CrispStrobe/CrispEmbed \"$CRISPEMBED_DIR\"" >&2
  exit 1
fi

cd "$CRISPASR_DIR"

if [[ "$CLEAN" == "1" ]]; then
  echo "==> cleaning previous iOS build dirs"
  rm -rf build-ios-sim build-ios-device build-apple
fi

# COREML on iOS needs deployment target ≥ 14.0; if the user picked
# something lower, drop COREML rather than fail at link time.
EFFECTIVE_COREML="$COREML"
if [[ "$EFFECTIVE_COREML" == "ON" ]]; then
  major="${IOS_MIN_OS_VERSION%%.*}"
  if [[ "$major" -lt 14 ]]; then
    echo "warn: IOS_MIN_OS_VERSION=$IOS_MIN_OS_VERSION < 14.0; disabling CoreML" >&2
    EFFECTIVE_COREML="OFF"
  fi
fi

COMMON_C_FLAGS="-Wno-macro-redefined -Wno-shorten-64-to-32 -Wno-unused-command-line-argument -g"
COMMON_CXX_FLAGS="$COMMON_C_FLAGS"

COMMON_CMAKE_ARGS=(
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY=
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
  -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf-with-dsym
  -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES
  -DCMAKE_XCODE_ATTRIBUTE_COPY_PHASE_STRIP=NO
  -DCMAKE_XCODE_ATTRIBUTE_STRIP_INSTALLED_PRODUCT=NO
  -DBUILD_SHARED_LIBS=OFF
  -DCRISPASR_BUILD_EXAMPLES=OFF
  -DCRISPASR_BUILD_TESTS=OFF
  -DCRISPASR_BUILD_SERVER=OFF
  -DCRISPASR_OPUS_FETCH=ON
  -DGGML_METAL_EMBED_LIBRARY=ON
  -DGGML_BLAS_DEFAULT=ON
  -DGGML_METAL=ON
  -DGGML_METAL_USE_BF16=ON
  -DGGML_NATIVE=OFF
  -DGGML_OPENMP=OFF
  # CRISPASR_WITH_ESPEAK_NG is set PER SLICE below — historically forced
  # OFF here (kokoro fell back to a popen("espeak-ng") shellout that
  # doesn't exist on iOS, so kokoro couldn't phonemize). When ESPEAK_NG=1
  # we cross-build libespeak-ng for the matching iOS slice and point the
  # CrispASR cmake at it; otherwise it stays OFF and this build is
  # identical to before.
  -DCMAKE_OSX_DEPLOYMENT_TARGET=$IOS_MIN_OS_VERSION
)

# ---------------------------------------------------------------------
# Optional (ESPEAK_NG=1): cross-build libespeak-ng (+libucd) for each
# iOS slice and point CrispASR's cmake at it, so kokoro phonemizes
# in-process. Every step is non-fatal — on failure we warn and the
# affected slice stays OFF (identical to the historical build), so the
# xcframework is always produced. Defaults leave everything OFF.
# ---------------------------------------------------------------------
ESPEAK_SRC="${CRISPASR_DIR}/build-espeak-ng/espeak-ng-src"
ESPEAK_ARGS_SIM=(-DCRISPASR_WITH_ESPEAK_NG=OFF)
ESPEAK_ARGS_DEVICE=(-DCRISPASR_WITH_ESPEAK_NG=OFF)
ESPEAK_LIBS_SIM=""
ESPEAK_LIBS_DEVICE=""

espeak_clone() {
  [[ -d "$ESPEAK_SRC/.git" ]] && return 0
  mkdir -p "$(dirname "$ESPEAK_SRC")"
  git clone --depth=1 --branch "$ESPEAK_NG_REF" \
    https://github.com/espeak-ng/espeak-ng.git "$ESPEAK_SRC" >&2
}

# Cross-build the static lib for one iOS sdk. Echoes "<inc>|<esp>|<ucd>"
# on success; non-zero return on failure (caller keeps the slice OFF).
# COMPILE_INTONATIONS=OFF: data ships as a Flutter asset, so we never run
# the iOS binary. MACOSX_BUNDLE=OFF: otherwise CMake treats espeak-ng-bin
# as an app bundle and its install() rule fails to configure under iOS.
espeak_build_slice() {
  local sdk="$1" bdir="$2"
  local sysroot; sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)" || return 1
  local build="${ESPEAK_SRC}/${bdir}"
  cmake -S "$ESPEAK_SRC" -B "$build" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sysroot" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_MIN_OS_VERSION" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_MACOSX_BUNDLE=OFF \
    -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DUSE_ASYNC=OFF -DUSE_MBROLA=OFF -DUSE_KLATT=OFF \
    -DUSE_LIBPCAUDIO=OFF -DUSE_LIBSONIC=OFF \
    -DCOMPILE_INTONATIONS=OFF -DESPEAK_COMPAT=OFF -DENABLE_TESTS=OFF \
    >&2 || return 1
  cmake --build "$build" --target espeak-ng --config Release >&2 || return 1
  local esp ucd
  esp="$(find "$build" -name libespeak-ng.a | head -1)"
  ucd="$(find "$build" -name libucd.a | head -1)"
  [[ -f "$esp" && -f "$ucd" ]] || return 1
  echo "${ESPEAK_SRC}/src/include|${esp}|${ucd}"
}

# Native (host macOS) build → generate espeak-ng-data + stage it as the
# Flutter asset (replacing the repo placeholder) so libespeak-ng finds
# its phoneme tables at runtime. Echoes the asset path on success.
espeak_stage_data() {
  local build="${ESPEAK_SRC}/build-native"
  cmake -S "$ESPEAK_SRC" -B "$build" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_MACOSX_BUNDLE=OFF \
    -DBUILD_SHARED_LIBS=OFF -DESPEAK_COMPAT=OFF \
    -DUSE_ASYNC=OFF -DUSE_MBROLA=OFF -DUSE_KLATT=OFF \
    -DUSE_LIBPCAUDIO=OFF -DUSE_LIBSONIC=OFF -DENABLE_TESTS=OFF >&2 || return 1
  cmake --build "$build" --parallel --target espeak-ng-bin >&2 || return 1
  cmake --build "$build" --parallel --target data >&2 || return 1
  local data; data="$(find "$build" -type d -name espeak-ng-data | head -1)"
  [[ -d "$data" && -f "$data/phontab" && -f "$data/phondata" ]] || return 1
  local asset="${REPO_ROOT}/assets/espeak-ng-data.tar.gz"
  tar -C "$data" -czf "$asset" . >&2 || return 1
  echo "$asset"
}

if [[ "$ESPEAK_NG" == "1" || "$ESPEAK_NG" == "ON" ]]; then
  echo "==> ESPEAK_NG=$ESPEAK_NG — cross-building libespeak-ng for iOS (kokoro phonemizer)"
  # Neutralise pkg-config's espeak-ng lookup for the CrispASR iOS
  # configures below. CrispASR's kokoro cmake tries pkg_check_modules
  # FIRST — on a Mac with Homebrew's espeak-ng that resolves to the
  # *macOS* lib and would be linked into the iOS slice, breaking the
  # arm64 link (the original reason espeak was forced OFF here). With
  # pkg-config pointed at an empty dir the snippet falls through to its
  # find_path/find_library branch, which honours the
  # -DESPEAK_NG_INCLUDE_DIR / -DESPEAK_NG_LIBRARY we pass per slice.
  # BLAS on Apple uses the Accelerate framework (not pkg-config), so the
  # rest of the build is unaffected. Only matters when espeak is ON.
  export PKG_CONFIG_LIBDIR="$(mktemp -d)"
  export PKG_CONFIG_PATH=""
  if espeak_clone; then
    if out=$(espeak_build_slice iphonesimulator build-ios-sim); then
      ESPEAK_ARGS_SIM=(-DCRISPASR_WITH_ESPEAK_NG=ON \
        -DESPEAK_NG_INCLUDE_DIR="${out%%|*}" \
        -DESPEAK_NG_LIBRARY="$(echo "$out" | cut -d'|' -f2)")
      ESPEAK_LIBS_SIM="$(echo "$out" | cut -d'|' -f2) $(echo "$out" | cut -d'|' -f3)"
      echo "    simulator slice: espeak ON"
    else
      echo "::warning:: espeak-ng iOS-sim build failed — kokoro stays popen-only (simulator)" >&2
    fi
    if out=$(espeak_build_slice iphoneos build-ios-device); then
      ESPEAK_ARGS_DEVICE=(-DCRISPASR_WITH_ESPEAK_NG=ON \
        -DESPEAK_NG_INCLUDE_DIR="${out%%|*}" \
        -DESPEAK_NG_LIBRARY="$(echo "$out" | cut -d'|' -f2)")
      ESPEAK_LIBS_DEVICE="$(echo "$out" | cut -d'|' -f2) $(echo "$out" | cut -d'|' -f3)"
      echo "    device slice: espeak ON"
    else
      echo "::warning:: espeak-ng iOS-device build failed — kokoro stays popen-only (device)" >&2
    fi
    if asset=$(espeak_stage_data); then
      echo "    staged espeak-ng-data asset: $asset ($(du -h "$asset" | cut -f1))"
      echo "    NOTE: this overwrote the repo's placeholder asset — do NOT commit it."
    else
      echo "::warning:: espeak-ng-data staging failed — kokoro will lack phoneme tables at runtime" >&2
    fi
  else
    echo "::warning:: espeak-ng clone failed — building without the in-process phonemizer" >&2
  fi
fi

# ---- Build iOS simulator slice (arm64, since Apple Silicon Mac) ----
echo "==> cmake configure: iOS simulator"
cmake -B build-ios-sim -G Xcode \
  "${COMMON_CMAKE_ARGS[@]}" \
  -DIOS=ON \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_ARCHITECTURES="arm64" \
  -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS=iphonesimulator \
  -DCMAKE_C_FLAGS="$COMMON_C_FLAGS" \
  -DCMAKE_CXX_FLAGS="$COMMON_CXX_FLAGS" \
  -DCRISPASR_COREML="$EFFECTIVE_COREML" \
  -DCRISPASR_COREML_ALLOW_FALLBACK=ON \
  "${ESPEAK_ARGS_SIM[@]}" \
  -S .
echo "==> cmake build: iOS simulator"
cmake --build build-ios-sim --config Release -- -quiet

# ---- Build iOS device slice (arm64) ----
echo "==> cmake configure: iOS device"
cmake -B build-ios-device -G Xcode \
  "${COMMON_CMAKE_ARGS[@]}" \
  -DIOS=ON \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES="arm64" \
  -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS=iphoneos \
  -DCMAKE_C_FLAGS="$COMMON_C_FLAGS" \
  -DCMAKE_CXX_FLAGS="$COMMON_CXX_FLAGS" \
  -DCRISPASR_COREML="$EFFECTIVE_COREML" \
  -DCRISPASR_COREML_ALLOW_FALLBACK=ON \
  "${ESPEAK_ARGS_DEVICE[@]}" \
  -S .
echo "==> cmake build: iOS device"
cmake --build build-ios-device --config Release -- -quiet

# ---- Wrap each slice into a crispasr.framework bundle ----
# Mirrors setup_framework_structure() and combine_static_libraries()
# from CrispASR/build-xcframework.sh, restricted to iOS.
setup_framework() {
  local build_dir="$1"
  local plat_dir="${CRISPASR_DIR}/${build_dir}"
  local fw="${plat_dir}/framework/crispasr.framework"
  rm -rf "$fw"
  mkdir -p "$fw/Headers" "$fw/Modules"

  cp include/crispasr.h          "$fw/Headers/"
  cp ggml/include/ggml.h         "$fw/Headers/"
  cp ggml/include/ggml-alloc.h   "$fw/Headers/"
  cp ggml/include/ggml-backend.h "$fw/Headers/"
  cp ggml/include/ggml-metal.h   "$fw/Headers/"
  cp ggml/include/ggml-cpu.h     "$fw/Headers/"
  cp ggml/include/ggml-blas.h    "$fw/Headers/"
  cp ggml/include/gguf.h         "$fw/Headers/"

  cat > "$fw/Modules/module.modulemap" <<EOF
framework module crispasr {
    header "crispasr.h"
    header "ggml.h"
    header "ggml-alloc.h"
    header "ggml-backend.h"
    header "ggml-metal.h"
    header "ggml-cpu.h"
    header "ggml-blas.h"
    header "gguf.h"

    link "c++"
    link framework "Accelerate"
    link framework "Metal"
    link framework "Foundation"
    link framework "AudioToolbox"

    export *
}
EOF

  cat > "$fw/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>crispasr</string>
    <key>CFBundleIdentifier</key><string>org.ggml.crispasr</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>crispasr</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>MinimumOSVersion</key><string>${IOS_MIN_OS_VERSION}</string>
    <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
    <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
    <key>DTPlatformName</key><string>iphoneos</string>
    <key>DTSDKName</key><string>iphoneos${IOS_MIN_OS_VERSION}</string>
</dict>
</plist>
EOF
}

combine() {
  local build_dir="$1"        # build-ios-sim or build-ios-device
  local release_dir="$2"      # Release-iphonesimulator or Release-iphoneos
  local sdk="$3"              # iphonesimulator or iphoneos
  local archs="$4"            # arm64 (or arm64+x86_64 for sim, but we kept sim arm64 only)
  local min_flag="$5"         # -mios-version-min=… or -mios-simulator-version-min=…
  local extra_libs="${6:-}"   # space-separated static libs to also force_load
                              # (libespeak-ng.a + libucd.a when ESPEAK_NG=1)
  local plat_dir="${CRISPASR_DIR}/${build_dir}"
  local fw="${plat_dir}/framework/crispasr.framework"
  local out_lib="${fw}/crispasr"

  # CrispASR's main libcrispasr.a calls into ~30 per-backend static
  # libs (libparakeet.a, libvoxtral.a, libkokoro.a, …). With
  # BUILD_SHARED_LIBS=OFF those backends aren't transitively pulled
  # into libcrispasr.a — the shared-lib link step would normally pull
  # them via target_link_libraries, but for a static archive we have
  # to list them all explicitly. Glob `src/${release_dir}/lib*.a` to
  # pick up every backend without hardcoding the list. The CrispASR
  # build-xcframework.sh upstream only enumerates libcrispasr+ggml*,
  # which is why the iOS link there fails on the same symbols if you
  # try it standalone — this is the working fix.
  local libs=(
    "${plat_dir}/ggml/src/${release_dir}/libggml.a"
    "${plat_dir}/ggml/src/${release_dir}/libggml-base.a"
    "${plat_dir}/ggml/src/${release_dir}/libggml-cpu.a"
    "${plat_dir}/ggml/src/ggml-metal/${release_dir}/libggml-metal.a"
    "${plat_dir}/ggml/src/ggml-blas/${release_dir}/libggml-blas.a"
  )
  # Recurse into the entire build tree to find ALL static libs. The Xcode
  # generator (-G Xcode) places per-target .a files in deep nested paths
  # like src/crispasr.build/Release-iphoneos/<target>.build/... rather
  # than flat under src/Release-iphoneos/. A broad find catches everything
  # regardless of generator layout.
  echo "    scanning ${plat_dir} for lib*.a ..."
  while IFS= read -r -d '' lib; do
    libs+=("$lib")
  done < <(find "${plat_dir}" -name 'lib*.a' -not -path '*/temp/*' -not -path '*/dedup/*' -print0 2>/dev/null)
  echo "    found ${#libs[@]} static libraries"
  # crisp_audio is its own subdir (not under src/). qwen3_asr +
  # voxtral both call into it via crisp_audio_compute_mel etc.
  if [[ -f "${plat_dir}/crisp_audio/${release_dir}/libcrisp_audio.a" ]]; then
    libs+=("${plat_dir}/crisp_audio/${release_dir}/libcrisp_audio.a")
  fi
  # The broad find above already covers crisp_punc/, crisp_lid/, and
  # any other cmake subdirectories.
  # espeak-ng + ucd (when ESPEAK_NG=1): kokoro.a was compiled with
  # CRISPASR_HAVE_ESPEAK_NG=1 and now references espeak_* / ucd_* symbols.
  # Force-load both so they resolve in the framework. Built for the slice
  # that matches $sdk, so device gets the iphoneos libs and sim the
  # iphonesimulator ones — no arch mixing.
  for el in $extra_libs; do
    [[ -f "$el" ]] && libs+=("$el")
  done

  local temp_dir="${plat_dir}/temp"
  rm -rf "$temp_dir"
  mkdir -p "$temp_dir"

  # Extract .o files from each static lib into per-lib subdirs, then
  # dedup. Two constraints:
  #  1. Same-named .o from DIFFERENT libs (e.g. nemotron.o from
  #     libnemotron.a vs libcrispasr-llama-core.a) must BOTH be kept
  #     — they define different symbols.
  #  2. Same-named .o from libs that re-export the SAME symbols (e.g.
  #     ggml symbols appearing in libggml.a and libggml-base.a) must
  #     be deduped to avoid duplicate-symbol link errors.
  #
  # Strategy: extract into per-lib dirs (prefix avoids cross-lib
  # collision), then dedup by file content hash so only truly identical
  # .o files collapse. Different .o files with the same basename from
  # different libs survive.
  local extract_dir="${temp_dir}/extract"
  mkdir -p "$extract_dir"
  local i=0
  for lib in "${libs[@]}"; do
    [[ -f "$lib" ]] || continue
    local sub="$extract_dir/$(printf '%03d' $i)_$(basename "$lib" .a)"
    mkdir -p "$sub"
    (cd "$sub" && ar -x "$lib") 2>/dev/null
    i=$((i+1))
  done

  local dedup_dir="${temp_dir}/dedup"
  mkdir -p "$dedup_dir"
  # Dedup by content hash: rename each .o to <lib-prefix>__<basename>
  # so cross-lib files never collide, then skip files whose md5
  # matches one already copied (catches ggml duplicates that appear
  # in multiple archives with the same content).
  local seen_file="${temp_dir}/seen_hashes.txt"
  : > "$seen_file"
  while IFS= read -r obj; do
    local subdir_name
    subdir_name="$(basename "$(dirname "$obj")")"
    local prefixed="${subdir_name}__$(basename "$obj")"
    local hash
    hash="$(md5 -q "$obj" 2>/dev/null || md5sum "$obj" 2>/dev/null | cut -d' ' -f1)" || hash="$prefixed"
    if ! grep -qxF "$hash" "$seen_file" 2>/dev/null; then
      echo "$hash" >> "$seen_file"
      cp "$obj" "$dedup_dir/$prefixed"
    fi
  done < <(find "$extract_dir" -name "*.o" -print | sort)

  ar -rcs "${temp_dir}/combined.a" "$dedup_dir"/*.o 2>/dev/null
  rm -rf "$extract_dir" "$dedup_dir"

  local arch_flags=""
  for a in $archs; do arch_flags+=" -arch $a"; done

  local frameworks="-framework Foundation -framework Metal -framework Accelerate -framework AudioToolbox"
  if [[ "$EFFECTIVE_COREML" == "ON" ]]; then
    frameworks+=" -framework CoreML"
  fi

  echo "==> linking ${build_dir} → crispasr.framework/crispasr"
  xcrun -sdk "$sdk" clang++ -dynamiclib \
    -isysroot "$(xcrun --sdk $sdk --show-sdk-path)" \
    $arch_flags \
    $min_flag \
    -Wl,-force_load,"${temp_dir}/combined.a" \
    $frameworks \
    -install_name "@rpath/crispasr.framework/crispasr" \
    -o "$out_lib"

  # iOS device builds need vtool to mark the binary as a framework
  # binary so App Store validation accepts it.
  if [[ "$sdk" == "iphoneos" ]] && command -v xcrun >/dev/null && xcrun vtool 2>/dev/null; then
    xcrun vtool -set-build-version ios "$IOS_MIN_OS_VERSION" "$IOS_MIN_OS_VERSION" -replace \
      -output "$out_lib" "$out_lib" 2>/dev/null || true
  fi

  # Generate dSYM next to the framework, then strip the in-framework
  # copy so the binary inside the .framework is small.
  mkdir -p "${plat_dir}/dSYMs"
  xcrun dsymutil "$out_lib" -o "${plat_dir}/dSYMs/crispasr.dSYM" 2>/dev/null
  xcrun strip -S "$out_lib" -o "${temp_dir}/stripped" 2>/dev/null && \
    mv "${temp_dir}/stripped" "$out_lib"

  rm -rf "$temp_dir"
}

echo "==> framework setup: simulator"
setup_framework "build-ios-sim"
combine "build-ios-sim" "Release-iphonesimulator" "iphonesimulator" "arm64" \
  "-mios-simulator-version-min=$IOS_MIN_OS_VERSION" "$ESPEAK_LIBS_SIM"

echo "==> framework setup: device"
setup_framework "build-ios-device"
combine "build-ios-device" "Release-iphoneos" "iphoneos" "arm64" \
  "-mios-version-min=$IOS_MIN_OS_VERSION" "$ESPEAK_LIBS_DEVICE"

# ---- xcframework with both slices ----
mkdir -p build-apple
rm -rf build-apple/crispasr.xcframework
echo "==> xcodebuild -create-xcframework"
xcodebuild -create-xcframework \
  -framework "${CRISPASR_DIR}/build-ios-sim/framework/crispasr.framework" \
  -debug-symbols "${CRISPASR_DIR}/build-ios-sim/dSYMs/crispasr.dSYM" \
  -framework "${CRISPASR_DIR}/build-ios-device/framework/crispasr.framework" \
  -debug-symbols "${CRISPASR_DIR}/build-ios-device/dSYMs/crispasr.dSYM" \
  -output "${CRISPASR_DIR}/build-apple/crispasr.xcframework"

# ---- Mirror into CrisperWeaver/ios/Frameworks/ for the wiring step ----
DEST="$REPO_ROOT/ios/Frameworks/crispasr.xcframework"
mkdir -p "$REPO_ROOT/ios/Frameworks"
rm -rf "$DEST"
cp -R "${CRISPASR_DIR}/build-apple/crispasr.xcframework" "$DEST"

echo
echo "==> done"
echo "    xcframework: $DEST"
echo "    next: scripts/wire_ios_xcframework.rb (adds it to Runner.xcodeproj"
echo "          with Embed & Sign), then flutter build ios"
