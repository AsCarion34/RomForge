// upstream: NSW.WPF/UI/IconButton.xaml(.cs), NSW.WPF/UI/MessageBoxHelper.cs
// ViewModel: SwitchMainViewModel 하위 탭 공용(엔진 호출 도우미·보조 뷰)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 엔진 호출 도우미

/// code-behind가 직접 쓰던 upstream 정적 메서드·도우미 객체를 엔진에서 부른다(로직은 엔진이 수행).
@MainActor
enum SwitchBridge {
    /// KeySetProvider.Instance.KeySet(prod.keys가 없으면 nil)
    static func keySet(_ engine: EngineClient) async -> Int? {
        guard let provider = await engine.callStatic("NSW.Core.KeySetProvider", "get_Instance")?.refId else { return nil }
        return await engine.call(provider, "get_KeySet")?.refId
    }

    /// NSW.Core.Properties.Resources 문자열(엔진의 현재 언어). 로직에서 비교하는 값(Status_NoKey 등)은 반드시 여기서 읽는다.
    static func resource(_ engine: EngineClient, _ key: String) async -> String {
        await engine.callStatic("NSW.Core.Properties.Resources", "get_\(key)")?.string ?? ""
    }

    /// Common.Utils.ExpandPaths(paths). 결과(엔진의 IEnumerable 참조)를 그대로 다음 호출 인자로 넘긴다.
    static func expandPaths(_ engine: EngineClient, _ paths: [String]) async -> JSONValue {
        await engine.callStatic("Common.Utils", "ExpandPaths", [.strings(paths)]) ?? .strings(paths)
    }

    /// 엔진 컬렉션(IEnumerable)의 값을 한 번 읽는다(문자열·숫자·객체 참조).
    static func values(_ engine: EngineClient, of list: JSONValue?) async -> [JSONValue] {
        guard let id = list?.refId, let result = try? await engine.request("list", ["obj": .int(id)]) else { return [] }
        return result["items"]?.array ?? []
    }

    /// 객체 참조의 최신 속성
    static func object(_ engine: EngineClient, _ value: JSONValue?) async -> RemoteObject? {
        guard let id = value?.refId else { return nil }
        return await engine.describe(id)
    }

    /// 정적 호출. 실패하면 예외 메시지를 던진다(upstream이 catch해서 메시지 상자에 띄우거나 무시하는 호출).
    static func callStatic(_ engine: EngineClient, _ type: String, _ method: String, _ args: [JSONValue] = []) async throws -> JSONValue {
        try await engine.request("callStatic", ["type": .string(type), "method": .string(method), "args": .array(args)])
    }

    /// 더 쓰지 않는 임시 엔진 객체(KeySet 사본 등)를 놓아준다.
    static func release(_ engine: EngineClient, _ ids: [Int]) async {
        guard !ids.isEmpty else { return }
        _ = try? await engine.request("release", ["objs": .array(ids.map { .int($0) })])
    }

    /// new HashSet<string>(StringComparer.OrdinalIgnoreCase) { … } — 만들지 못하면 대소문자를 구분하는 배열로 대신한다.
    static func extensionSet(_ engine: EngineClient, _ extensions: [String]) async -> JSONValue {
        if let comparer = (try? await callStatic(engine, "System.StringComparer", "get_OrdinalIgnoreCase"))?.refId,
           let set = (try? await engine.request("create", [
               "type": .string("System.Collections.Generic.HashSet`1[[System.String, System.Private.CoreLib]]"),
               "args": .array([EngineClient.ref(comparer)]),
           ]))?.refId {
            for ext in extensions {
                await engine.call(set, "Add", [.string(ext)])
            }
            return EngineClient.ref(set)
        }
        return .strings(extensions)
    }

    /// code-behind가 메서드 그룹을 대리자 인자로 넘기던 자리(예: `BulkPatchMatcher.MatchFromFolder(…, _viewModel.GetExpectedIds)`).
    /// Delegate.CreateDelegate(type, target, method)로 엔진 객체의 공개 메서드를 그 대리자 타입으로 묶는다.
    /// type은 Type.GetType 이름(예: "System.Action").
    static func methodDelegate(_ engine: EngineClient, type: String, target: Int, method: String) async -> JSONValue? {
        guard let delegateType = try? await callStatic(engine, "System.Type", "GetType", [.string(type)]), delegateType.refId != nil,
              let created = try? await callStatic(engine, "System.Delegate", "CreateDelegate",
                                                  [delegateType, EngineClient.ref(target), .string(method)]),
              created.refId != nil
        else { return nil }
        return created
    }

