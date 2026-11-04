#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Reproducible arm64 device + simulator framework, using the runtime/ios/patches chain.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export ISH_BUILD_DIR="${ISH_BUILD_DIR:-$REPO_DIR/apple/.build/ish}"
output="$REPO_DIR/apple/Vendor/ish/ish.xcframework"
for sdk in iphoneos iphonesimulator; do
  bash "$REPO_DIR/tooling/ish/build-static.sh" "$sdk"
  source_dir="$ISH_BUILD_DIR/sources/ish-patched"
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  target=arm64-apple-ios16.0
  [[ "$sdk" != iphonesimulator ]] || target="$target-simulator"
  flags=(-target "$target" -isysroot "$sdk_path" -O2 -DNDEBUG -DGUEST_ARM64=1
    -DENGINE_ASBESTOS=1 -DLOG_HANDLER_NSLOG=1 -I"$source_dir"
    -I"$source_dir/deps/libarchive/libarchive" -I"$ISH_BUILD_DIR/ish-$sdk")
  xcrun clang "${flags[@]}" -c "$source_dir/tools/fakefs.c" -o "$ISH_BUILD_DIR/fakefs-import-$sdk.o"
  xcrun clang "${flags[@]}" -fobjc-arc -fblocks -c "$REPO_DIR/apple/Modules/DSHRuntime/Native/ISHRuntime.m" \
    -o "$ISH_BUILD_DIR/runtime-$sdk.o"
  framework="$ISH_BUILD_DIR/$sdk/ish.framework"
  mkdir -p "$framework/Headers" "$framework/Modules"
  xcrun libtool -static -o "$framework/ish" \
    "$ISH_BUILD_DIR/ish-$sdk/libish.a" "$ISH_BUILD_DIR/ish-$sdk/libish_emu.a" \
    "$ISH_BUILD_DIR/ish-$sdk/libfakefs.a" "$ISH_BUILD_DIR/archive-$sdk/libarchive/libarchive.a" \
    "$ISH_BUILD_DIR/fakefs-import-$sdk.o" "$ISH_BUILD_DIR/runtime-$sdk.o"
  cp "$REPO_DIR/apple/Modules/DSHRuntime/Native/ISHRuntime.h" "$framework/Headers/ish.h"
  cat > "$framework/Modules/module.modulemap" <<'MODULE'
framework module ish {
  umbrella header "ish.h"
  export *
  module * { export * }
}
MODULE
  python3 - "$framework/Info.plist" "$sdk" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='io.github.fanofacane.dshfan.ish',
        CFBundleName='ish', CFBundleExecutable='ish', CFBundlePackageType='FMWK',
        CFBundleVersion='1', CFBundleShortVersionString='1.0', MinimumOSVersion='16.0',
        CFBundleSupportedPlatforms=['iPhoneOS' if sys.argv[2] == 'iphoneos' else 'iPhoneSimulator']), f)
PY
done
mkdir -p "$(dirname "$output")"
# Only this generated framework output is replaced.
rm -rf "$output"
xcodebuild -create-xcframework \
  -framework "$ISH_BUILD_DIR/iphoneos/ish.framework" \
  -framework "$ISH_BUILD_DIR/iphonesimulator/ish.framework" -output "$output"
echo "Built $output (not committed)"
