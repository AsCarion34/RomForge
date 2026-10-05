// upstream: RomForge/Controls/Switch/*.cs(SwitchGameFileImporter, GameFilePatchSyncManager, SwitchGameFileListOrganizer, SwitchBulkPatchMatcher, SwitchPatchDropValidator), NSW.WPF/UI/IconButton.xaml(.cs), NSW.WPF/UI/MessageBoxHelper.cs
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

    /// SwitchTitleListControl/FileManagerControl.RecalcKeyMissingFiles: '키 없음' 항목의 종류를 다시 판별한다.
    static func recalcKeyMissing(_ engine: EngineClient, _ files: [RemoteObject]) async {
        let targets = files.filter { $0["IsKeyMissing"]?.bool == true }
        guard !targets.isEmpty, let keySet = await keySet(engine) else { return }

        for file in targets {
            // upstream: Task.Run(() => MetadataReader.DetectFileType(keySet, path))
            let type = await engine.callStatic("NSW.Core.MetadataReader", "DetectFileType",
                                               [EngineClient.ref(keySet), .string(file.string("FilePath"))], options: .background) ?? .string("?")
            await engine.set(file.id, "FileType", type)
            await engine.describe(file.id)
        }
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

/// code-behind의 MessageBox.Show(text, caption, OK, icon)
@MainActor
enum SwitchAlert {
    static func show(_ text: String, caption: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.messageText = caption
        alert.informativeText = text
        alert.alertStyle = style
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }
}

// MARK: - 화면 수명과 관계없이 유지하는 상태

/// WPF 컨트롤 인스턴스가 들고 있던 상태(GameFiles 등). 하위 탭·메인 탭을 옮겨도 유지되도록 ViewModel 번호별로 둔다.
@MainActor
enum SwitchStore {
    private static var repacks: [Int: SwitchRepackState] = [:]
    private static var fileManagers: [Int: SwitchGameFileList] = [:]

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

/// SwitchTitleListControl·FileManagerControl의 GameFiles(ObservableCollection&lt;GameFile&gt;)와
/// 제목 목록 도우미(GameFilePatchSyncManager, SwitchGameFileImporter)를 엔진에 만들어 둔다.
@MainActor
@Observable
final class SwitchGameFileList {
    private(set) var listId: Int?
    private(set) var patchSyncId: Int?
    private(set) var importerId: Int?
    @ObservationIgnored private var preparing = false

    static let gameFilesType = "System.Collections.ObjectModel.ObservableCollection`1[[NSW.WPF.ViewModels.GameFile, NSW.WPF]]"
    static let supportedExtensions = [".nsp", ".xci", ".nsz", ".xcz"]

    /// importer: SwitchTitleListControl 생성자와 같이 GameFilePatchSyncManager·SwitchGameFileImporter도 만든다.
    func prepare(_ engine: EngineClient, importer: Bool) async {
        guard listId == nil, !preparing else { return }
        preparing = true
        defer { preparing = false }

        guard let list = await engine.create(Self.gameFilesType) else { return }

        if importer {
            guard let sync = await engine.create("RomForge.Controls.Switch.GameFilePatchSyncManager", [EngineClient.ref(list)]) else { return }
            let extensions = await SwitchBridge.extensionSet(engine, Self.supportedExtensions)
            importerId = await engine.create("RomForge.Controls.Switch.SwitchGameFileImporter",
                                             [EngineClient.ref(list), EngineClient.ref(sync), extensions])
            patchSyncId = sync
        }

        listId = list
        await engine.observeList(list)
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

/// 진행 상황(ProgressLabel · ProgressPercent · ProgressSpeed · ProgressTime + ProgressPct 막대)
struct SwitchProgressBlock: View {
    let vm: RemoteObject
    var details = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(vm.string("ProgressLabel"))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if details {
                    Text(vm.string("ProgressPercent")).foregroundStyle(.green)
                    Text(vm.string("ProgressSpeed")).foregroundStyle(.secondary)
                    Text(vm.string("ProgressTime")).foregroundStyle(.green)
                }
            }
            .font(.caption.monospacedDigit())

            ProgressView(value: min(max((vm["ProgressPct"]?.double ?? 0) / 100, 0), 1))
        }
    }
}

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

/// 빈 목록 안내(dropHint): 드래그 아이콘 · 제목 · 설명 · 형식 배지
struct SwitchDropHint: View {
    let title: String
    var detail: String?
    var formats: [String] = ["NSP", "NSZ", "XCI", "XCZ"]
    var icon = "Drag.png"

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

/// 게임 아이콘 + 두 줄 글자(타이틀 열)
struct SwitchTitleCell: View {
    let item: RemoteObject
    var title = "TitleName"
    var subtitle = "TitleID"
    var tooltip = "FilePath"

    var body: some View {
        HStack(spacing: 10) {
            RemoteImage(value: item["Icon"], size: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6))
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
