#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Production Alpine payload; build inputs live under runtime/ios/.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$HERE/.." && pwd)"
export ALPINE_BUILD_DIR="${IOS_BUILD_DIR:-$HERE/.work/ios-arm64}"
export IOS_NODE_MAJOR=24 RUNTIME_FLAVOR=production
mkdir -p "$ALPINE_BUILD_DIR"
bash "$REPO_DIR/runtime/ios/scripts/prepare-alpine.sh"
python3 -I - "$REPO_DIR" "$ALPINE_BUILD_DIR" "${RUNTIME_OUT:-$HERE/out}" <<'PY'
import hashlib, json, shutil, sys, tarfile
from pathlib import Path
repo, work, out = map(Path, sys.argv[1:])
assets = out / 'ios-arm64/assets/runtime'
assets.mkdir(parents=True, exist_ok=True)
archive = work / 'rootfs-ios-arm64.tar.xz'
inputs = [repo / x for x in [
    'runtime/build-ios-runtime.sh', 'runtime/lib/rtbuild.py',
    'runtime/patches/pins.json', 'runtime/locks/dsh-0.2.1-rc.4/package-lock.json',
    'runtime/locks/pnpm-11.28.5/package-lock.json',
    'runtime/ios/scripts/prepare-alpine.sh',
    'runtime/ios/scripts/build-alpine-container.sh',
    'runtime/ios/scripts/pack-alpine-container.sh',
    'runtime/ios/guest/zero_free.c',
    'runtime/ios/guest/wasm-polyfill.js',
    'runtime/ios/guest/fetch-polyfill.js',
]]
inputs += sorted((repo / 'runtime/patches').glob('*.diff'))
inputs += sorted(p for p in (repo / 'runtime/bridge/dsh-fan-bridge').rglob('*') if p.is_file())
inputs_hash = hashlib.sha256(b''.join(p.read_bytes() for p in inputs)).hexdigest()
with tarfile.open(archive) as tar:
    entries = tar.getmembers()
    names = {m.name.removeprefix('./') for m in entries}
    forbidden = ('opt/runtime-probe', 'memory-credentials.mjs', 'engine.patch.yml', 'oracle')
    if any(any(x in name for x in forbidden) for name in names):
        raise SystemExit('probe-only file found in production rootfs')
    for name in ('opt/node/bin/node', 'lib/zero_free.so', 'lib/wasm-polyfill.js',
                 'lib/fetch-polyfill.js', 'opt/dsh-fan/dsh-fan-bridge/lib/index.js',
                 'usr/share/zoneinfo/Asia/Shanghai', 'usr/share/zoneinfo/America/Los_Angeles'):
        if name not in names:
            raise SystemExit('missing production file: ' + name)
    uncompressed = sum(m.size for m in entries if m.isfile())
manifest = dict(schema=1, abi='ios-arm64',
    runtimeVersion='ios-r1-dsh0.2.1-rc.4-node24.22.1-alpine3.21-' + inputs_hash[:12],
    dshVersion='0.2.1-rc.4', nodeVersion='24.22.1', alpineVersion='3.21.0',
    pnpmVersion='11.28.5', tzdataVersion='2026e-r0', rootfs=archive.name,
    rootfsSha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
    rootfsBytes=archive.stat().st_size, uncompressedBytes=uncompressed, entries=len(entries),
    buildInputsSha256=inputs_hash, jniLibs={},
    launch=dict(argv=['/usr/local/bin/dsh', 'web', '--host', '127.0.0.1',
        '--port', '3080', '--no-open', '--patch', '/etc/dsh-app/dsh-web.patch.yml']))
shutil.copy2(archive, assets / archive.name)
(assets / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
shutil.copy2(work / 'provenance.json', assets / 'provenance.json')
print(json.dumps({k: manifest[k] for k in ('runtimeVersion', 'rootfsBytes', 'uncompressedBytes', 'rootfsSha256')}))
PY
