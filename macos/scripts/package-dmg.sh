#!/usr/bin/env bash
# 가입 없이 배포: ad-hoc 서명된 RomForge.app을 DMG로 묶는다.
#   macos/.build/RomForge.app → macos/.build/dist/RomForge-<버전>-macOS.dmg
# 받는 사람은 첫 실행 때 "그래도 열기"로 허용해야 한다(DMG 안의 '설치 안내.txt').
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

APP="$MACOS_DIR/.build/RomForge.app"
[[ -d "$APP" ]] || "$MACOS_DIR/scripts/build-app.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/RomForgeMac" | tr ' ' '+')"
STAGE="$MACOS_DIR/.build/dmg-stage"
DIST="$MACOS_DIR/.build/dist"
DMG="$DIST/RomForge-$VERSION-macOS-$ARCHS.dmg"

rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$MACOS_DIR/dist/설치 안내.txt" "$STAGE/"
cp "$REPO_ROOT/LICENSE" "$STAGE/LICENSE (GPL-2.0).txt"
cp "$MACOS_DIR/THIRD_PARTY_NOTICES.md" "$STAGE/"

rm -f "$DMG"
hdiutil create -volname "RomForge $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" > /dev/null
rm -rf "$STAGE"

echo "완료: $DMG"
du -h "$DMG" | cut -f1
