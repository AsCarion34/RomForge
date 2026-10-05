#!/usr/bin/env bash
# upstream RomForge.csproj를 macOS 빌드 프로필로 빌드해 화면 없는 엔진을 만든다.
# 사용: macos/scripts/build-engine.sh [build|publish] [추가 dotnet 인자...]
#       CONFIG=Debug macos/scripts/build-engine.sh build     → RomForge/bin/Debug/net8.0/
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

"$MACOS_DIR/scripts/ensure-private-assets.sh"

verb="${1:-build}"
[[ $# -gt 0 ]] && shift

# NuGet 복원은 전역 TargetFramework를 지우고 프로젝트 값을 읽으므로 TargetFrameworks도 함께 넘긴다.
dotnet "$verb" "$REPO_ROOT/RomForge/RomForge.csproj" -c "${CONFIG:-Release}" -nologo \
  -p:TargetFramework=net8.0 \
  -p:TargetFrameworks=net8.0 \
  -p:UseWPF=false \
  -p:RomForgeMac=true \
  -p:CustomAfterMicrosoftCommonTargets="$MACOS_DIR/build/Mac.targets" \
  "$@"
