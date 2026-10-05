#!/usr/bin/env python3
"""
SD/USB 이미지 굽기·읽기 종단 간 테스트(upstream ZipImageToolMainViewModel + PickPack.Disk의 macOS 구현).
실제 디스크는 쓰지 않는다: hdiutil로 붙인 "디스크 이미지 가상 장치"에만 쓴다.
  1) 16MB 빈 이미지를 장치로 붙이고(마운트 안 함), 내 소유 장치라 쓰기 권한만 직접 준다(관리자 인증 불필요)
  2) 엔진을 ROMFORGE_INCLUDE_DISK_IMAGES=1로 띄워 목록에서 그 장치를 고르고 굽기 → 장치 내용 비교
  3) 읽기로 장치 전체를 .img로 떠서 비교
사용: python3 macos/tests/e2e_disk_image.py [엔진 실행 파일]
"""
import os
import random
import re
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(__file__))
from bridge_client import Engine, ref  # noqa: E402

DISK_BYTES = 16 * 1024 * 1024


def sh(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def attach(image):
    out = sh("hdiutil", "attach", "-nomount", "-imagekey", "diskimage-class=CRawDiskImage", image)
    dev = out.split()[0]
    info = sh("diskutil", "info", dev)
    # 안전장치: 디스크 이미지 장치가 아니면 바로 멈춘다.
    if "Disk Image" not in info or "Virtual:                   Yes" not in info:
        subprocess.run(["hdiutil", "detach", dev, "-quiet"])
        raise SystemExit(f"디스크 이미지 장치가 아닙니다: {dev}")
    number = int(re.search(r"disk(\d+)$", dev).group(1))
    for node in (f"/dev/disk{number}", f"/dev/rdisk{number}"):
        os.chmod(node, 0o600)  # 내 소유 가상 장치에만 쓰기 권한
    return number


def wait_logs(engine, logs, until, timeout=120):
    seen, deadline, lines = 0, time.time() + timeout, []
    while time.time() < deadline:
        msg = engine.notifications.get(timeout=timeout)
        if msg["method"] == "collection" and msg["params"]["obj"] == logs:
            items = msg["params"]["items"]
            for entry in items[seen:]:
                e = engine.request("describe", obj=ref(entry))["props"]
                lines.append(e.get("Message", ""))
                print(f"  [log:{e.get('Level')}] {e.get('Message')}")
            seen = len(items)
            if any(until(line) for line in lines):
                return lines
    raise TimeoutError("완료 로그를 기다리다 시간이 지났습니다.")


def main():
    engine_path = sys.argv[1] if len(sys.argv) > 1 else None
    work = tempfile.mkdtemp(prefix="romforge-disk-")
    vdisk = os.path.join(work, "vdisk.img")
    source = os.path.join(work, "game-sd.img")
    readback = os.path.join(work, "readback.img")

    with open(vdisk, "wb") as f:
        f.truncate(DISK_BYTES)
    rnd = random.Random(3)
    payload = b"ROMFORGE-MACOS-DISK-TEST" + bytes(rnd.getrandbits(8) for _ in range(5 * 1024 * 1024 + 300))  # 섹터 배수가 아님
    with open(source, "wb") as f:
        f.write(payload)

    number = attach(vdisk)
    print(f"가상 장치: /dev/disk{number} (16MB), 원본 이미지 {len(payload):,}B")

    env = dict(os.environ, ROMFORGE_INCLUDE_DISK_IMAGES="1")
    os.environ.update(env)
    kwargs = {"path": engine_path} if engine_path else {}
    engine = Engine(ui_answers={"ui.messageBox": "Yes"}, **kwargs)
    ok = False
    try:
        root = ref(engine.wait_notification("ready", timeout=30)["root"])
        util = engine.request("describe", obj=ref(engine.request("describe", obj=root)["props"]["UtilMainVM"]))["props"]
        tool = ref(util["ZipImageToolVM"])
        vm = engine.request("describe", obj=tool)["props"]
        logs = ref(vm["LogEntries"])
        engine.request("list", obj=logs)

        drives = engine.request("list", obj=ref(vm["UsbDrives"]))["items"]
        target = None
        for d in drives:
            props = engine.request("describe", obj=ref(d))["props"]
            print(f"  목록: {props['DisplayName']} (disk{props['DiskNumber']})")
            if props["DiskNumber"] == number:
                target = ref(d)
        assert target, "목록에 가상 장치가 없습니다"

        engine.request("set", obj=tool, prop="SelectedDrive", value={"$obj": target})
        engine.request("set", obj=tool, prop="WriteImagePath", value=source)
        time.sleep(0.3)
        assert engine.request("execute", cmd=ref(vm["WriteCommand"])) is True
        wait_logs(engine, logs, lambda line: "완료" in line or "실패" in line or "오류" in line)

        with open(f"/dev/rdisk{number}", "rb") as dev:
            written = dev.read(len(payload) + 512)
        write_ok = written[:len(payload)] == payload
        pad = written[len(payload):len(payload) + (512 - len(payload) % 512) % 512]
        print(f"굽기 확인: 내용 {'일치' if write_ok else '불일치'}, 마지막 섹터 채움 {'0' if set(pad) <= {0} else '0 아님'}")

        engine.request("set", obj=tool, prop="ReadImagePath", value=readback)
        time.sleep(0.3)
        assert engine.request("execute", cmd=ref(vm["ReadCommand"])) is True
        wait_logs(engine, logs, lambda line: ("저장" in line and "완료" in line) or "실패" in line or "오류" in line)

        with open(f"/dev/rdisk{number}", "rb") as dev:
            device_bytes = dev.read(DISK_BYTES)
        read_ok = os.path.exists(readback) and open(readback, "rb").read() == device_bytes
        print(f"읽기 확인: {readback} {'장치 전체와 일치' if read_ok else '불일치'}")
        ok = write_ok and read_ok
    finally:
        engine.close()
        subprocess.run(["hdiutil", "detach", f"/dev/disk{number}", "-quiet", "-force"])
    print("성공" if ok else "실패")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