    /// `var tcs = new TaskCompletionSource(); x.Method(…, () => tcs.SetResult()); await tcs.Task;`
    /// 마지막 인자가 완료 콜백(Action onCompleted)인 upstream 메서드를 부르고 콜백이 불릴 때까지 기다린다.
    /// 대리자를 만들지 못하면 빈 콜백으로 부르기만 한다(기다리지 않는다).
    static func callUntilCompleted(_ engine: EngineClient, _ obj: Int, _ method: String, _ args: [JSONValue] = []) async {
        guard let tcs = await engine.create("System.Threading.Tasks.TaskCompletionSource") else {
            await engine.call(obj, method, args + [.null])
            return
        }
        guard let onCompleted = await methodDelegate(engine, type: "System.Action", target: tcs, method: "SetResult") else {
            await release(engine, [tcs])
            await engine.call(obj, method, args + [.null])
            return
        }

        // 실패한 호출(nil)은 콜백이 불리지 않으므로 기다리지 않는다.
        if await engine.call(obj, method, args + [onCompleted]) != nil {
            await engine.call(tcs, "get_Task")
        }
        await release(engine, [tcs] + [onCompleted.refId].compactMap { $0 })
    }

    /// ToolTabViewModel.AppendLog(msg, level)
    static func appendLog(_ engine: EngineClient, _ vmId: Int, _ message: String, _ level: String = "Info") async {
        await engine.call(vmId, "AppendLog", [.string(message), .string(level)])
    }

    /// RomForge.Core.Services.SoundPlayer.PlayErrorAsync()
    static func playError(_ engine: EngineClient) async {
        await engine.callStatic("RomForge.Core.Services.SoundPlayer", "PlayErrorAsync")
    }

    /// `ViewModel.AppendLog(Res.X, LogLevel.Error); await SoundPlayer.PlayErrorAsync();`
    static func logError(_ engine: EngineClient, _ vmId: Int, resource key: String) async {
        await appendLog(engine, vmId, await resource(engine, key), "Error")
        await playError(engine)
    }

    /// PasswordPromptWindow.OpenWithPasswordPromptAsync: 필요하면 비밀번호를 묻고 압축을 연다.
    /// 엔진 요청 archive.open이 upstream과 같은 경로(macos/Overrides의 PasswordPromptWindow)로 처리한다.
    /// keep이면 연 압축(opened.Value.Archive)을 돌려주고, 다 쓰면 call Dispose로 닫는다. 아니면 엔진이 바로 닫는다.
    static func openArchive(_ engine: EngineClient, _ path: String, keep: Bool = false) async throws -> (opened: Bool, password: JSONValue, archive: JSONValue?) {
        let result = try await engine.request("archive.open", ["path": .string(path), "keep": .bool(keep)])
        return (result["opened"]?.bool ?? false, result["password"] ?? .null, result["archive"])
    }

    /// NSW.WPF.UI.MessageBoxHelper.ShowInfo / ShowError(엔진의 메시지 상자 → SwiftUI 알림)
    static func showInfo(_ engine: EngineClient, _ message: String) async {
        await engine.callStatic("NSW.WPF.UI.MessageBoxHelper", "ShowInfo", [.string(message)])
    }

    static func showError(_ engine: EngineClient, _ message: String) async {
        await engine.callStatic("NSW.WPF.UI.MessageBoxHelper", "ShowError", [.string(message)])
    }

    /// 선택한 항목 번호를 목록 순서대로
    static func ordered(_ ids: Set<Int>, in items: [RemoteObject]) -> [Int] {
        items.map(\.id).filter(ids.contains)
    }

    static func errorMessage(_ error: Error) -> String {
        (error as? EngineError)?.message ?? error.localizedDescription
    }
}

// MARK: - 대화상자·Finder

@MainActor
enum SwitchPanels {
    /// "Switch 파일 (*.nsp;*.xci;*.nsz;*.xcz)" — WPF 대화상자의 기본(첫) 필터
    static let switchExtensions = ["nsp", "xci", "nsz", "xcz"]

