#!/usr/bin/env bash
# macOS용 네이티브 라이브러리를 macos/.build/native/ 에 만든다(기본: arm64 + x86_64 유니버설).
# 사용: macos/Native/build-native.sh [win32shim|macdisk|xz|xdelta3|libchdr|chdman|all|tools]
#       ARCHS="arm64" macos/Native/build-native.sh all      → 한 아키텍처만
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/env.sh"

NATIVE_DIR="$MACOS_DIR/Native"
OUT="$MACOS_DIR/.build/native"
WORK="$MACOS_DIR/.build/native-src"
mkdir -p "$OUT" "$WORK"

# 앱(LSMinimumSystemVersion)과 같은 최소 macOS. 이 값보다 높게 빌드되면 구버전 Mac에서 로드되지 않는다.
MIN_MACOS="${MIN_MACOS:-14.0}"
export MACOSX_DEPLOYMENT_TARGET="$MIN_MACOS"
read -r -a ARCH_LIST <<< "${ARCHS:-arm64 x86_64}"
ARCH_FLAGS=()
for a in "${ARCH_LIST[@]}"; do ARCH_FLAGS+=(-arch "$a"); done
CMAKE_ARCHS="$(IFS=';'; echo "${ARCH_LIST[*]}")"
CFLAGS_COMMON=(-O2 "${ARCH_FLAGS[@]}" -mmacosx-version-min="$MIN_MACOS" -fvisibility=hidden)
JOBS="$(sysctl -n hw.ncpu)"

fetch_github() { # owner/repo ref dest
  local dest="$3"
  [[ -d "$dest" ]] && return
  mkdir -p "$dest"
  curl -sSL "https://codeload.github.com/$1/tar.gz/$2" | tar -xz --strip-components=1 -C "$dest"
}

build_win32shim() {
  clang "${CFLAGS_COMMON[@]}" -dynamiclib \
    -install_name @rpath/libromforge_win32shim.dylib \
    -o "$OUT/libromforge_win32shim.dylib" \
    "$NATIVE_DIR/win32shim/win32shim.c" \
    -framework IOKit -framework CoreFoundation
  echo "[native] libromforge_win32shim.dylib"
}

# macdisk: macOS 물리 디스크 열기(authopen)·크기(ioctl). PickPack.Disk의 macOS 구현이 쓴다.
build_macdisk() {
  clang "${CFLAGS_COMMON[@]}" -dynamiclib \
    -install_name @rpath/libromforge_macdisk.dylib \
    -o "$OUT/libromforge_macdisk.dylib" \
    "$NATIVE_DIR/macdisk/macdisk.c"
  echo "[native] libromforge_macdisk.dylib"
}

# liblzma(xz): xdelta3의 LZMA 보조 압축용. 최소 macOS·아키텍처를 맞추려고 소스에서 정적 라이브러리로 빌드한다.
XZ_TAG="${XZ_TAG:-v5.8.4}"
XZ_SRC="$WORK/xz-$XZ_TAG"

build_xz() {
  fetch_github tukaani-project/xz "refs/tags/$XZ_TAG" "$XZ_SRC"
  cmake -S "$XZ_SRC" -B "$XZ_SRC/build" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="$CMAKE_ARCHS" -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS" \
    -DBUILD_SHARED_LIBS=OFF -DXZ_TOOL_XZ=OFF -DXZ_TOOL_XZDEC=OFF -DXZ_TOOL_LZMADEC=OFF \
    -DXZ_TOOL_LZMAINFO=OFF -DXZ_TOOL_SCRIPTS=OFF -DXZ_DOC=OFF -DXZ_NLS=OFF > /dev/null
  cmake --build "$XZ_SRC/build" --config Release -j"$JOBS" --target liblzma > /dev/null
  echo "[native] liblzma.a (xz $XZ_TAG, 정적)"
}

# xdelta3: upstream 래퍼(Patch.Core/src/xdelta3_wrapper.c)와 같은 설정으로 빌드한다.
# 래퍼가 SECONDARY_LZMA를 켜므로 liblzma를 정적으로 묶는다.
XDELTA_TAG="${XDELTA_TAG:-v3.1.0}"

