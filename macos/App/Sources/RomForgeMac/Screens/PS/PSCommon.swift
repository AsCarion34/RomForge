// upstream: RomForge/Controls/PS/PackingTab.xaml(.cs), UnpackingTab.xaml(.cs), ConverterTab.xaml(.cs) 공통 부분(하단 버튼, 목록 메뉴·드롭·삭제, 파일 대화상자)
// ViewModel: PackingMainViewModel, UnpackingMainViewModel, PSPConverterViewModel
import AppKit
import SwiftUI

/// 빈 목록 안내(upstream HintVisibility 상자: drag.png, 안내 문구, 형식 배지)
struct PSHint: View {
    var icon = "drag.png"
    let title: String
    var detail: String? = nil
    var badges: [String] = []

    var body: some View {
        VStack(spacing: 8) {
            UpstreamIcon(name: icon, size: 28)
            Text(title).font(.headline)
            if let detail {
                Text(detail).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            if !badges.isEmpty {
                HStack(spacing: 6) {
                    ForEach(badges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// 진행률 셀(upstream ProgressBar + "{Progress}%")
struct PSProgressCell: View {
    let item: RemoteObject

    var body: some View {
        HStack(spacing: 6) {
            ProgressCell(item: item)
            Text("\(item["Progress"]?.int ?? 0)%")
                .font(.caption.monospacedDigit())
                .frame(minWidth: 34, alignment: .trailing)
        }
    }
}

/// GridViewColumnHeader_Click(ListViewColumnSorter) 자리: 머리글 Tag 속성으로 화면 목록만 정렬한다(ViewModel 순서는 그대로).
struct PSColumnSort: SortComparator {
    let prop: String
    var order: SortOrder = .forward

    func compare(_ lhs: RemoteObject, _ rhs: RemoteObject) -> ComparisonResult {
        // 표 정렬은 화면(메인 스레드)에서만 한다.
        let (a, b, textA, textB) = MainActor.assumeIsolated {
            (lhs[prop]?.double, rhs[prop]?.double, lhs.string(prop), rhs.string(prop))
        }

        let result: ComparisonResult
        if let a, let b {
            result = a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
        } else {
            result = textA.localizedStandardCompare(textB)
        }

        guard order == .reverse else { return result }
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    static func sorted(_ items: [RemoteObject], by order: [PSColumnSort]) -> [RemoteObject] {
        order.isEmpty ? items : items.sorted(using: order)
    }
}

/// code-behind의 버튼·메뉴 처리기(파일 추가, 폴더 추가, 선택 삭제, 전체 삭제, 폴더 열기)
@MainActor
enum PSFileActions {
    /// BtnAddFiles_Click: OpenFileDialog{Multiselect, Filter, Title} → AddPaths.
    /// filterType이 있으면 upstream `<filterType>.GetFileDialogFilter()`로 필터를 받는다.
    static func addFiles(_ engine: EngineClient, _ vm: RemoteObject, filterType: String? = nil, filter: String? = nil, title: String? = nil) {
        Task {
            var dialogFilter = filter
            if let filterType {
                dialogFilter = await engine.callStatic(filterType, "GetFileDialogFilter")?.string
            }
            let paths = openFiles(filter: dialogFilter, title: title)
            if !paths.isEmpty {
                engine.invoke(vm, "AddPaths", [.strings(paths)])
            }
        }
    }

    /// BtnAddFolder_Click: VistaFolderBrowserDialog("추가할 폴더를 선택하세요") → AddPaths([폴더])
    static func addFolder(_ engine: EngineClient, _ vm: RemoteObject) {
        if let folder = openFolder(title: "추가할 폴더를 선택하세요") {
            engine.invoke(vm, "AddPaths", [.strings([folder])])
        }
    }

    /// BtnRemove_Click / Delete 키: RemoveItems(선택 항목)
    static func remove(_ engine: EngineClient, _ vm: RemoteObject, _ ids: Set<Int>) {
        guard !ids.isEmpty else { return }
        engine.invoke(vm, "RemoveItems", [EngineClient.refs(ids)])
    }

    /// BtnClear_Click: ClearItems()
    static func clear(_ engine: EngineClient, _ vm: RemoteObject) {
        engine.invoke(vm, "ClearItems")
    }

    /// MenuItem_OpenFolder_Click: 첫 선택 항목 FilePath의 폴더를 연다(Path.GetDirectoryName → OpenFolder)
    static func openFolder(_ engine: EngineClient, _ vm: RemoteObject, _ ids: Set<Int>) {
        guard let item = engine.items(vm, "FileItems").first(where: { ids.contains($0.id) }) else { return }
        let path = item.string("FilePath")
        guard !path.isEmpty else { return }

        let directory = (path as NSString).deletingLastPathComponent
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue {
            NSWorkspace.shared.open(URL(fileURLWithPath: directory, isDirectory: true))
        }
    }

    /// Directory.Exists(path)
    nonisolated static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// 엔진이 띄우는 파일 대화상자와 같은 처리(WPF 필터 해석 포함)를 쓴다.
    static func openFiles(filter: String?, title: String? = nil, multiselect: Bool = true) -> [String] {
        var params: [String: JSONValue] = ["multiselect": .bool(multiselect)]
        if let filter { params["filter"] = .string(filter) }
        if let title { params["title"] = .string(title) }
        return UiHostHandler.handle("ui.openFile", .object(params)).array?.compactMap(\.string) ?? []
    }

    static func openFolder(title: String) -> String? {
        UiHostHandler.handle("ui.openFolder", .object(["title": .string(title)])).array?.first?.string
    }
}

/// upstream ListView의 드롭·Delete 키·컨텍스트 메뉴(폴더 열기 / 선택 삭제 / 전체 삭제)
struct PSFileListBehavior: ViewModifier {
    let engine: EngineClient
    let vm: RemoteObject
    @Binding var selection: Set<Int>
    var enabled: Bool
    /// LvFiles_Drop: 드롭한 경로 중 AddPaths에 넘길 것
    var dropPaths: ([URL]) -> [String] = { $0.map(\.path) }

    func body(content: Content) -> some View {
        content
            .disabled(!enabled)
            .dropDestination(for: URL.self) { urls, _ in
                guard enabled else { return false }
                let paths = dropPaths(urls)
                guard !paths.isEmpty else { return false }
                engine.invoke(vm, "AddPaths", [.strings(paths)])
                return true
            }
            .onDeleteCommand {
                guard enabled else { return }
                PSFileActions.remove(engine, vm, selection)
                selection.removeAll()
            }
            .contextMenu(forSelectionType: Int.self) { ids in
                // LvFiles_ContextMenuOpening: 선택이 없으면 메뉴를 열지 않는다.
                if !ids.isEmpty {
                    Button("폴더 열기") { PSFileActions.openFolder(engine, vm, ids) }
                    Divider()
                    Button("선택 삭제") {
                        PSFileActions.remove(engine, vm, ids)
                        selection.subtract(ids)
                    }
                    Button("전체 삭제") {
                        PSFileActions.clear(engine, vm)
                        selection.removeAll()
                    }
                }
            }
    }
}