    /// OpenFileDialog. extensions가 nil이면 모든 파일
    static func openFiles(title: String, extensions: [String]? = nil, multiple: Bool = false) -> [String] {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = multiple
        if let extensions {
            panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        }
        return panel.runModal() == .OK ? panel.urls.map(\.path) : []
    }

    /// FolderBrowserDialog / OpenFolderDialog(설명을 제목으로)
    static func openFolder(title: String) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    /// TxtOutputPath_PreviewDragOver / TxtOutputPath_Drop: 끌어다 놓은 첫 항목이 폴더일 때만 받는다
    /// (PreviewDragOver가 폴더가 아니면 DragDropEffects.None으로 막는다).
    static func droppedFolder(_ urls: [URL]) -> String? {
        guard let path = urls.first?.path else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return path
    }

    /// NSW.WPF.Services.ProcessExtensions.OpenFolder: 폴더가 있으면 연다.
    static func showFolder(_ path: String?) {
        var isDirectory: ObjCBool = false
        guard let path, !path.isEmpty, FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// 파일이 있는 폴더(Path.GetDirectoryName(file).OpenFolder())
    static func showContainingFolder(_ file: String) {
        showFolder((file as NSString).deletingLastPathComponent)
    }

    static func openURL(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

// MARK: - 화면 수명과 관계없이 유지하는 상태

/// WPF 컨트롤 인스턴스가 들고 있던 상태(GameFiles 등). 하위 탭·메인 탭을 옮겨도 유지되도록 ViewModel 번호별로 둔다.
@MainActor
enum SwitchStore {
    private static var repacks: [Int: SwitchRepackState] = [:]
    private static var fileManagers: [Int: SwitchGameFileList] = [:]
    private static var splits: [Int: SwitchSplitState] = [:]

    static func repack(_ vmId: Int) -> SwitchRepackState {
        if let state = repacks[vmId] { return state }
        let state = SwitchRepackState()
        repacks[vmId] = state
        return state
    }

    static func fileManager(_ vmId: Int) -> SwitchGameFileList {
        if let list = fileManagers[vmId] { return list }
        let list = SwitchGameFileList()
        fileManagers[vmId] = list
        return list
    }

    static func split(_ vmId: Int) -> SwitchSplitState {
        if let state = splits[vmId] { return state }
        let state = SwitchSplitState()
        splits[vmId] = state
        return state
    }
}

/// RepackTab(titleList, langTab, SyncAll의 취소 토큰)
@MainActor
@Observable
final class SwitchRepackState {
    let files = SwitchGameFileList()
    let language = SwitchLanguageState()
    var innerTab = 0
    @ObservationIgnored var syncTask: Task<Void, Never>?
}

/// SplitFileListControl 첫 열 머리글 CheckBox(IsChecked="True", 바인딩 없음)
@MainActor
@Observable
final class SwitchSplitState {
    var allChecked = true
}

/// TitleListControl(리팩)·FileManagerControl(병합·버전 무시)의 GameFiles(ObservableCollection&lt;GameFile&gt;)를 엔진에 만들어 둔다.
/// TitleListControl은 생성자에서 `new TitleListViewModel(SupportedExtensions)`를 만들고 그 GameFiles를 쓴다.
@MainActor
@Observable
final class SwitchGameFileList {
    private(set) var listId: Int?
    /// TitleListControl의 _viewModel(RomForge.ViewModels.Switch.TitleListViewModel). FileManagerControl이면 nil
    private(set) var titleVMId: Int?
    @ObservationIgnored private var preparing = false

    static let gameFilesType = "System.Collections.ObjectModel.ObservableCollection`1[[NSW.WPF.ViewModels.GameFile, NSW.WPF]]"
    static let supportedExtensions = [".nsp", ".xci", ".nsz", ".xcz"]

    /// SupportedExtensions.Contains(Path.GetExtension(path)) — OrdinalIgnoreCase
    static func supports(_ path: String) -> Bool {
        supportedExtensions.contains("." + (path as NSString).pathExtension.lowercased())
    }

    /// titleList: TitleListControl()처럼 TitleListViewModel을 만든다. 아니면 FileManagerControl.GameFiles만 만든다.
    func prepare(_ engine: EngineClient, titleList: Bool) async {
        guard listId == nil, !preparing else { return }
        preparing = true
        defer { preparing = false }

        if titleList {
            let extensions = await SwitchBridge.extensionSet(engine, Self.supportedExtensions)
            guard let vmId = await engine.create("RomForge.ViewModels.Switch.TitleListViewModel", [extensions]),
                  let vm = await engine.describe(vmId), let list = vm.ref("GameFiles") else { return }
            titleVMId = vmId
            listId = list
        } else {
            guard let list = await engine.create(Self.gameFilesType) else { return }
            listId = list
        }

        await engine.observeList(listId)
    }

    func items(_ engine: EngineClient) -> [RemoteObject] {
        engine.store.items(listId).compactMap { engine.store.object($0.refId) }
    }

    /// 방금 바꾼 속성을 바로 써야 할 때 엔진에서 항목을 다시 읽는다.
    func refreshedItems(_ engine: EngineClient) async -> [RemoteObject] {
        guard let listId else { return [] }
        await engine.observeList(listId)

        var result: [RemoteObject] = []
        for value in engine.store.items(listId) {
            if let id = value.refId, let item = await engine.describe(id) { result.append(item) }
        }
        return result
    }
}

// MARK: - 보조 뷰

/// 배경·글자 색이 있는 배지(TypeBackground/TypeForeground, ExtensionBackground/ExtensionForeground)
struct SwitchBadge: View {
    let text: String
    var background: Color?
    var foreground: Color?

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(foreground ?? .primary)
            .background(background ?? Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// 빈 목록 안내(dropHint): 안내 아이콘 · 제목 · 설명 · 형식 배지
struct SwitchDropHint: View {
    let title: String
    var detail: String?
    var formats: [String] = ["NSP", "NSZ", "XCI", "XCZ"]
    var icon = "Info.png"

    var body: some View {
        VStack(spacing: 6) {
            UpstreamIcon(name: icon, size: 28)
            Text(title).font(.headline)
            if let detail {
                Text(detail).foregroundStyle(.orange)
            }
            HStack(spacing: 6) {
                ForEach(formats, id: \.self) { SwitchBadge(text: $0) }
            }
        }
        .multilineTextAlignment(.center)
        .padding()
        .allowsHitTesting(false)
    }
}

/// 게임 아이콘 + 두 줄 글자(타이틀 열). showsIcon이 false면 아이콘 칸을 접는다(SplitRow IsChild).
struct SwitchTitleCell: View {
    let item: RemoteObject
    var title = "TitleName"
    var subtitle = "TitleID"
    var tooltip = "FilePath"
    var showsIcon = true

    var body: some View {
        HStack(spacing: 10) {
            if showsIcon {
                RemoteImage(value: item["Icon"], size: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.string(title))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .help(item.string(tooltip))
                Text(item.string(subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 항목의 출력 형식 콤보(AvailableFormats / SelectedTargetFormat)
struct SwitchFormatPicker: View {
    @Environment(EngineClient.self) private var engine
    let item: RemoteObject

    var body: some View {
        let listId = item.ref("AvailableFormats")
        let current = item.string("SelectedTargetFormat")
        let loaded = engine.store.items(listId).compactMap(\.string)
        let formats = loaded.isEmpty ? [current] : loaded

        Picker("", selection: engine.string(item, "SelectedTargetFormat")) {
            ForEach(formats, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .frame(width: 84)
        .task(id: listId) { await engine.observeList(listId) }
    }
}

/// 읽기 전용 TextBox(IsReadOnly=True): 선택·복사만 된다.
struct SwitchReadOnlyField: View {
    let text: String

    var body: some View {
        Text(text.isEmpty ? " " : text)
            .textSelection(.enabled)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.4)))
    }
}

/// 경로 TextBox(빈 칸이면 안내 문구 — …HintVisibility 자리)
struct SwitchPathField: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject
    let prop: String
    let hint: String

    var body: some View {
        TextField(hint, text: engine.string(vm, prop))
            .textFieldStyle(.roundedBorder)
            .help(vm.string(prop))
    }
}

extension View {
    /// TxtOutputPath_PreviewDragOver / TxtOutputPath_Drop: 폴더를 끌어다 놓으면 경로 속성(prop)에 넣는다.
    func switchFolderDrop(_ engine: EngineClient, _ vm: RemoteObject, _ prop: String) -> some View {
        dropDestination(for: URL.self) { urls, _ in
            guard let folder = SwitchPanels.droppedFolder(urls) else { return false }
            engine.string(vm, prop).wrappedValue = folder
            return true
        }
    }
}

/// MergeTab·SplitTab 출력 폴더 줄: [경로(폴더 드래그)] [출력 폴더 선택].
/// btnWorkSpace(OpenWorkSpaceCommand)는 upstream에서 그림이 빠져 크기가 없는(보이지 않는) 단추라 옮기지 않는다.
struct SwitchOutputFolderRow: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    var body: some View {
        HStack(spacing: 5) {
            SwitchPathField(vm: vm, prop: "OutputPath", hint: "출력 폴더를 드래그하거나 선택하세요")
            // Res.ToolTip_BrowseOutput
            ToolIconButton(icon: "AddFolder.png", help: "출력 폴더 선택") {
                // BtnBrowseOutput_Click: VistaFolderBrowserDialog(Res.Hint_SelectOutput)
                if let folder = SwitchPanels.openFolder(title: "출력 폴더를 선택하세요") {
                    engine.string(vm, "OutputPath").wrappedValue = folder
                }
            }
        }
        .switchFolderDrop(engine, vm, "OutputPath")
    }
}

/// RadioButton(Content + ToolTip). SwiftUI 라디오 묶음은 단추마다 툴팁을 달 수 없어 AppKit 라디오 단추를 쓴다.
struct SwitchRadioButton: NSViewRepresentable {
    let title: String
    var help: String?
    let isOn: Bool
    let select: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(radioButtonWithTitle: title, target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        button.title = title
        button.toolTip = help
        button.state = isOn ? .on : .off
        button.isEnabled = context.environment.isEnabled
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SwitchRadioButton

        init(_ parent: SwitchRadioButton) { self.parent = parent }

        @objc func clicked(_ sender: NSButton) {
            sender.state = .on
            parent.select()
        }
    }
}

/// WPF CheckBox(IsChecked: bool?, IsThreeState=False). null이면 '일부 선택'으로 그리고,
/// 누르면 ToggleButton.OnToggle처럼 true·null → false, false → true로 바꾼다.
struct SwitchCheckbox: NSViewRepresentable {
    let value: Bool?
    var help: String?
    let toggle: (Bool) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        button.allowsMixedState = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        button.state = value.map { $0 ? .on : .off } ?? .mixed
        button.toolTip = help
        button.isEnabled = context.environment.isEnabled
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SwitchCheckbox

        init(_ parent: SwitchCheckbox) { self.parent = parent }

        @objc func clicked(_ sender: NSButton) {
            let next = parent.value == false
            sender.state = next ? .on : .off
            parent.toggle(next)
        }
    }
}

/// ListViewColumnSorter 자리: 머리글(Tag) 속성 값으로 화면에서만 정렬한다(원본 컬렉션 순서는 그대로).
struct SwitchColumnSort: SortComparator {
    var prop: String
    var order: SortOrder = .forward

    func compare(_ lhs: RemoteObject, _ rhs: RemoteObject) -> ComparisonResult {
        let result = MainActor.assumeIsolated { Self.compareValues(lhs[prop], rhs[prop]) }
        switch (order, result) {
        case (.reverse, .orderedAscending): return .orderedDescending
        case (.reverse, .orderedDescending): return .orderedAscending
        default: return result
        }
    }

    private static func compareValues(_ a: JSONValue?, _ b: JSONValue?) -> ComparisonResult {
        if let x = a?.double, let y = b?.double {
            return x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
        }
        return (a?.string ?? "").localizedCompare(b?.string ?? "")
    }

    static func apply(_ order: [SwitchColumnSort], to items: [RemoteObject]) -> [RemoteObject] {
        order.isEmpty ? items : items.sorted(using: order)
    }
}

/// 드래그해서 꺼낼 PNG 임시 파일(ImgGame/ImgCover_MouseLeftButtonDown의 DoDragDrop 자리)
@MainActor
enum SwitchImageDrag {
    static func provider(_ image: NSImage?, fileName: String) -> NSItemProvider {
        guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return NSItemProvider() }

        let invalid = CharacterSet(charactersIn: "<>:\"/\\|?*").union(.controlCharacters)
        let safeName = String(fileName.unicodeScalars.map { invalid.contains($0) ? "_" : Character($0) })
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(safeName)

        do {
            try png.write(to: url)
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        } catch {
            return NSItemProvider()
        }
    }
}