build_xdelta3() {
  local src="$WORK/xdelta-$XDELTA_TAG"
  fetch_github jmacd/xdelta "refs/tags/$XDELTA_TAG" "$src"
  [[ -f "$XZ_SRC/build/liblzma.a" ]] || build_xz

  clang "${CFLAGS_COMMON[@]}" -dynamiclib -Wno-everything \
    -install_name @rpath/libxdelta3.dylib \
    -DXD3_ENCODER=1 -DSECONDARY_LZMA=1 -DSECONDARY_DJW=1 -DXD3_USE_LARGEFILE64=1 -DXD3_STDIO=1 \
    -DSIZEOF_SIZE_T=8 -DSIZEOF_UNSIGNED_LONG_LONG=8 -DSIZEOF_USIZE_T=8 -DSIZEOF_XOFF_T=8 -DXD3_DEBUG=0 \
    -I "$src/xdelta3" -I "$XZ_SRC/src/liblzma/api" \
    "$src/xdelta3/xdelta3.c" "$REPO_ROOT/Patch.Core/src/xdelta3_wrapper.c" \
    "$XZ_SRC/build/liblzma.a" \
    -o "$OUT/libxdelta3.dylib"
  echo "[native] libxdelta3.dylib (xdelta $XDELTA_TAG + upstream 래퍼)"
}

# libchdr: CHD 헤더·메타데이터 읽기(CHD.Core/Interop/LibChdr.cs). 공개 API가 안정적이라 커밋을 고정해 쓴다.
LIBCHDR_REF="${LIBCHDR_REF:-607694ca0812edfc9cc2030c64634fc2393668de}"

build_libchdr() {
  local src="$WORK/libchdr-$LIBCHDR_REF"
  fetch_github rtissera/libchdr "$LIBCHDR_REF" "$src"

  rm -rf "$src/build"
  cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="$CMAKE_ARCHS" -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DINSTALL_STATIC_LIBS=OFF > /dev/null
  cmake --build "$src/build" --config Release -j"$JOBS" > /dev/null

  local built
  built="$(find "$src/build" -name 'libchdr*.dylib' -type f | head -1)"
  [[ -n "$built" ]] || { echo "libchdr 결과물을 찾지 못했습니다." >&2; exit 1; }

  cp "$built" "$OUT/libchdr.dylib"
  install_name_tool -id @rpath/libchdr.dylib "$OUT/libchdr.dylib"
  echo "[native] libchdr.dylib ($LIBCHDR_REF)"
}

# chdman: upstream README의 서드파티 목록대로 MAME chdman을 쓴다.
# upstream이 수정한 파일(CHD.Core/src, CHD.Core/scripts)을 같은 버전의 MAME 원본에 덮어 빌드한다.
# upstream이 MAME 버전을 바꾸면 MAME_TAG를 맞춘다(커밋 기록: "chdman 구버전(v0.287) 복원").
MAME_TAG="${MAME_TAG:-mame0287}"

