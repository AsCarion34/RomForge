# SwiftUI 화면 작성 가이드

RomForge macOS 앱의 탭 화면을 만들 때 따르는 규칙입니다. 전체 구조는 `macos/README.md`를 보세요.

## 구조 한 줄 요약

로직은 엔진에서 돌고 있는 **upstream ViewModel**이 전부 수행합니다. Swift 화면은 ViewModel 속성을 보여 주고, 속성 설정·커맨드 실행·메서드 호출만 합니다. 파일 처리 같은 업무 로직을 Swift에 쓰지 않습니다.

## 파일 규칙

- 각 화면은 `Sources/RomForgeMac/Screens/<그룹>/` 아래에 둡니다. 다른 폴더의 파일은 고치지 않습니다.
- 메인 탭 진입점은 `struct <이름>Screen: View { let vmId: Int }`입니다.
  - 이름: `PatchScreen`, `ConvertScreen`, `SwitchScreen`, `WiiUScreen`, `WiiScreen`, `ThreeDSScreen`, `PSVitaScreen`, `PSPScreen`, `UtilScreen`, `SettingsScreen` (압축 탭은 `Views/CompressView`)
  - `vmId`는 MainViewModel의 해당 속성(PatchVM 등) 객체 번호입니다.
- **모든 파일 첫 줄에 upstream 출처를 적습니다.** upstream이 화면을 바꿨을 때 고칠 Swift 파일을 자동으로 찾는 데 씁니다.
  ```swift
  // upstream: RomForge/Controls/Util/HashTab.xaml(.cs)
  // ViewModel: HashMainViewModel
  ```

## upstream과 같게 맞출 것

- **문구:** 한국어 문구(버튼, 라벨, 툴팁, 안내)는 upstream XAML과 똑같이 씁니다.
- **구성:** 옵션 순서, 묶음, 표 열 구성, 하위 탭 순서를 같게 합니다.
- **아이콘:** XAML의 `Source="/Assets/Images/X.png"` 파일 이름을 그대로 `UpstreamIcon(name: "X.png")`에 씁니다.
- **변환기:** XAML이 쓰는 변환기(LevelToColorConverter 등)는 `engine.converted(...)`로 엔진의 upstream 변환기를 씁니다. Swift로 다시 짜지 않습니다.
- **스타일:** WPF 스타일(색, 그림자, 테두리)은 따라 하지 않습니다. macOS 기본 컨트롤을 씁니다.

### code-behind(.xaml.cs) 동작 옮기기

