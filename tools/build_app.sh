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
swift build -c release --product XodusPreview
bin=$(swift build -c release --show-bin-path)
mkdir -p dist
stage=$(mktemp -d "$PWD/dist/Xodus-build.XXXXXX")
app="$stage/Xodus.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/XodusPreview" "$app/Contents/MacOS/Xodus"
cp tools/Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
for name in XodusAppFoundation_XodusPreview XodusAppFoundation_XodusManagement; do
    if [ ! -d "$bin/$name.bundle" ]; then
        printf '%s\n' "Missing required SwiftPM resource bundle: $name" >&2
        exit 1
    fi
    ditto "$bin/$name.bundle" "$app/Contents/Resources/$name.bundle"
done
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
