#!/usr/bin/env bash
# upstream이 .gitignore로 제외한 리소스(resx에 포함되는 파일)가 없으면 빈 대체 파일을 만든다.
# 대체 파일로 빌드는 통과하지만, 아래 기능은 실제 파일을 넣어야 동작한다.
#   - PBP.Core/*        : PS1 → PSP EBOOT(PBP) 변환
#   - 3DS.Core/Resources/*.3dsx : 3DS SD 직접 설치 마무리(custom-install, MIT)
# 실제 파일을 같은 경로에 넣으면 그대로 사용된다(이 스크립트는 기존 파일을 건드리지 않는다).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ASSETS=(
  "PBP.Core/BASE.zip"
  "PBP.Core/Config.zip"
  "PBP.Core/DATA.psp"
  "PBP.Core/DATA1.bin"
  "PBP.Core/DATA2.bin"
  "PBP.Core/DATA3.bin"
  "PBP.Core/GamesDB.zip"
  "PBP.Core/ICON0.png"
  "PBP.Core/PIC0.png"
  "PBP.Core/PIC1.png"
  "3DS.Core/Resources/custom-install-finalize.3dsx"
)

created=0
for rel in "${ASSETS[@]}"; do
  path="$ROOT/$rel"
  if [[ ! -e "$path" ]]; then
    mkdir -p "$(dirname "$path")"
    : > "$path"
    echo "[placeholder] $rel"
    created=$((created + 1))
  fi
done

if (( created > 0 )); then
  echo "빈 대체 파일 ${created}개를 만들었습니다. 해당 기능은 실제 파일을 넣기 전까지 동작하지 않습니다."
fi