| upstream code-behind | Swift |
|---|---|
| Drop → `ViewModel.X.AddPaths(paths)` | `.remoteFileList(engine, owner: vm, list: ..., dropMethod: "AddPaths")` 또는 `.dropDestination` + `engine.invoke(vm, "AddPaths", [.strings(paths)])` |
| Delete 키·제거 버튼 → `RemoveItems(selected)` | `.remoteFileList(... removeMethod: "RemoveItems")`. 버튼이면 `engine.invoke(vm, "RemoveItems", [EngineClient.refs(selection)])` |
| `new OpenFileDialog{...}` 후 VM 메서드 호출 | `NSOpenPanel`(같은 필터·다중 선택)로 고른 뒤 같은 VM 메서드 호출 |
| VM 커맨드가 대화상자를 여는 경우 | 그냥 `engine.run(vm, "BrowseXxxCommand")`. 엔진이 SwiftUI 쪽 대화상자를 띄웁니다. |
| 폴더 열기(Process.Start explorer) | `NSWorkspace.shared.activateFileViewerSelecting([url])` 또는 `NSWorkspace.shared.open(url)` |
| URL 열기(Process.Start https://…) | `NSWorkspace.shared.open(URL(string: …)!)` |
| ContextMenu 항목 | `.contextMenu(forSelectionType: Int.self) { ids in … }`로 같은 항목과 동작 |
| code-behind가 upstream 도우미 클래스를 쓰는 경우(예: `new SwitchGameFileImporter(...)`, `SwitchBulkPatchMatcher.MatchFromFolder(...)`) | 로직을 Swift로 옮기지 말고 `engine.create` / `engine.call` / `engine.callStatic`으로 같은 upstream 클래스를 부른다 |
| `ScrollToItemRequested` 같은 화면 전용 이벤트 | 생략 가능 |
| `_cts = new CancellationTokenSource()` → `await Vm.XxxAsync(…, _cts.Token)`, 취소 단추 → `_cts.Cancel()` | `try await engine.callThrowing(vm.id, "XxxAsync", [args], options: CallOptions(cancelKey: key))`, 취소 단추 → `await engine.cancel(key)`. CancellationToken 인자는 생략합니다(엔진이 key의 토큰을 넣음). `catch (OperationCanceledException)`은 `catch let e as EngineError where e.isCancellation` |
| `await Task.Run(() => 무거운 upstream 계산)` | `options: .background`(엔진 스레드 풀에서 실행. 그동안 화면 알림이 멈추지 않음) |
| 단추 연타로 같은 비동기 메서드가 겹치면 안 되는 경우 | `options: CallOptions(exclusive: true)`(실행 중이면 엔진이 "이미 실행 중입니다."로 거절) |
| `PasswordPromptWindow.OpenWithPasswordPromptAsync(path, owner)` | `engine.request("archive.open", ["path": …, "keep": …])` → `{opened, password, entries, archive?}`. keep이면 `archive`를 다 쓰고 `call Dispose` |

## 데이터 접근 API

```swift
@Environment(EngineClient.self) private var engine

ChildVM(id: vmId) { vm in ... }                 // ViewModel을 describe하고 그린다(속성 변경은 자동 반영)
vm["Prop"]?.bool / ?.string / ?.double / ?.int  // 속성 값(JSONValue)
vm.string("Prop")                               // 문자열(없으면 "")
vm.ref("ChildVM")                               // 하위 객체·컬렉션·커맨드 번호
vm.isVisible("XxxVisibility")                   // Visibility 속성이 Visible인지
vm.options("EnumProp")                          // enum 선택지
vm.has("AddPaths")                              // 공개 메서드가 있는지

engine.items(vm, "FileItems")                   // 컬렉션 항목(RemoteObject 배열). 먼저 observeLists로 구독
engine.store.groupBy(listId)                    // upstream이 CollectionViewSource로 묶은 목록의 묶음 기준 속성 이름(항목은 뷰 순서로 온다)
item.string("FileName"), item["Progress"]?.double

engine.bool(vm, "Prop")        // Binding<Bool>
engine.inverseBool(vm, "Prop") // Binding<Bool>(반대)
engine.string(vm, "Prop")      // Binding<String>
engine.double / engine.int     // Binding<Double> / Binding<Int>
engine.choice(vm, "EnumProp")  // Binding<String>(enum 이름)
engine.isChoice(vm, "EnumProp", "Value")   // RadioButton(EnumToBooleanConverter) 자리
engine.selectedItem(vm, "SelectedItem")    // Binding<Int?>(항목 객체 번호)

engine.run(vm, "RunCommand")                 // ICommand 실행(인자: engine.run(vm, "Cmd", .string("x")))
engine.canRun(vm, "RunCommand")              // CanExecute
engine.invoke(vm, "AddPaths", [.strings(paths)])   // 공개 메서드 호출
await engine.call(objId, "Method", [args])      // 반환값이 필요할 때(JSONValue?)
await engine.callStatic("SwitchGameFileListOrganizer", "Reorganize", [EngineClient.ref(listId)])  // upstream 정적 도우미
let helperId = await engine.create("GameFilePatchSyncManager", [EngineClient.ref(listId)])         // upstream 도우미 객체 생성
// 인자: 문자열 .string, 경로 배열 .strings([...]), 객체·컬렉션 EngineClient.ref(id), 콜백(Action<…>) 자리는 .null(엔진이 빈 콜백을 넣음)
// 뒤쪽 선택 인자(기본값 있는 매개변수, CancellationToken)는 생략할 수 있다. 같은 이름 오버로드는 인자 수·타입으로 고른다.
// 2^53을 넘는 정수(Switch Title ID 등)는 10진 문자열 .string("72324500776771584")로 보낸다. 엔진도 그런 값은 문자열로 보낸다.
let result = try await engine.callThrowing(objId, "InstallAsync", [EngineClient.ref(itemId)],
                                           options: CallOptions(exclusive: true, cancelKey: "3ds.install.\(objId)", background: false))
await engine.cancel("3ds.install.\(objId)")                     // 위 호출의 CancellationToken 취소
try await engine.callStaticThrowing("NSW.Core.MetadataReader", "DetectFileType", [...], options: .background)
engine.converted("LevelToColorConverter", vm, "Level")?.color   // upstream 변환기 결과(처음엔 nil)
engine.converted("BoolToImageConverter", vm, "Flag")            // 이미지면 RemoteImage(value:)로 그린다
RemoteImage(value: item["Icon"], size: 32)                      // 엔진 이미지(게임 아이콘 등)
UpstreamIcon(name: "Patch.png", size: 18)                       // upstream PNG 아이콘
```

## 공용 컴포넌트(`Components/`)

- `ToolLayout(vm:lists:logs:) { 본문 } options: { 옵션 }`: 본문 / 옵션 / 로그 배치. `lists`에 구독할 컬렉션 이름을 넣습니다.
- `.observeLists(engine, vm, ["PatchSlots"])`: ToolLayout 밖에서 컬렉션 구독
- `SubTabsView(owner: vm, tabs: [SubTab(title:icon:vmProp:)], selectionProp: "SelectedTabIndex") { index, childId in ... }`
  - upstream ViewModel이 선택 상태를 어떤 속성으로 갖는지(SelectedTabIndex 등) `dump_vm.py`로 확인합니다. 없으면 `selectionProp: nil`로 둡니다.
- `.remoteFileList(engine, owner:list:selection:dropMethod:removeMethod:pathProp:enabled:)`: Table에 드롭, 삭제, Finder 보기, 제거 메뉴를 붙입니다.
- `ExtensionBadge(item:)`, `ProgressCell(item:)`, `DropHint(title:detail:)`
- `OptionCard(title:icon:) { ... }`: upstream OptionBorder 상자
- **Table 셀 주의:** 셀 안에서 `@Environment(EngineClient.self)`를 읽는 뷰(엔진 바인딩 Picker, `RemoteImage`, 화면별 셀 뷰)를 쓰면 셀 끝에 `.cellEnvironment(engine)`을 붙입니다. 행이 지워질 때 SwiftUI가 셀을 환경 없이 한 번 더 갱신해 "No Observable object of type EngineClient" 오류로 앱이 멈추기 때문입니다.
- 버튼(`Buttons.swift`): `IconLabel`(아이콘 + 문구), `IconButton`(code-behind Click), `CommandIconButton`(커맨드 + CanExecute), `RunCancelButton`(NSW.WPF IconButton: 실행 중이면 "취소"), `ToolIconButton`(아이콘만 있는 작은 버튼). 화면 폴더마다 새로 만들지 말고 이것을 씁니다.
- `OutputPathRow(vm:toggleProp:pathProp:browseCommand:toggleTitle:placeholder:)`
- `ToolProgressBar(vm:)`: upstream ToolTabViewModel의 표준 진행 줄(ProgressLabel · ProgressPercent · ProgressSpeed · ProgressTime · ProgressPct 막대)
- `LevelSlider(vm:prop:range:textConverter:colorConverter:)`
- `EnumPicker(vm:prop:labels:style:)`: `.segmented` / `.radio` / `.menu`
- `CommandButton(title:systemImage:vm:command:arg:prominent:)`
- `GenericVMForm(vmId:)`: 자동 생성 화면. 아직 못 옮긴 부분의 임시 대체로만 씁니다.
- `LogListView(listId:owner:)`: 로그(upstream 로그 메뉴: 로그 비우기 = owner의 ClearLog(), 로그 복사). ToolLayout이 자동으로 붙입니다.

부족한 부품이 있으면 공용 파일을 고치지 말고, 자기 폴더 안에 `private` 보조 뷰로 만든 뒤 보고서에 적습니다.

## 도구

```bash
# ViewModel 실제 속성·타입·enum·메서드 확인(경로는 MainViewModel 기준)
python3 macos/tests/dump_vm.py PatchVM.NormalVM
python3 macos/tests/dump_vm.py UtilMainVM.HashVM --items FileItems

# 자기 폴더만 타입 검사(공용 코드 포함). 전체 패키지 빌드나 앱 실행은 하지 않습니다.
macos/scripts/typecheck-screens.sh Patch
```

- 엔진 실행 파일은 이미 빌드되어 있습니다(`RomForge/bin/Release/net8.0/RomForge`). 다시 빌드하지 않습니다.
- git 커밋은 하지 않습니다.
