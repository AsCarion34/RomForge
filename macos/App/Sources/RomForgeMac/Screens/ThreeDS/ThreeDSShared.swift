// upstream: RomForge/Controls/3DS/MainTab.xaml, InstallMainTab.xaml, InstallTab.xaml(.cs), InstalledTitlesTab.xaml(.cs), ConverterTab.xaml(.cs), DecryptorTab.xaml(.cs) 공통 부분(하위 탭, 표 셀, 목록 드롭·삭제·메뉴, 정렬, 대화상자)
// ViewModel: _3DSMainViewModel, InstallerMainViewModel, ConverterMainViewModel, DecryptorMainViewModel, TitleViewModel, _3DSFileItem, DecryptorFileItem
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 하위 탭

/// 선택 속성이 없는 하위 탭(InstallMainTab의 내부 TabControl)의 선택을 화면이 다시 만들어져도 기억한다.
@MainActor private var threeDSTabMemory: [String: Int] = [:]

/// upstream TabControl 자리. 공용 SubTabsView와 같지만 TabItem의 IsEnabled="{Binding IsIdle}"를 따라
/// 작업 중에는 하위 탭을 바꿀 수 없다.
struct ThreeDSTabs<Content: View>: View {
    @Environment(EngineClient.self) private var engine
    let owner: RemoteObject?
    let tabs: [SubTab]
    var selectionProp: String?
    var memoryKey: String?
    var enabled: Bool
    let content: (_ index: Int, _ childId: Int?) -> Content

    @State private var selected: Int

    init(owner: RemoteObject?, tabs: [SubTab], selectionProp: String? = nil, memoryKey: String? = nil, enabled: Bool = true,
         @ViewBuilder content: @escaping (_ index: Int, _ childId: Int?) -> Content) {
        self.owner = owner
        self.tabs = tabs
        self.selectionProp = selectionProp
        self.memoryKey = memoryKey
        self.enabled = enabled
        self.content = content

        let initial = selectionProp.flatMap { owner?[$0]?.int } ?? memoryKey.flatMap { threeDSTabMemory[$0] } ?? 0
        _selected = State(initialValue: tabs.indices.contains(initial) ? initial : 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selected) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    Text(tab.title).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            let childId = tabs.indices.contains(selected) ? owner?.ref(tabs[selected].vmProp) : nil
            content(selected, childId)
                .id(selected)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: childId) { if let childId { await engine.describe(childId) } }
        }
        .onChange(of: ownerSelection) { _, index in
            if let index, tabs.indices.contains(index), index != selected { selected = index }
        }
        .onChange(of: selected) { _, index in
            if let memoryKey { threeDSTabMemory[memoryKey] = index }
            guard let owner, let selectionProp, owner.props[selectionProp] != nil, owner[selectionProp]?.int != index else { return }
            engine.int(owner, selectionProp).wrappedValue = index
        }
    }

    private var ownerSelection: Int? { selectionProp.flatMap { owner?[$0]?.int } }
}

/// 하위 객체(RomInfo 등)를 describe한 뒤 그린다. 공용 ChildVM과 달리 불러오는 동안은 비워 둔다.
struct ThreeDSDescribed<Content: View>: View {
    @Environment(EngineClient.self) private var engine
    let id: Int?
    @ViewBuilder let content: (RemoteObject) -> Content

    var body: some View {
        if let id, let object = engine.store.object(id) {
            content(object)
        } else {
            Color.clear
                .frame(width: 1, height: 1)
                .task(id: id) { if let id { await engine.describe(id) } }
        }
    }
}

// MARK: - 입력 칸

/// TextBox Text="{Binding Prop, UpdateSourceTrigger=PropertyChanged}" (MaxLength 선택).
/// 입력할 때마다 ViewModel에 보내되, 엔진이 늦게 돌려주는 이전 값(내가 보낸 값의 메아리)으로 입력 중인 글자를 덮어쓰지 않는다.
/// 드롭·찾아보기처럼 ViewModel이 다른 값으로 바뀌면 바로 따른다.
struct ThreeDSTextField: View {
    @Environment(EngineClient.self) private var engine
    let title: String
    let vm: RemoteObject
    let prop: String
    var maxLength: Int?

    @State private var text = ""
    @State private var sent: [String] = []

