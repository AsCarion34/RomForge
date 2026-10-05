#!/usr/bin/env python3
"""
엔진(stdio 브리지)을 SwiftUI 앱 대신 구동하는 테스트 클라이언트.
엔진 프로토콜은 macos/Engine/BridgeHost.cs 주석을 참고한다.
"""
import json
import os
import queue
import subprocess
import threading
import time

ENGINE = os.environ.get("ROMFORGE_ENGINE") or os.path.join(os.path.dirname(__file__), "..", "..", "RomForge", "bin", "Release", "net8.0", "RomForge")


class Engine:
    def __init__(self, path=ENGINE, ui_answers=None, verbose=False):
        env = dict(os.environ)
        env.setdefault("DOTNET_ROOT", os.path.expanduser("~/.dotnet"))
        self.proc = subprocess.Popen(
            [os.path.abspath(path)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, env=env, bufsize=0)
        self.notifications = queue.Queue()
        self.responses = {}
        self.cond = threading.Condition()
        self.next_id = 1
        self.ui_answers = ui_answers or {}
        self.verbose = verbose
        self.stderr_lines = []
        self.stdout_noise = []
        threading.Thread(target=self._read_stdout, daemon=True).start()
        threading.Thread(target=self._read_stderr, daemon=True).start()

    def _read_stderr(self):
        for raw in self.proc.stderr:
            line = raw.decode("utf-8", "replace").rstrip()
            self.stderr_lines.append(line)
            if self.verbose:
                print("  [stderr]", line)

    def _read_stdout(self):
        for raw in self.proc.stdout:
            try:
                msg = json.loads(raw.decode("utf-8"))
            except ValueError:
                # 프로토콜이 아닌 출력이 stdout에 섞였다(엔진 버그). 기록만 하고 계속 읽는다.
                self.stdout_noise.append(raw.decode("utf-8", "replace").rstrip())
                print("  [stdout 오염]", self.stdout_noise[-1][:120])
                continue
            if "method" in msg and "id" in msg:          # 엔진 → 앱 요청(대화상자 등)
                self._answer_ui(msg)
            elif "method" in msg:                          # 알림
                self.notifications.put(msg)
            else:                                          # 응답
                with self.cond:
                    self.responses[msg["id"]] = msg
                    self.cond.notify_all()

    def _answer_ui(self, msg):
        method = msg["method"]
        answer = self.ui_answers.get(method)
        result = answer(msg["params"]) if callable(answer) else answer
        print(f"  [ui] {method} {json.dumps(msg['params'], ensure_ascii=False)} -> {result!r}")
        self._send({"id": msg["id"], "result": result})

    def _send(self, obj):
        self.proc.stdin.write((json.dumps(obj, ensure_ascii=False) + "\n").encode("utf-8"))
        self.proc.stdin.flush()

    def request(self, rpc_method, timeout=60, **params):
        rid = self.next_id
        self.next_id += 1
        self._send({"id": rid, "method": rpc_method, "params": params})
        deadline = time.time() + timeout
        with self.cond:
            while rid not in self.responses:
                left = deadline - time.time()
                if left <= 0:
                    raise TimeoutError(rpc_method)
                self.cond.wait(left)
            msg = self.responses.pop(rid)
        if "error" in msg:
            raise RuntimeError(f"{rpc_method}: {msg['error']}")
        return msg["result"]

    def wait_notification(self, method, timeout=60):
        deadline = time.time() + timeout
        while True:
            left = deadline - time.time()
            if left <= 0:
                raise TimeoutError(method)
            msg = self.notifications.get(timeout=left)
            if msg["method"] == method:
                return msg["params"]

    def close(self):
        try:
            self.proc.stdin.close()
            self.proc.wait(timeout=10)
        except Exception:
            self.proc.kill()


def ref(value):
    """{"$obj":id} 같은 참조에서 번호를 꺼낸다."""
    for key in ("$obj", "$list", "$cmd", "$image"):
        if isinstance(value, dict) and key in value:
            return value[key]
    raise ValueError(f"참조가 아닙니다: {value}")
