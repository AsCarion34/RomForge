#!/usr/bin/env python3
"""
브리지 부가 기능 점검: call/callStatic 선택 항목(exclusive·cancelKey·background), 선택 인자 생략,
convert valueType, 2^53을 넘는 정수 왕복.

    ROMFORGE_ENGINE=RomForge/bin/Debug/net8.0/RomForge python3 macos/tests/e2e_bridge_features.py
"""
import json
import os
import sys
import tempfile
import threading
import time

sys.path.insert(0, os.path.dirname(__file__))
from bridge_client import Engine, ref  # noqa: E402


def send_async(engine, rpc_method, **params):
    """응답을 기다리지 않고 보낸다. 결과는 wait_result로 받는다."""
    rid = engine.next_id
    engine.next_id += 1
    engine._send({"id": rid, "method": rpc_method, "params": params})
    return rid


def wait_result(engine, rid, timeout=60):
    deadline = time.time() + timeout
    with engine.cond:
        while rid not in engine.responses:
            left = deadline - time.time()
            if left <= 0:
                raise TimeoutError(rid)
            engine.cond.wait(left)
        return engine.responses.pop(rid)


def check(name, ok, detail=""):
    print(("  통과" if ok else "  실패") + f": {name}" + (f" — {detail}" if detail else ""))
    return ok


def test_exclusive(engine):
    first = send_async(engine, "callStatic", type="System.Threading.Tasks.Task", method="Delay", args=[800], exclusive=True)
    time.sleep(0.2)
    second = wait_result(engine, send_async(engine, "callStatic", type="System.Threading.Tasks.Task", method="Delay", args=[10], exclusive=True))
    first_result = wait_result(engine, first)
    third = wait_result(engine, send_async(engine, "callStatic", type="System.Threading.Tasks.Task", method="Delay", args=[10], exclusive=True))
    return check("exclusive: 실행 중 같은 호출 거절, 끝난 뒤엔 다시 허용",
                 "error" in second and "이미 실행 중" in second["error"]["message"] and "error" not in first_result and "error" not in third,
                 json.dumps(second.get("error"), ensure_ascii=False))


def test_cancel_upstream(engine, workdir):
    # upstream ZipCompressor.CompressFromFileAsync(src, src, outDir, ct): 마지막 CancellationToken 인자는 생략(cancelKey 토큰이 들어간다)
    source = os.path.join(workdir, "big.bin")
    with open(source, "wb") as f:
        f.truncate(6 * 1024 * 1024 * 1024)  # 빈 공간 파일(디스크를 쓰지 않음)

    compressor = engine.request("create", type="RomForge.Core.Services.Patch.ZipCompressor", args=[None, None])
    rid = send_async(engine, "call", obj=ref(compressor), method="CompressFromFileAsync", args=[source, source, workdir], cancelKey="zip")
    time.sleep(0.5)
    cancelled = engine.request("cancel", key="zip")
    started = time.time()
    response = wait_result(engine, rid, timeout=30)
    elapsed = time.time() - started
    again = engine.request("cancel", key="zip")  # 끝난 뒤에는 키가 없다

    error = response.get("error") or {}
    return check("cancelKey: upstream 압축을 취소하면 OperationCanceled 계열 오류로 곧바로 끝남",
                 cancelled is True and again is False and error.get("type") in ("OperationCanceledException", "TaskCanceledException") and elapsed < 5,
                 f"cancel={cancelled}, 오류={error}, {elapsed:.2f}초")


def test_background(engine):
    ui = engine.request("callStatic", type="System.Environment", method="get_CurrentManagedThreadId", args=[])
    pool = engine.request("callStatic", type="System.Environment", method="get_CurrentManagedThreadId", args=[], background=True)
    return check("background: 스레드 풀에서 실행", isinstance(ui, (int, float)) and ui != pool, f"UI {ui}, 백그라운드 {pool}")


def test_value_type(engine):
    label = engine.request("convert", converter="Locale3dsLanguageToLabelConverter", value="KO", valueType="_3DS.Core.Enums.LocaleLanguage")
    plain = engine.request("convert", converter="Locale3dsLanguageToLabelConverter", value="KO")
    return check("convert valueType: 이름 문자열 → enum 값으로 변환기 실행", label == "한국어" and plain == "미선택", f"{label!r} / 타입 없이 {plain!r}")


def test_big_integer(engine):
    title_id = 0x0100F2C0115B6000  # 2^53보다 큰 Switch Title ID
    games = engine.request("create", type="System.Collections.Generic.List`1[[NSW.WPF.ViewModels.GameFile, NSW.WPF]]", args=[])
    context = engine.request("create", type="RomForge.ViewModels.Switch.RepackMainViewModel+BuildContext",
                             args=[games, None, "AmericanEnglish", None, str(title_id)])
    described = engine.request("describe", obj=ref(context))
    value = described["props"].get("OverrideTitleId")
    hex_context = engine.request("create", type="RomForge.ViewModels.Switch.RepackMainViewModel+BuildContext",
                                 args=[games, None, "AmericanEnglish", None, "0x0100F2C0115B6000"])
    hex_value = engine.request("describe", obj=ref(hex_context))["props"].get("OverrideTitleId")
    return check("64비트 정수: 문자열로 보내고 문자열로 돌려받음(정밀도 손실 없음)",
                 value == str(title_id) and hex_value == str(title_id), f"{value!r}, 16진 입력 {hex_value!r}")


def test_bind_callback(engine):
    # code-behind: NormalVM.SourceHash.RequestGdRomLayoutAsync = ShowGdRomLayoutDialogAsync (Func<Task<GdRomHashLayout>>)
    root = engine.request("describe", obj=engine.root)
    patch = engine.request("describe", obj=ref(root["props"]["PatchVM"]))
    normal = engine.request("describe", obj=ref(patch["props"]["NormalVM"]))
    source_hash = ref(normal["props"]["SourceHash"])

    asked = []
    engine.ui_answers["ui.callback"] = lambda params: (asked.append(params), "Cue")[1]
    engine.request("bindCallback", obj=source_hash, prop="RequestGdRomLayoutAsync", name="patch.gdRomLayout")
    delegate = engine.request("describe", obj=source_hash)["props"]["RequestGdRomLayoutAsync"]
    chosen = engine.request("call", obj=ref(delegate), method="Invoke", args=[])

    engine.request("bindCallback", obj=source_hash, prop="RequestGdRomLayoutAsync")  # 이름 없이 → 비우기
    cleared = engine.request("describe", obj=source_hash)["props"]["RequestGdRomLayoutAsync"]
    return check("bindCallback: Func 속성에 앱 처리기를 걸고, 불리면 ui.callback으로 묻고 enum으로 받음",
                 chosen == "Cue" and len(asked) == 1 and asked[0]["name"] == "patch.gdRomLayout" and cleared is None,
                 f"결과 {chosen!r}, 요청 {asked}, 해제 후 {cleared!r}")


def main():
    workdir = tempfile.mkdtemp(prefix="romforge-bridge-")
    engine = Engine(ui_answers={"ui.messageBox": "OK"})
    try:
        engine.root = ref(engine.wait_notification("ready")["root"])
        results = [
            test_exclusive(engine),
            test_cancel_upstream(engine, workdir),
            test_background(engine),
            test_value_type(engine),
            test_big_integer(engine),
            test_bind_callback(engine),
        ]
        print("성공" if all(results) else "실패")
        return 0 if all(results) else 1
    finally:
        engine.close()
        for name in os.listdir(workdir):
            os.remove(os.path.join(workdir, name))
        os.rmdir(workdir)


if __name__ == "__main__":
    sys.exit(main())