    var body: some View {
        TextField(title, text: $text)
            .onAppear(perform: reload)
            .onChange(of: vm.id) { _, _ in reload() }
            .onChange(of: text) { _, value in
                if let maxLength, value.utf16.count > maxLength {
                    var limited = value
                    while limited.utf16.count > maxLength { limited.removeLast() }
                    text = limited
                    return
                }
                // 아직 돌아오지 않은 마지막 값(없으면 ViewModel 값)과 같으면 보낼 것이 없다.
                guard value != (sent.last ?? vm.string(prop)) else { return }
                sent.append(value)
                let id = vm.id, prop = prop
                Task { await engine.set(id, prop, .string(value)) }
            }
            .onChange(of: vm.string(prop)) { _, value in
                if let index = sent.lastIndex(of: value) {
                    // 내가 보낸 값이 돌아왔다. 그보다 앞서 보낸 값은 더 기다리지 않는다.
                    sent.removeFirst(index + 1)
                    if sent.isEmpty, value != text { text = value }
                    return
                }
                // 드롭·찾아보기 등 ViewModel 쪽 변경
                sent.removeAll()
                if value != text { text = value }
            }
    }

    private func reload() {
        sent.removeAll()
        text = vm.string(prop)
    }
}

// MARK: - 버튼·안내

/// 컨텍스트 메뉴 항목(upstream MenuItem.Icon). 메뉴는 Image만 그리므로 크기를 맞춘 NSImage를 쓴다.
struct ThreeDSMenuLabel: View {
    let title: String
    let icon: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            UpstreamAssets.menuImage(icon)
        }
    }
}

/// 빈 목록 안내(upstream HintVisibility 상자: drag.png, 안내 문구, 형식 배지)
struct ThreeDSHint: View {
    var icon = "drag.png"
    var iconSize: CGFloat = 28
    let title: String
    var detail: String?
    var badges: [String] = []