build_chdman() {
  local src="$WORK/mame-$MAME_TAG"

  if [[ ! -d "$src" ]]; then
    echo "[native] MAME 소스 받는 중: $MAME_TAG"
    curl -sSL -o "$WORK/$MAME_TAG.tar.gz" "https://codeload.github.com/mamedev/mame/tar.gz/refs/tags/$MAME_TAG"
    tar -xzf "$WORK/$MAME_TAG.tar.gz" -C "$WORK"
  fi

  # upstream 수정본을 MAME 트리에 덮는다(upstream 파일 자체는 건드리지 않는다).
  cp "$REPO_ROOT"/CHD.Core/src/tools/chdman.cpp \
     "$REPO_ROOT"/CHD.Core/src/tools/chdman_wrapper.cpp \
     "$REPO_ROOT"/CHD.Core/src/tools/chdman_wrapper.h \
     "$src/src/tools/"
  cp "$REPO_ROOT/CHD.Core/src/lib/util/cdrom.cpp" "$src/src/lib/util/"
  cp "$REPO_ROOT/CHD.Core/scripts/src/tools.lua" "$src/scripts/src/tools.lua"

  # macOS 진입점 래퍼(Windows 긴 경로 접두사 처리)를 덧붙인다.
  cp "$NATIVE_DIR/chdman/chdman_paths_mac.cpp" "$src/src/tools/"
  cat "$NATIVE_DIR/chdman/tools_mac.lua" >> "$src/scripts/src/tools.lua"

  local projdir="build/projects/mac/mametiny/gmake-osx-clang"
  local slices=()

  # 아키텍처마다 처음부터 빌드한다(MAME는 아키텍처별 오브젝트 폴더를 나누지 않는다).
  for arch in "${ARCH_LIST[@]}"; do
    local platform=arm64
    [[ "$arch" == "x86_64" ]] && platform=x86
    # OSD=mac: SDL 없이 시스템 프레임워크만 링크. -mmacosx-version-min: 최소 macOS 고정.
    local params=(TOOLS=1 EMULATOR=0 SUBTARGET=tiny NOWERROR=1 PTR64=1 OSD=mac PLATFORM="$platform"
                  ARCHOPTS="-mmacosx-version-min=$MIN_MACOS")

    # upstream tools.lua가 chdman_dll 오브젝트를 build/ 밖(mingw-gcc/)에 두므로 함께 지운다.
    rm -rf "$src/build" "$src/mingw-gcc" "$src"/libchdman_dll*.dylib
    make -C "$src" "${params[@]}" -j"$JOBS" generate "$projdir/Makefile" > "$WORK/chdman-$arch.log" 2>&1
    make -C "$src/$projdir" config=release64 -j"$JOBS" chdman_dll >> "$WORK/chdman-$arch.log" 2>&1 ||
      { tail -20 "$WORK/chdman-$arch.log"; exit 1; }

    local built
    built="$(find "$src" -maxdepth 3 -name '*chdman_dll*.dylib' -newer "$src/src/tools/chdman_wrapper.cpp" | head -1)"
    [[ -n "$built" ]] || { echo "chdman_dll 결과물을 찾지 못했습니다($arch)." >&2; exit 1; }

    # 진입점이 빠진 결과물(오브젝트 아키텍처 불일치 등)을 걸러 낸다.
    nm -gU "$built" | grep -q ' _chdman_create_cd$' ||
      { echo "chdman_dll($arch)에 진입점이 없습니다. 로그: $WORK/chdman-$arch.log" >&2; exit 1; }

    cp "$built" "$WORK/libchdman-$arch.dylib"
    slices+=("$WORK/libchdman-$arch.dylib")
  done

  lipo -create "${slices[@]}" -output "$OUT/libchdman.dylib"
  install_name_tool -id @rpath/libchdman.dylib "$OUT/libchdman.dylib"
  echo "[native] libchdman.dylib (MAME $MAME_TAG + upstream 수정본, ${ARCH_LIST[*]})"
}

# 테스트 도구: xdelta3 명령줄(패치 생성용, 앱에는 넣지 않는다) → macos/.build/tools/xdelta3
build_tools() {
  local src="$WORK/xdelta-$XDELTA_TAG"
  fetch_github jmacd/xdelta "refs/tags/$XDELTA_TAG" "$src"
  [[ -f "$XZ_SRC/build/liblzma.a" ]] || build_xz
  mkdir -p "$MACOS_DIR/.build/tools"
  clang -O2 -w -DXD3_MAIN=1 -DXD3_POSIX=1 -DXD3_ENCODER=1 -DSECONDARY_LZMA=1 -DSECONDARY_DJW=1 \
    -DXD3_USE_LARGEFILE64=1 -DSIZEOF_SIZE_T=8 -DSIZEOF_UNSIGNED_LONG_LONG=8 -DSIZEOF_USIZE_T=8 -DSIZEOF_XOFF_T=8 -DXD3_DEBUG=0 \
    -I "$src/xdelta3" -I "$XZ_SRC/src/liblzma/api" "$src/xdelta3/xdelta3.c" "$XZ_SRC/build/liblzma.a" \
    -o "$MACOS_DIR/.build/tools/xdelta3"
  echo "[native] tools/xdelta3 (테스트용)"
}

target="${1:-all}"
case "$target" in
  tools) build_tools ;;
  win32shim) build_win32shim ;;
  macdisk) build_macdisk ;;
  xz) build_xz ;;
  xdelta3) build_xdelta3 ;;
  libchdr) build_libchdr ;;
  chdman) build_chdman ;;
  all) build_win32shim; build_macdisk; build_xz; build_xdelta3; build_libchdr; build_chdman ;;
  *) echo "알 수 없는 대상: $target" >&2; exit 1 ;;
esac
