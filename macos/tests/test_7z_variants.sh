#!/usr/bin/env bash
# SevenZipSharp 대체 구현(Compat/SevenZip) 점검: 7-Zip(7zz)으로 여러 형식의 7z를 만들어 엔진의 --test-7z로 확인한다.
# 사용: macos/tests/test_7z_variants.sh [엔진 실행 파일]
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/env.sh"

ENGINE="${1:-$REPO_ROOT/RomForge/bin/Release/net8.0/RomForge}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/rf7z-XXXX")"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/src/sub/deep"
head -c 700000 /dev/urandom > "$WORK/src/a.bin"
python3 -c "open('$WORK/src/sub/b.txt','w').write('RomForge 한글 텍스트 ' * 20000)"
head -c 300000 /dev/zero > "$WORK/src/sub/deep/c.dat"
cp /bin/ls "$WORK/src/ls_exe"

z() { (cd "$WORK" && 7zz a -bso0 -bsp0 "$@" ./src/*); }
z lzma2_solid.7z -ms=on
z ppmd.7z -m0=PPMd
z bzip2.7z -m0=BZip2
z bcj.7z -mf=BCJ
z enc.7z -pRomForge
z enc_hdr.7z -pRomForge -mhe=on
z split.7z -v300k

pass=0 fail=0
check() { # 설명 기대(ok|fail) 파일 [비밀번호]
  local desc="$1" expect="$2" file="$3" pw="${4:-}"
  local out
  if [[ -n "$pw" ]]; then out="$("$ENGINE" --test-7z "$WORK/$file" "$pw" 2>&1)"; else out="$("$ENGINE" --test-7z "$WORK/$file" 2>&1)"; fi
  local got=ok
  grep -q '^실패' <<<"$out" && got=fail
  if [[ "$got" == "$expect" ]]; then pass=$((pass + 1)); mark="통과"; else fail=$((fail + 1)); mark="불일치"; fi
  printf '%-34s 기대=%-4s 결과=%-4s %s | %s\n' "$desc" "$expect" "$got" "$mark" "$(grep -E '^(압축 해제 성공|실패)' <<<"$out" | head -1)"
}

check "LZMA2 solid"                ok   lzma2_solid.7z
check "PPMd"                       ok   ppmd.7z
check "BZip2"                      ok   bzip2.7z
check "BCJ 필터"                    ok   bcj.7z
check "암호(올바른 비밀번호)"          ok   enc.7z RomForge
check "암호(비밀번호 없음)"            fail enc.7z
check "암호(틀린 비밀번호)"            fail enc.7z WrongPass
check "헤더 암호(올바른 비밀번호)"      ok   enc_hdr.7z RomForge
check "헤더 암호(비밀번호 없음)"        fail enc_hdr.7z
check "분할 볼륨(.7z.001)"           ok   split.7z.001

echo "통과 $pass / 불일치 $fail"
[[ $fail -eq 0 ]]
