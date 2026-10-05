#!/usr/bin/env python3
"""
7z 종단 간 테스트(Windows 7z.dll 대신 SharpCompress 기반 대체 구현)
  1) 패치 탭: 원본 롬을 .7z 안에 넣은 채로 xdelta 패치 적용 → 결과 해시 비교
  2) 암호 7z: upstream 비밀번호 흐름(틀리면 다시 묻기)을 stdio로 왕복 → 틀린 비밀번호 후 올바른 비밀번호로 열림
  3) 원본 후보가 여럿인 7z: NormalVM.RequestSourceSelectionAsync(bindCallback)로 앱에 물어 고른 파일에 패치
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


def prepare(workdir):
    rnd = random.Random(7)
    source = bytearray(rnd.getrandbits(8) for _ in range(384 * 1024))
    target = bytearray(source)
    for _ in range(100):
        pos = rnd.randrange(len(target) - 32)
        target[pos:pos + 16] = bytes(rnd.getrandbits(8) for _ in range(16))
    rom = os.path.join(workdir, "game.bin")
    expected = os.path.join(workdir, "expected.bin")
    patch = os.path.join(workdir, "fix.xdelta")
    open(rom, "wb").write(source)
    open(expected, "wb").write(target)
    subprocess.run([XDELTA, "-e", "-f", "-s", rom, expected, patch], check=True)

    source_7z = os.path.join(workdir, "game.7z")
    secret_7z = os.path.join(workdir, "secret-patch.7z")
    multi_7z = os.path.join(workdir, "multi.7z")
    decoy = os.path.join(workdir, "decoy.bin")
    open(decoy, "wb").write(bytes(rnd.getrandbits(8) for _ in range(256 * 1024)))
    subprocess.run(["7zz", "a", "-bso0", "-bsp0", source_7z, rom], check=True, cwd=workdir)
    subprocess.run(["7zz", "a", "-bso0", "-bsp0", "-pRomForge", "-mhe=on", secret_7z, patch], check=True, cwd=workdir)
    subprocess.run(["7zz", "a", "-bso0", "-bsp0", multi_7z, decoy, rom], check=True, cwd=workdir)
    os.remove(rom)  # 원본은 7z 안에만 남긴다
    os.remove(decoy)
    return source_7z, secret_7z, multi_7z, patch, expected


def wait_patch_output(engine, logs, seen):
    """로그에 '패치 완료: 경로'가 나올 때까지 기다린다. (결과 경로, 본 로그 수)"""
    output, deadline = None, time.time() + 120
    while time.time() < deadline and output is None:
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
            seen = len(items)
    return output, seen


def test_patch_from_7z_source(engine, source_7z, patch, expected):
    root = ref(engine.wait_notification("ready", timeout=30)["root"])
    pvm = engine.request("describe", obj=ref(engine.request("describe", obj=root)["props"]["PatchVM"]))["props"]
    normal = ref(pvm["NormalVM"])
    nvm = engine.request("describe", obj=normal)["props"]
    logs = ref(nvm["LogEntries"])
    engine.request("list", obj=logs)

    engine.request("set", obj=normal, prop="SourcePath", value=source_7z)
    engine.request("call", obj=normal, method="AddPatchSlot", args=[])
    slot = ref(engine.request("list", obj=ref(nvm["PatchSlots"]))["items"][0])
    engine.request("set", obj=slot, prop="FilePath", value=patch)
    time.sleep(0.5)
    assert engine.request("execute", cmd=ref(pvm["RunCommand"])) is True

    output, seen = wait_patch_output(engine, logs, 0)
    ok = output is not None and sha1(output) == sha1(expected)
    print(("  통과" if ok else "  실패") + f": 7z 안 원본으로 패치 → {output}")
    return ok, (pvm, normal, logs, seen)


def test_source_selection(engine, state, multi_7z, expected):
    pvm, normal, logs, seen = state
    asked = []

    def choose(params):
        asked.append(params)
        assert params["name"] == "patch.selectSource"
        candidates = params["args"][0]
        return next(c["EntryKey"] for c in candidates if c["EntryKey"].endswith("game.bin"))

    engine.ui_answers["ui.callback"] = choose
    # code-behind: NormalVM.RequestSourceSelectionAsync = ShowSourceSelectionDialogAsync
    engine.request("bindCallback", obj=normal, prop="RequestSourceSelectionAsync", name="patch.selectSource")
    engine.request("set", obj=normal, prop="SourcePath", value=multi_7z)
    time.sleep(0.5)
    assert engine.request("execute", cmd=ref(pvm["RunCommand"])) is True

    output, _ = wait_patch_output(engine, logs, seen)
    candidates = asked[0]["args"][0] if asked else []
    ok = (len(asked) == 1 and len(candidates) == 2 and all("Size" in c for c in candidates)
          and output is not None and sha1(output) == sha1(expected))
    print(("  통과" if ok else "  실패") + f": 후보 {[(c['EntryKey'], c['Size']) for c in candidates]} 중 game.bin 선택 → {output}")
    return ok


def test_password_round_trip(engine, secret_7z):
    answers = iter(["wrong-password", "RomForge"])
    prompts = []

    def answer(params):
        prompts.append(params)
        return next(answers)

    engine.ui_answers["ui.password"] = answer
    # keep: 연 압축을 돌려받아(upstream의 using var archive = opened.Value.Archive) 직접 닫는다.
    result = engine.request("archive.open", path=secret_7z, keep=True, timeout=60)
    archive = result.get("archive")
    ok = (result.get("opened") and result.get("password") == "RomForge"
          and len(prompts) == 2 and prompts[0]["wrongPassword"] is False and prompts[1]["wrongPassword"] is True
          and any(e.endswith("fix.xdelta") for e in result.get("entries", []))
          and isinstance(archive, dict))
    if archive:
        engine.request("call", obj=ref(archive), method="Dispose", args=[])
    print(("  통과" if ok else "  실패") + f": 암호 7z 열기, 입력창 {len(prompts)}번(두 번째는 '틀림' 표시), 항목 {result.get('entries')}, 압축 객체 {archive}")
    return ok


def main():
    workdir = tempfile.mkdtemp(prefix="romforge-7z-")
    source_7z, secret_7z, multi_7z, patch, expected = prepare(workdir)
    engine = Engine(ui_answers={"ui.messageBox": "OK"})
    try:
        print("1) 패치 탭: 7z 안의 원본")
        ok1, state = test_patch_from_7z_source(engine, source_7z, patch, expected)
        print("2) 암호 7z 비밀번호 왕복")
        ok2 = test_password_round_trip(engine, secret_7z)
        print("3) 원본 후보가 여럿인 7z: 앱에 물어 고르기")
        ok3 = test_source_selection(engine, state, multi_7z, expected)
        ok = ok1 and ok2 and ok3
        print("성공" if ok else "실패")
        return 0 if ok else 1
    finally:
        engine.close()


if __name__ == "__main__":
    sys.exit(main())
