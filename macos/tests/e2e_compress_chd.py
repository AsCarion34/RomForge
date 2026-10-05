#!/usr/bin/env python3
"""
압축 탭 종단 간 테스트: 직접 만든 ISO9660 이미지를 upstream CompressMainViewModel로 CHD 압축한다.
  ViewModel 생성 → AddPaths → RunCommand → 진행률·로그 알림 → .chd 결과 확인
"""
import os
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(__file__))
from bridge_client import Engine, ref  # noqa: E402


def make_test_iso(workdir):
    src = os.path.join(workdir, "disc")
    os.makedirs(src)
    for i in range(3):
        with open(os.path.join(src, f"DATA{i}.BIN"), "wb") as f:
            f.write(os.urandom(2 * 1024 * 1024))
    iso = os.path.join(workdir, "test.iso")
    subprocess.run(["hdiutil", "makehybrid", "-iso", "-joliet", "-o", iso, src],
                   check=True, capture_output=True)
    shutil.rmtree(src)
    return iso


def main():
    workdir = tempfile.mkdtemp(prefix="romforge-e2e-")
    iso = make_test_iso(workdir)
    print(f"테스트 ISO: {iso} ({os.path.getsize(iso):,} bytes)")

    engine = Engine(ui_answers={"ui.messageBox": "OK"})
    try:
        ready = engine.wait_notification("ready", timeout=30)
        root = ref(ready["root"])
        main_vm = engine.request("describe", obj=root)
        compress = ref(main_vm["props"]["CompressVM"])
        vm = engine.request("describe", obj=compress)
        props = vm["props"]
        print("CompressMainViewModel 속성:", ", ".join(sorted(props)))

        file_items = ref(props["FileItems"])
        log_entries = ref(props["LogEntries"])
        run_cmd = ref(props["RunCommand"])
        engine.request("list", obj=file_items)
        engine.request("list", obj=log_entries)

        engine.request("call", obj=compress, method="AddPaths", args=[[iso]])
        items = engine.wait_notification("collection", timeout=30)
        while items["obj"] != file_items:
            items = engine.wait_notification("collection", timeout=30)
        item_id = ref(items["items"][0])
        item = engine.request("describe", obj=item_id)["props"]
        print(f"추가된 항목: {item.get('FileName')} / 상태={item.get('Status')} / 포맷={item.get('Extension')}")

        started = time.time()
        assert engine.request("execute", cmd=run_cmd) is True, "RunCommand를 실행할 수 없습니다"

        seen_logs = 0
        status = item.get("Status")
        last_progress = None
        while time.time() - started < 300:
            msg = engine.notifications.get(timeout=300)
            p = msg["params"]
            if msg["method"] == "changed" and p["obj"] == item_id:
                status = p["props"].get("Status", status)
                progress = p["props"].get("Progress", last_progress)
                if progress != last_progress:
                    last_progress = progress
                    print(f"  진행률 {progress}% (상태: {status})")
            elif msg["method"] == "collection" and p["obj"] == log_entries:
                for entry in p["items"][seen_logs:]:
                    e = engine.request("describe", obj=ref(entry))["props"]
                    print(f"  [log:{e.get('Level')}] {e.get('Message')}")
                seen_logs = len(p["items"])
            elif msg["method"] == "engineError":
                print("  [engineError]", p["message"])
            if status in ("완료", "실패", "미지원", "취소"):
                break

        elapsed = time.time() - started
        chd = os.path.splitext(iso)[0] + ".chd"
        ok = status == "완료" and os.path.exists(chd)
        if ok:
            with open(chd, "rb") as f:
                magic = f.read(8)
            print(f"결과: {chd} ({os.path.getsize(chd):,} bytes, 헤더 {magic!r}) / {elapsed:.1f}초")
            ok = magic == b"MComprHD"
        print("성공" if ok else f"실패 (상태={status})")
        return 0 if ok else 1
    finally:
        engine.close()
        if engine.stderr_lines:
            print("--- 엔진 stderr (마지막 15줄) ---")
            print("\n".join(engine.stderr_lines[-15:]))


if __name__ == "__main__":
    sys.exit(main())
