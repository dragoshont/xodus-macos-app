#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")/.."
backend=${1:-}
if [ "$#" -gt 1 ]; then
    printf '%s\n' 'Usage: sh tools/build_app.sh [explicit-management-engine]' >&2
    exit 2
fi
if [ -n "$backend" ] && [ ! -x "$backend" ]; then
    printf '%s\n' 'Backend must be an explicit executable management build.' >&2
    exit 2
fi
python3 tools/sync_contract.py
if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
    printf '%s\n' 'Packaging requires a frozen clean source commit.' >&2
    exit 1
fi
swift build -c release --product XodusPreview
swift build -c release --product XodusAuthHost
bin=$(swift build -c release --show-bin-path)
mkdir -p dist
stage=$(mktemp -d "$PWD/dist/Xodus-build.XXXXXX")
app="$stage/Xodus.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/XodusPreview" "$app/Contents/MacOS/Xodus"
cp "$bin/XodusAuthHost" "$app/Contents/MacOS/XodusAuthHost"
chmod 755 "$app/Contents/MacOS/XodusAuthHost"
cp tools/Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
for name in XodusAppFoundation_XodusPreview XodusAppFoundation_XodusManagement XodusAppFoundation_XodusAuthHost; do
    if [ ! -d "$bin/$name.bundle" ]; then
        printf '%s\n' "Missing required SwiftPM resource bundle: $name" >&2
        exit 1
    fi
    ditto "$bin/$name.bundle" "$app/Contents/Resources/$name.bundle"
done
codesign --force --sign - "$app/Contents/MacOS/XodusAuthHost"
helper_hash=$(shasum -a 256 "$app/Contents/MacOS/XodusAuthHost" | cut -d ' ' -f 1)
source_commit=$(git rev-parse HEAD)
python3 - "$app/Contents/Resources/XodusAuthHost.json" "$helper_hash" "$source_commit" <<'PY'
import json
import pathlib
import sys
pathlib.Path(sys.argv[1]).write_text(
    json.dumps({"version": 1, "sha256": sys.argv[2], "sourceCommit": sys.argv[3]}, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY
swift tools/RenderAppIcon.swift "$app/Contents/Resources/Xodus.iconset"
iconutil -c icns "$app/Contents/Resources/Xodus.iconset" -o "$app/Contents/Resources/Xodus.icns"
if [ -n "$backend" ]; then
    mkdir -p "$app/Contents/Resources/XodusEngine"
    cp "$backend" "$app/Contents/Resources/XodusEngine/xodus-cli"
    codesign --force --sign - "$app/Contents/Resources/XodusEngine/xodus-cli"
fi
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
plutil -lint "$app/Contents/Info.plist"
if [ -L dist/Xodus.app ]; then
    printf '%s\n' 'Refusing to replace a symlinked application.' >&2
    exit 1
fi
if [ -e dist/Xodus.app ]; then
    mv dist/Xodus.app "dist/Xodus-previous-$(date +%s).app"
fi
mv "$app" dist/Xodus.app
rmdir "$stage"
printf '%s\n' "$PWD/dist/Xodus.app"
printf '%s\n' 'Local ad-hoc-signed development app only. Not notarized, distributed or gameplay-certified.'
