#!/usr/bin/env bash
set -euo pipefail
APP=$(find build/macos/Build/Products/Release -maxdepth 1 -name '*.app' -type d -print -quit)
[[ -n "$APP" ]] || { echo 'No built macOS app found'; exit 1; }
EXE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")
test -x "$APP/Contents/MacOS/$EXE"
file "$APP/Contents/MacOS/$EXE"
lipo -archs "$APP/Contents/MacOS/$EXE" | tee macos-architectures.txt
# Keep the build's local/ad-hoc signature and sandbox entitlements. This is not a Developer ID/notarized release.
codesign --verify --deep --strict "$APP"
mkdir -p dist build/dmg-staging
cp -R "$APP" build/dmg-staging/
ln -s /Applications build/dmg-staging/Applications
cp docs/MACOS_INSTALL.md build/dmg-staging/README.txt
hdiutil create -volname 'Cloud Music' -srcfolder build/dmg-staging -format UDZO -ov dist/cloud-music-macos-unsigned.dmg
hdiutil verify dist/cloud-music-macos-unsigned.dmg
cp macos-architectures.txt dist/
