#!/usr/bin/env python3
"""
upstream 변경 중 macOS 쪽에서 손으로 확인할 곳을 정리한다.
  사용: python3 macos/scripts/ui-sync-report.py <이전 커밋> <새 커밋> [--schema-old a.json --schema-new b.json]

1) 화면: 바뀐 upstream XAML·code-behind → 그 파일을 "// upstream:" 주석에 적은 Swift 화면 파일
2) 대체 파일: macos/Overrides 또는 Compat이 대신하는 upstream 파일이 바뀌었는지
3) ViewModel 스키마: 속성·커맨드·메서드·enum의 추가/삭제/변경(엔진 --dump-schema 결과 비교)
4) 네이티브: chdman·xdelta3 소스나 MAME 버전 관련 변경
"""
import json
import os
import re
import subprocess
import sys

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
SCREENS = os.path.join(ROOT, "macos", "App", "Sources", "RomForgeMac")

# macOS 쪽이 내용을 대신하는 upstream 파일(대체 파일 목록 — README 표와 같게 유지)
OVERRIDDEN = {
    "RomForge/Views/PasswordPromptWindow.xaml.cs": "macos/Overrides/RomForge/PasswordPromptWindow.cs",
    "RomForge.Core/Services/Util/ClipboardHelper.cs": "macos/Overrides/RomForge.Core/ClipboardHelper.cs",
    "PickPack.Disk/Helpers/DriveInfos.cs": "macos/Overrides/PickPack.Disk/DriveInfos.cs",
    "PickPack.Disk/Services/ImageWriter.cs": "macos/Overrides/PickPack.Disk/ImageWriter.cs",
    "PickPack.Disk/Services/ImageReader.cs": "macos/Overrides/PickPack.Disk/ImageReader.cs",
    "PickPack.Disk/Helpers/DiskUtil.cs": "macos/Overrides/PickPack.Disk/DiskUtil.cs",
    "PickPack.Disk/Helpers/PartitionUtil.cs": "macos/Overrides/PickPack.Disk/PartitionUtil.cs",
    "Common/7z/NativeSevenZip.cs": "macos/Overrides/Common/NativeSevenZip.cs",
    "Common.WPF/SoundManager.cs": "macos/Overrides/Common.WPF/SoundManager.cs",
    "CHD.Core/src/tools/chdman_wrapper.h": "macos/Native/chdman/chdman_paths_mac.cpp (진입점 시그니처)",
}
NATIVE = ("CHD.Core/src/", "CHD.Core/scripts/", "Patch.Core/src/")


def changed_files(old, new):
    out = subprocess.run(["git", "diff", "--name-only", f"{old}..{new}"], capture_output=True, text=True, cwd=ROOT, check=True).stdout
    return [line for line in out.splitlines() if line and not line.startswith("macos/")]


def screen_map():
    """upstream 파일 → 그 파일을 옮긴 Swift 파일들"""
    mapping = {}
    for dirpath, _, files in os.walk(SCREENS):
        for name in files:
            if not name.endswith(".swift"):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding="utf-8") as f:
                head = "".join(f.readline() for _ in range(5))
            for m in re.finditer(r"upstream:\s*(.+)", head):
                for ref in re.split(r",\s*", m.group(1)):
                    ref = ref.strip()
                    base = ref.replace("(.cs)", "")
                    for variant in {base, base + ".cs"} if base.endswith(".xaml") else {base}:
                        mapping.setdefault(variant, set()).add(os.path.relpath(path, ROOT))
    return mapping


def schema_diff(old_path, new_path):
    old = json.load(open(old_path, encoding="utf-8"))
    new = json.load(open(new_path, encoding="utf-8"))
    lines = []
    for t in sorted(set(old) | set(new)):
        if t not in new:
            lines.append(f"- 타입 삭제: {t}")
            continue
        if t not in old:
            lines.append(f"+ 타입 추가: {t}")
            continue
        for section in ("properties", "methods", "enums"):
            a, b = old[t].get(section, {}), new[t].get(section, {})
            if isinstance(a, list):
                for item in sorted(set(b) - set(a)):
                    lines.append(f"+ {t} {section}: {item}")
                for item in sorted(set(a) - set(b)):
                    lines.append(f"- {t} {section}: {item}")
            else:
                for key in sorted(set(a) | set(b)):
                    if a.get(key) != b.get(key):
                        lines.append(f"~ {t}.{key} ({section}): {a.get(key)} → {b.get(key)}")
    return lines


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) < 2:
        print(__doc__)
        return 2
    old, new = args[0], args[1]
    files = changed_files(old, new)
    mapping = screen_map()

    print(f"# upstream 변경 점검 ({old[:10]}..{new[:10]}, 파일 {len(files)}개)\n")

    ui = [f for f in files if f.endswith((".xaml", ".xaml.cs"))]
    print("## 1. 화면(XAML·code-behind)")
    if not ui:
        print("- 없음")
    for f in ui:
        targets = sorted(mapping.get(f, [])) or ["(대응하는 Swift 화면 없음 — 새 화면이거나 자동 생성 화면으로 표시됨)"]
        print(f"- {f} → {', '.join(targets)}")

    print("\n## 2. 대체 파일")
    hits = [f for f in files if f in OVERRIDDEN]
    print("- 없음" if not hits else "\n".join(f"- {f} → {OVERRIDDEN[f]} 를 맞춰야 합니다" for f in hits))

    print("\n## 3. 네이티브")
    native = [f for f in files if f.startswith(NATIVE)]
    print("- 없음" if not native else "\n".join(f"- {f} (macos/Native/build-native.sh로 다시 빌드, MAME 버전 바뀌었는지 확인)" for f in native))

    if "--schema-old" in sys.argv and "--schema-new" in sys.argv:
        print("\n## 4. ViewModel 스키마")
        diff = schema_diff(sys.argv[sys.argv.index("--schema-old") + 1], sys.argv[sys.argv.index("--schema-new") + 1])
        print("- 변경 없음" if not diff else "\n".join(diff))
    return 0


if __name__ == "__main__":
    sys.exit(main())
