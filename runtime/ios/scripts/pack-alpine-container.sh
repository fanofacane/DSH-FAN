#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Final rootfs deliberately starts from the pinned 3.21.0 base (musl r8).
set -eu
test "$(uname -sm)" = 'Linux aarch64'
test -f /.dockerenv
apk verify /out/nodejs-22.23.2-r0.apk /out/tzdata-2026e-r0.apk
apk --cache-dir /out/apk-cache --update-cache add \
  /out/nodejs-22.23.2-r0.apk nodejs=22.23.2-r0 npm \
  /out/tzdata-2026e-r0.apk tzdata=2026e-r0 \
  bash ca-certificates libstdc++ libgcc libffi git curl
test "$(apk info -v -e tzdata)" = tzdata-2026e-r0
apk info -v -e tzdata > /out/tzdata-version.txt
apk list --installed musl | grep '^musl-1.2.5-r8 '
tar -xzf /out/payload.tar.gz -C /
export PATH=/opt/node/bin:/usr/local/bin:$PATH
# Koffi prefers its optional package over the local source-build directory.
# Install the freshly compiled musl ELF there, preserving its JS loader.
grep -q '^Linux koffi explicit-source-build exit=0$' /out/native-build-status.txt
koffi_built=/opt/dsh/node_modules/koffi/build/koffi/linux_arm64/koffi.node
test -f "$koffi_built"
koffi_target=/opt/dsh/node_modules/@koromix/koffi-linux-arm64/musl_arm64/koffi.node
cp "$koffi_built" "$koffi_target"
sha256sum "$koffi_built" "$koffi_target" > /out/koffi-source-install-sha256.txt
rm -rf /opt/dsh/node_modules/koffi/build
# Install the source-built Sharp addon into its platform package, where the
# upstream relative libvips RPATHs apply. Keep the DSH JS and lock untouched.
sharp_version="$(node -p "require('/opt/dsh/node_modules/sharp/package.json').version")"
sharp_built="/opt/dsh/node_modules/sharp/src/build/Release/sharp-linuxmusl-arm64-$sharp_version.node"
sharp_package="$(node -e "const r=require('module').createRequire('/opt/dsh/package.json'); console.log(require('path').dirname(r.resolve('@img/sharp-linuxmusl-arm64/package')))")"
sharp_target="$sharp_package/lib/sharp-linuxmusl-arm64-$sharp_version.node"
test -f "$sharp_target"
grep -q '^Linux sharp source-build exit=0$' /out/native-build-status.txt
test -s "$sharp_built"
cp "$sharp_built" "$sharp_target"
sha256sum "$sharp_built" "$sharp_target" > /out/sharp-source-install-sha256.txt
rm -rf /opt/dsh/node_modules/sharp/src/build
LD_PRELOAD=/lib/zero_free.so:/out/zero_free_observer.so /out/zero_free_test
set +e
LD_PRELOAD=/lib/zero_free.so node -e 'console.log(1)'
echo "Linux zero_free node-e exit=$?"
dsh --version
echo "Linux baseline dsh-version exit=$?"
native_failures=0
for module in node-pty koffi node:sqlite sharp; do
  LD_PRELOAD=/lib/zero_free.so node /out/native-modules.cjs "$module"
  code=$?
  echo "Linux $module functional exit=$code"
  [ "$code" = 0 ] || native_failures=$((native_failures + 1))
done
test "$native_failures" = 0 || exit 1
LD_PRELOAD=/lib/zero_free.so node -e "const r=require('module').createRequire('/opt/dsh/package.json'); for(const p of ['node-pty','koffi','sharp'])r(p); console.log(JSON.stringify(Object.keys(require.cache).filter(p=>p.endsWith('.node'))))" > /out/loaded-native-paths.json
set -e
grep -q '/@img/sharp-linuxmusl-arm64/lib/.*\.node' /out/loaded-native-paths.json
apk list --installed > /out/alpine-packages.txt
# readelf stays in the build container; use the previously captured build ID.
node --version > /out/node-version.txt
sha256sum /lib/zero_free.so /lib/wasm-polyfill.js /lib/fetch-polyfill.js /lib/ld-musl-aarch64.so.1 \
  /usr/share/zoneinfo/Asia/Shanghai /usr/share/zoneinfo/America/Los_Angeles > /out/runtime-file-sha256.txt
mkdir -p /root/.dsh /dev/pts /tmp /run /media /mnt /srv
if [ "${RUNTIME_FLAVOR:-probe}" = probe ]; then
  : > /tmp/probe-native-http
fi
rm -rf /root/.npm /var/cache/apk/*
if [ "${RUNTIME_FLAVOR:-probe}" = production ]; then
  # No diagnostic scripts, oracles, ephemeral credential providers or overlays.
  test ! -e /opt/runtime-probe
  apk --cache-dir /out/apk-cache add xz
  tar -cJf /out/rootfs-ios-arm64.tar.xz -C / \
    --exclude='./dev/*' --exclude='./proc/*' --exclude='./sys/*' \
    --exclude='./etc/hosts' --exclude='./etc/hostname' --exclude='./etc/resolv.conf' \
    ./bin ./sbin ./lib ./usr ./etc ./opt ./root ./tmp ./var ./dev ./proc ./sys ./run ./media ./mnt ./srv
  sha256sum /out/rootfs-ios-arm64.tar.xz
  exit 0
fi
tar -czf /out/rootfs-B.tar.gz -C / \
  --exclude='./dev/*' --exclude='./proc/*' --exclude='./sys/*' \
  --exclude='./etc/hosts' --exclude='./etc/hostname' --exclude='./etc/resolv.conf' \
  ./bin ./sbin ./lib ./usr ./etc ./opt ./root ./tmp ./var ./dev ./proc ./sys ./run ./media ./mnt ./srv
sha256sum /out/rootfs-B.tar.gz
