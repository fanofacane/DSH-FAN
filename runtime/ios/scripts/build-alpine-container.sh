#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
set -eu
test "$(uname -sm)" = 'Linux aarch64'
test -f /.dockerenv
test -d /out
ios=/repo/runtime/ios
mkdir -p /out/apk-cache /opt/dsh /opt/dsh-fan /etc/dsh-app /root/.dsh /dev/pts /tmp
apk verify /out/nodejs-22.23.2-r0.apk /out/nodejs-dev-22.23.2-r0.apk /out/nodejs-libs-22.23.2-r0.apk /out/tzdata-2026e-r0.apk
apk --cache-dir /out/apk-cache --update-cache add \
  /out/nodejs-22.23.2-r0.apk nodejs=22.23.2-r0 npm \
  /out/tzdata-2026e-r0.apk tzdata=2026e-r0 \
  bash ca-certificates libstdc++ libgcc libffi git curl
test "$(apk info -v -e tzdata)" = tzdata-2026e-r0
apk --cache-dir /out/apk-cache --update-cache add --virtual .probe-build-deps \
  /out/nodejs-dev-22.23.2-r0.apk nodejs-dev=22.23.2-r0 \
  /out/nodejs-libs-22.23.2-r0.apk nodejs-libs=22.23.2-r0 \
  build-base python3 linux-headers libffi-dev cmake ninja binutils
node --version | grep '^v22\.23\.2$'
node_root=/usr
if [ "$IOS_NODE_MAJOR" = 24 ]; then
  mkdir -p /opt/node
  tar -xJf /out/node-musl.tar.xz -C /opt/node --strip-components=1
  export PATH=/opt/node/bin:$PATH
  node_root=/opt/node
  node --version | grep '^v24\.22\.1$'
fi
cc -std=c11 -O2 -Wall -Wextra -Werror -fPIC -shared "$ios/guest/zero_free.c" -ldl -pthread -o /lib/zero_free.so
cc -O2 -fPIC -shared "$ios/guest/zero_free_observer.c" -ldl -o /tmp/zero_free_observer.so
cc -O2 -fno-builtin "$ios/guest/zero_free_test.c" -ldl -pthread -o /tmp/zero_free_test
LD_PRELOAD=/lib/zero_free.so:/tmp/zero_free_observer.so /tmp/zero_free_test
# Functional checks run outside the payload in production builds.
cp "$ios/guest/native-modules.cjs" /out/
if [ "${RUNTIME_FLAVOR:-probe}" = probe ]; then
  mkdir -p /opt/runtime-probe
  cp "$ios/guest/native-modules.cjs" /opt/runtime-probe/
fi
cp "$ios/guest/wasm-polyfill.js" "$ios/guest/fetch-polyfill.js" /lib/
cp /repo/runtime/locks/dsh-0.2.1-rc.4/package.json /repo/runtime/locks/dsh-0.2.1-rc.4/package-lock.json /opt/dsh/
npm --prefix /opt/dsh ci --ignore-scripts --os=linux --cpu=arm64 --libc=musl \
  --cache=/out/npm-cache --include=optional --no-audit --no-fund --registry=https://registry.npmmirror.com
# Skip the glibc ELF before its loader can abort rather than falling back.
rm -f /opt/dsh/node_modules/@koromix/koffi-linux-arm64/linux_arm64/koffi.node
set +e
npm --prefix /opt/dsh rebuild node-pty koffi --build-from-source --nodedir="$node_root" --foreground-scripts
build_result=$?
echo "Linux node-pty/koffi native-rebuild exit=$build_result" | tee /out/native-build-status.txt
test "$build_result" = 0 || exit 1
set -e
# cnoke's install --prebuild ignores npm_config_build_from_source when a
# usable optional binary exists. Call the source builder without --prebuild.
(cd /opt/dsh/node_modules/koffi && node ./cnoke.cjs -P . -D src/koffi --release --verbose)
echo 'Linux koffi explicit-source-build exit=0' >> /out/native-build-status.txt
# Sharp 0.35 has no install lifecycle build; invoke its published build script.
# Headers/node-gyp are build-only, outside the DSH tree and its original lock.
npm --prefix /out/sharp-build-tools install --ignore-scripts --save-exact \
  node-gyp@12.4.0 @img/sharp-libvips-dev@1.3.4 \
  --cache=/out/npm-cache --no-audit --no-fund --registry=https://registry.npmmirror.com
set +e
# Alpine Node 22's common.gypi appends LTO flags after user flags. A
# build-only compiler adapter appends the final -fno-lto for both compilation
# and linking, avoiding GCC/fortify vsnprintf inline failures. No source edits.
cat > /tmp/probe-sharp-cxx <<'CXX'
#!/bin/sh
exec g++ "$@" -fno-lto
CXX
chmod +x /tmp/probe-sharp-cxx
CXX=/tmp/probe-sharp-cxx \
  NODE_PATH=/out/sharp-build-tools/node_modules npm_config_nodedir="$node_root" \
  npm --prefix /opt/dsh/node_modules/sharp run build
build_result=$?
echo "Linux sharp source-build exit=$build_result" | tee -a /out/native-build-status.txt
test "$build_result" = 0 || exit 1
set -e
# Existing reviewed DSH patches only; no Node-22 compatibility edits or new pins.
python3 -I /repo/runtime/lib/rtbuild.py patch-dsh --prefix /opt/dsh --dsh-version 0.2.1-rc.4
if [ "${RUNTIME_FLAVOR:-probe}" = production ]; then
  mkdir -p /opt/pnpm
  cp /repo/runtime/locks/pnpm-11.28.5/package*.json /opt/pnpm/
  npm --prefix /opt/pnpm ci --ignore-scripts --cache=/out/npm-cache --no-audit --no-fund --registry=https://registry.npmmirror.com
  ln -s /opt/pnpm/node_modules/pnpm/bin/pnpm.cjs /usr/local/bin/pnpm
fi
cp -a /repo/runtime/bridge/dsh-fan-bridge /opt/dsh-fan/dsh-fan-bridge
cat > /etc/dsh-app/dsh-web.patch.yml <<'YAML'
- insert:
    - id: dsh-fan-bridge
      name: /opt/dsh-fan/dsh-fan-bridge/lib/index.js
YAML
ln -sf "$node_root/bin/node" /usr/local/bin/node
if [ "${RUNTIME_FLAVOR:-probe}" = production ]; then
  # Same rescue overlay/profile as Android SafeMode.kt. No user plugins/HMR.
  cat > /etc/dsh-app/safe.patch.yml <<'YAML'
- id: plugin-manager
  disabled: true
- id: tool-plugin-manager
  disabled: true
- id: hmr
  disabled: true
YAML
fi
cat > /usr/local/bin/dsh <<'SH'
#!/bin/sh
exec node /opt/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js "$@"
SH
chmod +x /usr/local/bin/dsh
readelf -n "$node_root/bin/node" | sed -n 's/.*Build ID: //p' > /out/node-build-id.txt
# Export only built payload. Package metadata/libc come from a fresh runtime
# container, never by replacing libc behind apk's installed database.
cp /tmp/zero_free_test /tmp/zero_free_observer.so /out/
tar -czf /out/payload.tar.gz -C / ./opt ./etc/dsh-app \
  ./usr/local/bin ./lib/zero_free.so \
  ./lib/wasm-polyfill.js ./lib/fetch-polyfill.js
