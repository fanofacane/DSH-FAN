#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Alpine build recipe; use runtime/build-ios-runtime.sh for the production payload.
set -euo pipefail
IOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$(cd "$IOS_DIR/../.." && pwd)"
IOS_BUILD_DIR="${IOS_BUILD_DIR:-$IOS_DIR/.build}"
IOS_NODE_MAJOR="${IOS_NODE_MAJOR:-22}"
case "$IOS_NODE_MAJOR" in 22|24) ;; *) exit 2 ;; esac
out="${ALPINE_BUILD_DIR:-$IOS_BUILD_DIR/alpine$IOS_NODE_MAJOR}"
mkdir -p "$out"
# The official index has moved to 22.23.4. This mirror retains the original
# signed 3.21 APKs, alongside the pinned timezone database. Both content
# hashes and Alpine signatures are checked (including on cache hits).
for entry in \
  nodejs-22.23.2-r0:fdb52c38ae9e78d21cb3ee748b658c017a558d63344658ba109a656cb3d6b345 \
  nodejs-dev-22.23.2-r0:bfbf028b047e6dfe9213ed88156a528f46ed588776ce64b19197564e817211ae \
  nodejs-libs-22.23.2-r0:c7a722d8219f300e10cbf14a8174d0fa3ca217c704bd030c94106dec5ca2235d \
  tzdata-2026e-r0:42594fb5de44b28620648dbf4917ab1cd913ff58ba6b9045e6c0b9e479793b9a; do
  name="${entry%%:*}.apk"; digest="${entry#*:}"
  [[ -f "$out/$name" ]] || curl -fL --retry 2 --connect-timeout 20 \
    "https://repo.huaweicloud.com/alpine/v3.21/main/aarch64/$name" -o "$out/$name"
  printf '%s  %s\n' "$digest" "$out/$name" | shasum -a 256 -c -
done
if [[ "$IOS_NODE_MAJOR" == 24 ]]; then
  archive="$out/node-musl.tar.xz"
  [[ -f "$archive" ]] || curl -fL --retry 2 --connect-timeout 20 \
    https://unofficial-builds.nodejs.org/download/release/v24.22.1/node-v24.22.1-linux-arm64-musl.tar.xz -o "$archive"
  printf '%s  %s\n' 1938774185b35e42f0b064f0998dd7a32fa912bba5bfa8422779df9be5c21c29 "$archive" | shasum -a 256 -c -
fi
image=alpine:3.21.0
docker image inspect "$image" >/dev/null 2>&1 || docker pull --platform linux/arm64 "$image"
docker image inspect "$image" --format '{{json .RepoDigests}}' | \
  grep -q sha256:21dc6063fd678b478f57c0e13f47560d0ea4eeba26dfc947b2a4f81f686b9f45
container="dsh-ios-r2-node$IOS_NODE_MAJOR-$(date +%s)"
if ! docker run --name "$container" --pull never --platform linux/arm64 \
  --mount "type=bind,src=$REPO_DIR,dst=/repo,readonly" \
  --mount "type=bind,src=$out,dst=/out" -e "IOS_NODE_MAJOR=$IOS_NODE_MAJOR" -e "RUNTIME_FLAVOR=${RUNTIME_FLAVOR:-probe}" \
  "$image" sh /repo/runtime/ios/scripts/build-alpine-container.sh; then
  echo "Build failed; container retained: $container" >&2; exit 1
fi
docker rm "$container"
# Fresh base: dev packages upgrade musl, but the tested runtime must retain r8.
container="dsh-ios-r2-pack$IOS_NODE_MAJOR-$(date +%s)"
if ! docker run --name "$container" --pull never --platform linux/arm64 \
  --mount "type=bind,src=$REPO_DIR,dst=/repo,readonly" \
  --mount "type=bind,src=$out,dst=/out" -e "IOS_NODE_MAJOR=$IOS_NODE_MAJOR" -e "RUNTIME_FLAVOR=${RUNTIME_FLAVOR:-probe}" \
  "$image" sh /repo/runtime/ios/scripts/pack-alpine-container.sh; then
  echo "Pack failed; container retained: $container" >&2; exit 1
fi
docker rm "$container"
python3 - "$out" <<'PYINFO'
import json,sys
from pathlib import Path
out=Path(sys.argv[1])
files={line.split(None,1)[1].strip():line.split()[0]
       for line in (out/'runtime-file-sha256.txt').read_text().splitlines()}
(out/'provenance.json').write_text(json.dumps({
  'alpine':'3.21.0','musl':'1.2.5-r8',
  'tzdata':(out/'tzdata-version.txt').read_text().strip(),
  'nodeVersion':(out/'node-version.txt').read_text().strip(),
  'nodeBuildId':(out/'node-build-id.txt').read_text().strip(),
  'files':files,
  'nativeBuildStatus':(out/'native-build-status.txt').read_text().splitlines(),
  'loadedNativePaths':json.loads((out/'loaded-native-paths.json').read_text()),
  'koffiSourceInstallHashes':(out/'koffi-source-install-sha256.txt').read_text().splitlines(),
  'sharpSourceInstallHashes':(out/'sharp-source-install-sha256.txt').read_text().splitlines()
  },indent=2)+'\n')
PYINFO
echo "Built iOS rootfs: $out/rootfs-ios-arm64.tar.xz"
