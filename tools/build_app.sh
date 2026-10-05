#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Execute only after independent operator approval of source and sealed CLI inputs.
set -eu
cd "$(dirname "$0")/.."
if [ "$#" -ne 8 ]; then
    printf '%s\n' 'Usage: build_app.sh engine unsignedSHA bytes provenanceSHA bytes approvedAppCommit approvedAppTree newOutputRoot' >&2
    exit 2
fi
engine=$1
engine_hash=$2
engine_bytes=$3
proof_hash=$4
proof_bytes=$5
source=$6
tree=$7
output_root=$8
test "$(git rev-parse HEAD)" = "$source"
test "$(git rev-parse 'HEAD^{tree}')" = "$tree"
if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
    printf '%s\n' 'Packaging requires an independently approved frozen clean source commit.' >&2
    exit 1
fi
python3 - "$output_root" <<'PY'
import os, pathlib, stat, sys
p = pathlib.Path(sys.argv[1])
s = p.lstat()
assert p.is_absolute() and p.resolve(strict=True) == p and stat.S_ISDIR(s.st_mode)
assert s.st_uid == os.getuid() and s.st_mode & 0o022 == 0
PY
stage=$(mktemp -d "$output_root/Xodus-controlled-pair.XXXXXX")
python3 tools/shipping_pair.py verify --engine "$engine" --engine-hash "$engine_hash" \
    --engine-bytes "$engine_bytes" --proof-hash "$proof_hash" --proof-bytes "$proof_bytes" \
    --output "$stage/unsigned-approval.json"
git archive --format=tar "$source" > "$stage/source.tar"
mkdir "$stage/source"
tar -xf "$stage/source.tar" -C "$stage/source"
cd "$stage/source"
python3 tools/sync_runtime_provider_contract.py --check
XODUS_SHIPPING=1 swift build -c release --product XodusAuthHost
bin=$(XODUS_SHIPPING=1 swift build -c release --show-bin-path)
app="$stage/Xodus.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/XodusEngine"
cp "$bin/XodusAuthHost" "$app/Contents/MacOS/XodusAuthHost"
cp "$engine" "$app/Contents/Resources/XodusEngine/xodus-cli"
python3 - "$app/Contents/Resources/XodusEngine/xodus-cli" "$engine_hash" "$engine_bytes" <<'PY'
import sys
from tools.shipping_pair import owned_bytes
owned_bytes(sys.argv[1], sys.argv[2], int(sys.argv[3]))
PY
chmod 755 "$app/Contents/MacOS/XodusAuthHost" "$app/Contents/Resources/XodusEngine/xodus-cli"
codesign --force --sign - "$app/Contents/MacOS/XodusAuthHost"
codesign --force --sign - "$app/Contents/Resources/XodusEngine/xodus-cli"
python3 tools/shipping_pair.py generate --source "$source" --tree "$tree" \
    --engine "$app/Contents/Resources/XodusEngine/xodus-cli" --helper "$app/Contents/MacOS/XodusAuthHost" \
    --approval "$stage/unsigned-approval.json" --output Sources/XodusPreview/ShippingPairPins.swift \
    --receipt "$stage/paired-inputs.json"
XODUS_SHIPPING=1 swift build -c release --product XodusPreview
cp "$bin/XodusPreview" "$app/Contents/MacOS/Xodus"
cp tools/Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
ditto "$bin/XodusAppFoundation_XodusManagement.bundle" \
    "$app/Contents/Resources/XodusAppFoundation_XodusManagement.bundle"
python3 - "$stage/paired-inputs.json" "$app/Contents/Resources/XodusAuthHost.json" <<'PY'
import json, pathlib, sys
record = json.loads(pathlib.Path(sys.argv[1]).read_bytes())
pathlib.Path(sys.argv[2]).write_text(json.dumps({
    "version": 1, "sha256": record["signedHelper"]["sha256"],
    "sourceCommit": record["approvedAppSourceCommit"]}, sort_keys=True) + "\n", encoding="utf-8")
PY
swift tools/RenderAppIcon.swift "$app/Contents/Resources/Xodus.iconset"
iconutil -c icns "$app/Contents/Resources/Xodus.iconset" -o "$app/Contents/Resources/Xodus.icns"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
plutil -lint "$app/Contents/Info.plist"
python3 tools/verify_shipping_package.py "$stage"
# Re-pin original unsigned inputs after all copying/building/signing.
python3 tools/shipping_pair.py verify --engine "$engine" --engine-hash "$engine_hash" \
    --engine-bytes "$engine_bytes" --proof-hash "$proof_hash" --proof-bytes "$proof_bytes" \
    --output "$stage/unsigned-approval-after.json"
cmp "$stage/unsigned-approval.json" "$stage/unsigned-approval-after.json"
printf '%s\n' "$app" "$stage/package-receipt.json"
printf '%s\n' 'Controlled local pair only. No launch, account operation, previous app replacement, notarization or gameplay qualification.'
