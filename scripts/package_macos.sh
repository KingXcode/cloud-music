#!/usr/bin/env bash
set -euo pipefail
APP=build/macos/Build/Products/Release/Xianbo.app
[[ -d "$APP" ]] || { echo 'No built Xianbo macOS app found'; exit 1; }
EXE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")
test -x "$APP/Contents/MacOS/$EXE"
file "$APP/Contents/MacOS/$EXE"
lipo -archs "$APP/Contents/MacOS/$EXE" | tee macos-architectures.txt
# 保留构建产物的本地临时签名和沙盒授权，此版本未使用 Developer ID 签名，也未经过公证。
codesign --verify --deep --strict "$APP"
mkdir -p dist
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/xianbo-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp docs/MACOS_INSTALL.md "$STAGING/README.txt"
hdiutil create -volname 'Xianbo' -srcfolder "$STAGING" -format UDZO -ov dist/cloud-music-macos-unsigned.dmg
hdiutil verify dist/cloud-music-macos-unsigned.dmg
cp macos-architectures.txt dist/

# Record the built bundle version, not the workflow's tag or current source file.
export UPDATE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
export UPDATE_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
python3 - <<'PY_VERSION'
import json, os
with open('dist/macos-version.json', 'w') as stream:
    json.dump({'version': os.environ['UPDATE_VERSION'], 'build': os.environ['UPDATE_BUILD']}, stream)
PY_VERSION
