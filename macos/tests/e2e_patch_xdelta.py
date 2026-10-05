#!/usr/bin/env python3
"""
패치 탭 종단 간 테스트: upstream NormalPatchMainViewModel로 xdelta3 패치(LZMA 보조 압축)를 적용한다.
  SourcePath 설정 → AddPatchSlot → 슬롯 FilePath 설정 → RunCommand → 결과 파일이 기대값과 같은지 비교
테스트용 패치는 macos/.build/tools/xdelta3(xdelta 3.1.0 CLI)로 만든다.
"""
import hashlib
import os
import random
import re
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(__file__))
from bridge_client import Engine, ref  # noqa: E402

XDELTA = os.path.join(os.path.dirname(__file__), "..", ".build", "tools", "xdelta3")


def sha1(path):
    with open(path, "rb") as f:
        return hashlib.sha1(f.read()).hexdigest()


def make_files(workdir):
    rnd = random.Random(42)
    source = bytearray(rnd.getrandbits(8) for _ in range(512 * 1024))
    target = bytearray(source)
    for _ in range(200):  # 군데군데 바꾸고 뒤에 데이터를 붙인다(번역 패치 흉내)
        pos = rnd.randrange(len(target) - 64)
        target[pos:pos + 32] = bytes(rnd.getrandbits(8) for _ in range(32))
    target += b"RomForge macOS patch test " * 1000

    src = os.path.join(workdir, "game.bin")
    tgt = os.path.join(workdir, "expected.bin")
    patch = os.path.join(workdir, "translation.xdelta")
    open(src, "wb").write(source)
    open(tgt, "wb").write(target)
    subprocess.run([XDELTA, "-e", "-f", "-S", "lzma", "-s", src, tgt, patch], check=True)
    return src, tgt, patch


def main():
    workdir = tempfile.mkdtemp(prefix="romforge-patch-")
    src, expected, patch = make_files(workdir)
    print(f"원본 {os.path.getsize(src):,}B, 기대 결과 {os.path.getsize(expected):,}B, 패치 {os.path.getsize(patch):,}B (LZMA)")

    engine = Engine(ui_answers={"ui.messageBox": "OK"})
    try:
        root = ref(engine.wait_notification("ready", timeout=30)["root"])
        patch_vm = ref(engine.request("describe", obj=root)["props"]["PatchVM"])
        pvm = engine.request("describe", obj=patch_vm)["props"]
        normal = ref(pvm["NormalVM"])
        run_cmd = ref(pvm["RunCommand"])

        nvm = engine.request("describe", obj=normal)["props"]
        logs = ref(nvm["LogEntries"])
        slots = ref(nvm["PatchSlots"])
        engine.request("list", obj=logs)

        engine.request("set", obj=normal, prop="SourcePath", value=src)
        engine.request("call", obj=normal, method="AddPatchSlot", args=[])
        slot = ref(engine.request("list", obj=slots)["items"][0])
        engine.request("set", obj=slot, prop="FilePath", value=patch)
        time.sleep(0.3)

        assert engine.request("execute", cmd=run_cmd) is True, "RunCommand를 실행할 수 없습니다"

        output = None
        seen = 0
        deadline = time.time() + 120
        done = False
        while time.time() < deadline and not done:
            msg = engine.notifications.get(timeout=120)
            if msg["method"] == "collection" and msg["params"]["obj"] == logs:
                items = msg["params"]["items"]
                for entry in items[seen:]:
                    e = engine.request("describe", obj=ref(entry))["props"]
                    text = e.get("Message", "")
                    print(f"  [log:{e.get('Level')}] {text}")
                    m = re.search(r"패치 완료: (/.+\.bin)$", text)
                    if m:
                        output = m.group(1)
                    if e.get("Level") in ("Ok", "Error") and ("완료" in text or "실패" in text or "오류" in text):
                        done = True
                seen = len(items)

        if output is None:  # 로그에 경로가 없으면 출력 폴더에서 가장 최근 파일을 찾는다
            outdir = os.path.expanduser("~/Library/Application Support/RomForge/Engine/output")
            for base in [os.path.join(os.path.dirname(__file__), "..", "..", "RomForge", "bin", "Release", "net8.0", "output"), outdir, workdir]:
                if os.path.isdir(base):
                    files = [os.path.join(base, f) for f in os.listdir(base) if f.endswith(".bin") and f != "expected.bin" and os.path.join(base, f) != src]
                    if files:
                        output = max(files, key=os.path.getmtime)
                        break

        ok = output is not None and os.path.exists(output) and sha1(output) == sha1(expected)
        print(f"결과 파일: {output}")
        print("성공: 패치 결과가 기대값과 일치합니다" if ok else "실패")
        return 0 if ok else 1
    finally:
        engine.close()
        errors = [l for l in engine.stderr_lines if "error" in l.lower()]
        if errors:
            print("--- 엔진 오류 ---")
            print("\n".join(errors[-10:]))


if __name__ == "__main__":
    sys.exit(main())
