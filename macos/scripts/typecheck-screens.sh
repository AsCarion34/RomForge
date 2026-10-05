#!/usr/bin/env bash
# 공용 코드 + 지정한 화면 폴더만 Swift 타입 검사한다(다른 화면이 작업 중이어도 영향을 받지 않는다).
# 사용: macos/scripts/typecheck-screens.sh Patch           → Screens/Patch/*.swift 검사
#       macos/scripts/typecheck-screens.sh                 → 공용 코드만 검사
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../App/Sources/RomForgeMac" && pwd)"

files=("$SRC"/Engine/*.swift "$SRC"/Components/*.swift "$SRC"/Views/UpstreamAssets.swift "$SRC"/Views/LogListView.swift)
for group in "$@"; do
  files+=("$SRC"/Screens/"$group"/*.swift)
done

xcrun swiftc -typecheck -parse-as-library -swift-version 5 \
  -sdk "$(xcrun --show-sdk-path)" -target "$(uname -m)-apple-macos14.0" \
  "${files[@]}"
echo "타입 검사 통과: 공용 코드${*:+ + $*}"