    var body: some View {
        VStack(spacing: 8) {
            UpstreamIcon(name: icon, size: iconSize)
            Text(title).font(.headline)
            if let detail {
                Text(detail).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            if !badges.isEmpty {
                HStack(spacing: 6) {
                    ForEach(badges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

// MARK: - 표 셀

/// 타이틀 열: 아이콘 + 게임명 + 배급사(툴팁은 파일 경로)
struct ThreeDSTitleCell: View {
    let item: RemoteObject
    var pathTooltip = true

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(value: item["Icon"], size: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.string("ShortDescription"))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(item.string("Publisher"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 4)
        .help(pathTooltip ? item.string("FilePath") : "")
    }
}

/// 종류 열(TypeLabel, 배경 TypeBadgeColor)
struct ThreeDSTypeBadge: View {
    let item: RemoteObject

    var body: some View {
        Text(item.string("TypeLabel"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(item["TypeBadgeColor"]?.color ?? .gray, in: RoundedRectangle(cornerRadius: 4))
            .frame(maxWidth: .infinity)
    }
}

/// 제품 코드 열(ProductCode + TitleId)
struct ThreeDSCodeCell: View {
    let item: RemoteObject

    var body: some View {
        VStack(spacing: 0) {
            Text(item.string("ProductCode")).foregroundStyle(.secondary)
            Text(item.string("TitleId")).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 지역 열: ProductCode에 upstream RegionToImageConverter, 툴팁 Region
struct ThreeDSRegionCell: View {
    @Environment(EngineClient.self) private var engine
    let item: RemoteObject

    var body: some View {
        RemoteImage(value: engine.converted("RegionToImageConverter", item, "ProductCode"), size: 24)
            .help(item.string("Region"))
            .frame(maxWidth: .infinity)
    }
}

/// 암호화 열: Crypto에 upstream LockIconConverter
struct ThreeDSLockCell: View {
    @Environment(EngineClient.self) private var engine
    let item: RemoteObject

    var body: some View {
        RemoteImage(value: engine.converted("LockIconConverter", item, "Crypto"), size: 24)
            .frame(maxWidth: .infinity)
    }
}

/// 입력 형식 배지(Extension, 배경 ExtensionBackground). upstream은 밝은 배경에 어두운 글자를 쓴다.
struct ThreeDSExtensionBadge: View {
    let item: RemoteObject

    var body: some View {
        Text(item.string("Extension"))
            .font(.caption.weight(.bold))
            .foregroundStyle(Color(white: 0.07))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(item["ExtensionBackground"]?.color ?? .gray, in: RoundedRectangle(cornerRadius: 4))
            .frame(maxWidth: .infinity)
    }
}

/// 진행률 열(ProgressBar + "{텍스트}%")
struct ThreeDSProgressCell: View {
    let item: RemoteObject
    var textProp = "Progress"

    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: min(max((item["Progress"]?.double ?? 0) / 100, 0), 1))
            Text("\(item[textProp]?.string ?? "0")%")
                .font(.caption.monospacedDigit().weight(.bold))
                .frame(minWidth: 34, alignment: .trailing)
        }
    }
}

// MARK: - 목록 동작

/// ListViewColumnSorter 자리: 헤더 Tag(속성 이름)로 화면의 정렬만 바꾼다(ViewModel 순서는 그대로).
struct ThreeDSColumnSort: SortComparator {
    let key: String
    var order: SortOrder = .forward

    init(_ key: String) { self.key = key }

    func compare(_ lhs: RemoteObject, _ rhs: RemoteObject) -> ComparisonResult {
        let result = MainActor.assumeIsolated { Self.compareValues(lhs[key], rhs[key]) }
        guard order == .reverse else { return result }
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    private static func compareValues(_ a: JSONValue?, _ b: JSONValue?) -> ComparisonResult {
        switch (a, b) {
        case let (.number(x)?, .number(y)?):
            return x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
        case let (.bool(x)?, .bool(y)?):
            return x == y ? .orderedSame : (x ? .orderedDescending : .orderedAscending)
        default:
            return (a?.string ?? "").localizedCompare(b?.string ?? "")
        }
    }
}

/// upstream ListView + code-behind: Drop, Delete 키, 컨텍스트 메뉴("폴더 열기 / 선택 삭제 / 전체 삭제").
/// 동작(ViewModel 메서드 호출)은 화면마다 다르므로 클로저로 받는다.
struct ThreeDSListBehavior: ViewModifier {
    @Binding var selection: Set<Int>
    var enabled: Bool
    /// 화면 순서의 항목들(“첫 선택 항목”을 고를 때)
    let rows: [RemoteObject]
    let drop: ([String]) -> Void
    let remove: (Set<Int>) -> Void
    let clear: () -> Void

    func body(content: Content) -> some View {
        content
            .disabled(!enabled)
            .dropDestination(for: URL.self) { urls, _ in
                guard enabled, !urls.isEmpty else { return false }
                drop(urls.map(\.path))
                return true
            }
            .onDeleteCommand {
                guard enabled, !selection.isEmpty else { return }
                remove(selection)
                selection.removeAll()
            }
            .contextMenu(forSelectionType: Int.self) { ids in
                // LvFiles_ContextMenuOpening: 선택이 없으면 메뉴를 열지 않는다.
                if !ids.isEmpty {
                    Button { openFolder(ids) } label: { ThreeDSMenuLabel(title: "폴더 열기", icon: "AddFolder.png") }
                    Divider()
                    Button {
                        remove(ids)
                        selection.subtract(ids)
                    } label: { ThreeDSMenuLabel(title: "선택 삭제", icon: "Delete.png") }
                    Button {
                        clear()
                        selection.removeAll()
                    } label: { ThreeDSMenuLabel(title: "전체 삭제", icon: "Clear.png") }
                }
            }
    }

    /// MenuItem_OpenFolder_Click: 첫 선택 항목 FilePath의 폴더를 연다(Path.GetDirectoryName → OpenFolder).
    private func openFolder(_ ids: Set<Int>) {
        guard let item = rows.first(where: { ids.contains($0.id) }) else { return }
        let path = item.string("FilePath")
        guard !path.isEmpty else { return }
        let directory = (path as NSString).deletingLastPathComponent
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue {
            NSWorkspace.shared.open(URL(fileURLWithPath: directory, isDirectory: true))
        }
    }
}

/// 변환·복호화 탭 하단(파일 추가 / 폴더 추가 / 선택 삭제 / 전체 삭제 … 시작 / 취소).
/// 왼쪽 버튼은 code-behind Click, 오른쪽은 RunCommand / CancelCommand.
struct ThreeDSListFooter: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject
    /// IsConverting / IsDecrypting
    let busy: Bool
    let addFiles: () -> Void
    let addFolder: () -> Void
    let removeSelected: () -> Void
    let clearAll: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Group {
                Button(action: addFiles) { IconLabel(title: "파일 추가", icon: "AddFile.png") }
                Button(action: addFolder) { IconLabel(title: "폴더 추가", icon: "AddFolder.png") }
                Button(action: removeSelected) { IconLabel(title: "선택 삭제", icon: "Delete.png") }
                Button(action: clearAll) { IconLabel(title: "전체 삭제", icon: "Clear.png") }
            }
            .disabled(busy)

            Spacer()

            Button { engine.run(vm, "RunCommand") } label: { IconLabel(title: "시작", icon: "Run.png") }
                .buttonStyle(.borderedProminent)
                .disabled(busy || !engine.canRun(vm, "RunCommand"))
            Button { engine.run(vm, "CancelCommand") } label: { IconLabel(title: "취소", icon: "Cancel.png") }
                .disabled(!busy || !engine.canRun(vm, "CancelCommand"))
        }
        .padding(8)
    }
}

// MARK: - 엔진 호출

@MainActor
enum ThreeDSBridge {
    /// 공개 메서드를 끝까지 기다려 부른다. 실패하면 upstream 예외를 돌려준다(code-behind의 try/catch 자리).
    static func call(_ engine: EngineClient, _ obj: Int, _ method: String, _ args: [JSONValue] = []) async -> Result<JSONValue, Error> {
        do {
            return .success(try await engine.request("call", ["obj": .int(obj), "method": .string(method), "args": .array(args)]))
        } catch {
            return .failure(error)
        }
    }

    /// code-behind의 Vm.AppendLog(msg, LogLevel.X)
    static func log(_ engine: EngineClient, _ vm: RemoteObject?, _ message: String, _ level: String) {
        engine.invoke(vm, "AppendLog", [.string(message), .string(level)])
    }
}

// MARK: - 파일·대화상자

@MainActor
enum ThreeDSDialogs {
    /// Microsoft.Win32.OpenFileDialog{Title, Filter, Multiselect}. 엔진 대화상자와 같은 처리(WPF 필터 해석)를 쓴다.
    static func openFiles(title: String, filter: String?, multiple: Bool) -> [String] {
        var params: [String: JSONValue] = ["title": .string(title), "multiselect": .bool(multiple)]
        if let filter { params["filter"] = .string(filter) }
        return UiHostHandler.handle("ui.openFile", .object(params)).array?.compactMap(\.string) ?? []
    }

    /// Ookii VistaFolderBrowserDialog{Description, UseDescriptionForTitle}
    static func openFolder(title: String) -> String? {
        UiHostHandler.handle("ui.openFolder", .object(["title": .string(title)])).array?.first?.string
    }

    /// Microsoft.Win32.SaveFileDialog{Title, Filter, FileName}. WPF처럼 필터의 확장자를 붙인다(AddExtension).
    static func saveFile(title: String, filter: String, fileName: String) -> String? {
        let panel = NSSavePanel()
        panel.title = title
        panel.message = title
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true

        let parts = filter.split(separator: "|", omittingEmptySubsequences: false)
        let extensions = stride(from: 1, to: parts.count, by: 2)
            .flatMap { parts[$0].split(separator: ";") }
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "*.", with: "") }
            .filter { !$0.isEmpty && $0 != "*" }
        let types = extensions.compactMap { UTType(filenameExtension: $0) }
        if !types.isEmpty {
            panel.allowedContentTypes = types
            panel.allowsOtherFileTypes = false
        }

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }
}

enum ThreeDSFiles {
    /// InstallTab.GetFilesSafe: 폴더면 하위 폴더까지 모든 파일, 아니면 그대로. 읽을 수 없는 폴더는 건너뛴다.
    /// macOS 숨김 파일(._* 메타데이터 등)은 넘기지 않는다.
    static func expand(_ path: String) -> [String] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return [path] }

        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path, isDirectory: true),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [] }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map(\.path)
    }
}
