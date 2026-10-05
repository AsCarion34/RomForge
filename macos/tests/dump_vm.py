#!/usr/bin/env python3
"""
엔진에서 upstream ViewModel 하나를 열어 속성·타입·enum 선택지·메서드를 출력한다(화면 작성용).
사용: python3 macos/tests/dump_vm.py PatchVM.NormalVM
      python3 macos/tests/dump_vm.py UtilMainVM.HashVM --items FileItems   (컬렉션 첫 항목의 속성도)
경로는 MainViewModel에서 시작하는 속성 이름을 점으로 잇는다.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from bridge_client import Engine, ref  # noqa: E402


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    items_prop = sys.argv[sys.argv.index("--items") + 1] if "--items" in sys.argv else None

    engine = Engine(ui_answers={"ui.messageBox": "OK"})
    try:
        obj = ref(engine.wait_notification("ready", timeout=30)["root"])
        vm = engine.request("describe", obj=obj)
        for part in [p for p in path.split(".") if p]:
            obj = ref(vm["props"][part])
            vm = engine.request("describe", obj=obj)

        print(f"# {vm['type']}")
        print("## 속성 (이름: 타입 = 현재값)  [S]=설정 가능")
        for name in sorted(vm["props"]):
            value = vm["props"][name]
            mark = "[S]" if name in vm["settable"] else "   "
            print(f"  {mark} {name}: {vm['types'].get(name)} = {json.dumps(value, ensure_ascii=False)[:110]}")
        if vm["enums"]:
            print("## enum 선택지")
            for name, options in vm["enums"].items():
                print(f"  {name}: {options}")
        print("## 메서드")
        print("  " + ", ".join(vm["methods"]))

        if items_prop:
            listing = engine.request("list", obj=ref(vm["props"][items_prop]))
            print(f"## {items_prop}: 항목 {len(listing['items'])}개")
            if listing["items"]:
                first = engine.request("describe", obj=ref(listing["items"][0]))
                print(f"### 첫 항목 {first['type']}")
                for name in sorted(first["props"]):
                    print(f"  {name}: {first['types'].get(name)} = {json.dumps(first['props'][name], ensure_ascii=False)[:100]}")
        return 0
    finally:
        engine.close()


if __name__ == "__main__":
    sys.exit(main())
