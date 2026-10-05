#!/usr/bin/env bash
# RomForge.app 번들을 만든다: SwiftUI 앱 + 자급식(.NET 런타임 포함) 엔진 + 네이티브 dylib + upstream 아이콘.
# 기본은 유니버설(Apple Silicon + Intel). 엔진은 아키텍처마다 따로 들어간다(Resources/Engine-<arch>).
# 사용: macos/scripts/build-app.sh                    → macos/.build/RomForge.app
#       ARCHS="arm64" macos/scripts/build-app.sh      → Apple Silicon 전용(용량 절반)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

read -r -a ARCH_LIST <<< "${ARCHS:-arm64 x86_64}"
OUT="$MACOS_DIR/.build"
APP="$OUT/RomForge.app"

# 1) 네이티브 라이브러리(없을 때만)
for lib in libromforge_win32shim libromforge_macdisk libxdelta3 libchdr libchdman; do
  [[ -f "$OUT/native/$lib.dylib" ]] || ARCHS="${ARCH_LIST[*]}" "$MACOS_DIR/Native/build-native.sh" all
done

# 2) 엔진: upstream RomForge.csproj를 macOS 프로필로 아키텍처마다 자급식 게시
for arch in "${ARCH_LIST[@]}"; do
  rid="osx-${arch/x86_64/x64}"
  rm -rf "$OUT/engine-$rid"
  "$MACOS_DIR/scripts/build-engine.sh" publish -r "$rid" --self-contained true -o "$OUT/engine-$rid" -clp:NoSummary
  # Windows 전용 네이티브 DLL은 넣지 않는다.
  rm -f "$OUT/engine-$rid"/{7z,chdman,chdr,xdelta3}.dll
done

# 3) SwiftUI 앱(유니버설)
SWIFT_ARCHS=()
for arch in "${ARCH_LIST[@]}"; do SWIFT_ARCHS+=(--arch "$arch"); done
swift build -c release --package-path "$MACOS_DIR/App" "${SWIFT_ARCHS[@]}"
BIN="$(swift build -c release --package-path "$MACOS_DIR/App" "${SWIFT_ARCHS[@]}" --show-bin-path)/RomForgeMac"

# 4) 번들 구성
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/UpstreamAssets"
cp "$BIN" "$APP/Contents/MacOS/RomForgeMac"
for arch in "${ARCH_LIST[@]}"; do
  cp -R "$OUT/engine-osx-${arch/x86_64/x64}" "$APP/Contents/Resources/Engine-$arch"
done

# upstream 아이콘(이름이 겹치면 RomForge 것을 우선)
for dir in NSW.WPF Common.WPF RomForge; do
  cp "$REPO_ROOT/$dir/Assets/Images/"*.png "$APP/Contents/Resources/UpstreamAssets/" 2>/dev/null || true
done

cp "$REPO_ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
cp "$MACOS_DIR/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"

# 앱 아이콘: upstream icon.ico → icns
ICONSET="$OUT/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
sips -s format png "$REPO_ROOT/RomForge/icon.ico" --out "$OUT/icon-src.png" > /dev/null
for size in 16 32 128 256 512; do
  sips -z $size $size "$OUT/icon-src.png" --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
  sips -z $((size * 2)) $((size * 2)) "$OUT/icon-src.png" --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

UPSTREAM_VERSION="$(sed -n 's:.*<VersionPrefix>\(.*\)</VersionPrefix>.*:\1:p' "$REPO_ROOT/RomForge/RomForge.csproj" | head -1)"
BUILD_STAMP="$(date +%Y%m%d%H%M%S)"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>RomForge</string>
  <key>CFBundleDisplayName</key><string>RomForge</string>
  <key>CFBundleIdentifier</key><string>io.github.ascarion34.romforge</string>
  <key>CFBundleExecutable</key><string>RomForgeMac</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${UPSTREAM_VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_STAMP}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>GPL-2.0-or-later. 원본 RomForge © sinjunyoung</string>
</dict>
</plist>
PLIST

# 5) ad-hoc 서명(내부 Mach-O 먼저, 번들 마지막). 가입 없이 배포하므로 Developer ID 서명·공증은 하지 않는다.
find "$APP/Contents/Resources" -type f \( -name '*.dylib' -o -perm -u+x \) -print0 |
  while IFS= read -r -d '' f; do
    if file "$f" | grep -q 'Mach-O'; then codesign --force --sign - "$f" > /dev/null 2>&1; fi
  done
codesign --force --sign - "$APP"

echo "완료: $APP (upstream $UPSTREAM_VERSION, 빌드 $BUILD_STAMP, ${ARCH_LIST[*]})"
du -sh "$APP" | cut -f1
