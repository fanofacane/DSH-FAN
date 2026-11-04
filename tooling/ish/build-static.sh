#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Static iSH build for DSHRuntime. No upstream source is modified.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ISH_BUILD_DIR="${ISH_BUILD_DIR:-$REPO_DIR/apple/.build/ish}"
ISH_SOURCE_DIR="${ISH_UPSTREAM_DIR:-${ISH_SOURCE_DIR:-$ISH_BUILD_DIR/sources/ish-arm64}}"
ISH_REV=c5c264da19148512167aa493d7bd4e50aae1b74e
ISH_SDK="${1:-iphonesimulator}"
# true enables the upstream AOT-capable runtime, with runtime code emission
# disabled below. No AOT images are built or bundled by this runtime.
ISH_JIT="${ISH_JIT:-false}"
case "$ISH_SDK" in
  iphoneos) target=arm64-apple-ios16.0 ;;
  iphonesimulator) target=arm64-apple-ios16.0-simulator ;;
  *) echo 'usage: build-kernel.sh [iphoneos|iphonesimulator]' >&2; exit 2 ;;
esac
for tool in meson ninja cmake python3; do command -v "$tool" >/dev/null; done
mkdir -p "$ISH_BUILD_DIR"
if [[ ! -d "$ISH_SOURCE_DIR/.git" ]]; then
  git clone --no-checkout https://github.com/OpenMinis/ish-arm64.git "$ISH_SOURCE_DIR"
  git -C "$ISH_SOURCE_DIR" checkout --detach "$ISH_REV"
fi
[[ "$(git -C "$ISH_SOURCE_DIR" rev-parse HEAD)" == "$ISH_REV" ]] || {
  echo "Expected ish-arm64 $ISH_REV; refusing another revision" >&2; exit 1;
}
git -C "$ISH_SOURCE_DIR" submodule update --init --depth 1 deps/libarchive
# Keep the external clone clean. Only the isolated, hash-verified export is
# compiled. Xcode must use this export for headers and the fakefs helper.
ISH_SOURCE_DIR="$(python3 "$REPO_DIR/tooling/ish/prepare-source.py" "$ISH_SOURCE_DIR" \
  "$ISH_BUILD_DIR/sources/ish-patched")"
sdk_path="$(xcrun --sdk "$ISH_SDK" --show-sdk-path)"
apple_clang="$(xcrun --find clang)"
cross="$ISH_BUILD_DIR/$ISH_SDK.ini"
cat > "$cross" <<EOF
[binaries]
c = ['$apple_clang', '-target', '$target', '-isysroot', '$sdk_path']
ar = '/usr/bin/ar'
strip = '/usr/bin/strip'
pkg-config = '/usr/bin/false'
[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
needs_exe_wrapper = true
EOF
# Meson finds `clang` on PATH for the Linux VDSO, independently of the Apple
# cross compiler above. Use LLVM+lld, or the Zig wrapper below. No source patch.
if [[ "${ISH_VDSO_COMPILER:-}" == zig ]]; then
  mkdir -p "$ISH_BUILD_DIR/vdso-bin"
  cat > "$ISH_BUILD_DIR/vdso-bin/clang" <<EOF
#!/bin/sh
exec "$(command -v python3)" -m ziglang cc "\$@"
EOF
  chmod +x "$ISH_BUILD_DIR/vdso-bin/clang"
  export PATH="$ISH_BUILD_DIR/vdso-bin:$PATH"
fi
kernel="$ISH_BUILD_DIR/ish-$ISH_SDK"
if [[ ! -f "$kernel/build.ninja" ]]; then
  meson setup "$kernel" "$ISH_SOURCE_DIR" --cross-file "$cross" \
    --buildtype release -Db_ndebug=true -Dguest_arch=arm64 -Dkernel=ish \
    -Dengine=asbestos -Djit="$ISH_JIT" -Djit_emit=false -Dlog_handler=nslog
else
  meson configure "$kernel" -Djit="$ISH_JIT" -Djit_emit=false
fi
ninja -C "$kernel" libish.a libish_emu.a libfakefs.a
file "$kernel/vdso/arm64/libvdso.so.elf" | tee "$ISH_BUILD_DIR/vdso-$ISH_SDK.txt"
grep -q 'ELF 64-bit.*ARM aarch64' "$ISH_BUILD_DIR/vdso-$ISH_SDK.txt"

# Build the pinned iSH libarchive submodule for on-device fakefs_import.
# XZ uses the public liblzma stub supplied by the iOS SDK. Only the matching
# public C headers are needed from the pinned upstream (no host SDK headers).
xz_source="$ISH_BUILD_DIR/sources/xz"
xz_revision=3d078b52adbff566ccfc51067dfbf742ecf3ef86
if [[ ! -d "$xz_source/.git" ]]; then
  git clone --depth 1 --branch v5.8.2 https://github.com/tukaani-project/xz.git "$xz_source"
fi
[[ "$(git -C "$xz_source" rev-parse HEAD)" == "$xz_revision" ]]
[[ -z "$(git -C "$xz_source" status --porcelain)" ]]
cmake -S "$ISH_SOURCE_DIR/deps/libarchive" -B "$ISH_BUILD_DIR/archive-$ISH_SDK" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk_path" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DENABLE_TEST=OFF -DENABLE_INSTALL=OFF -DENABLE_TAR=OFF -DENABLE_CPIO=OFF \
  -DENABLE_CAT=OFF -DENABLE_UNZIP=OFF -DENABLE_OPENSSL=OFF -DENABLE_MBEDTLS=OFF \
  -DENABLE_NETTLE=OFF -DENABLE_LIBB2=OFF -DENABLE_LZ4=OFF -DENABLE_LZMA=ON \
  -DLIBLZMA_INCLUDE_DIR="$xz_source/src/liblzma/api" \
  -DLIBLZMA_LIBRARY="$sdk_path/usr/lib/liblzma.tbd" \
  -DENABLE_ZSTD=OFF -DENABLE_BZip2=OFF -DENABLE_LIBXML2=OFF -DENABLE_EXPAT=OFF
cmake --build "$ISH_BUILD_DIR/archive-$ISH_SDK" --target archive_static --parallel 4
echo "Built shared iSH libraries for $ISH_SDK."
