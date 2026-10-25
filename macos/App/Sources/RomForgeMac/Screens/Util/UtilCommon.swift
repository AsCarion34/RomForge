// upstream: RomForge/Controls/Util/HashTab.xaml(.cs), RomForge/Controls/Util/TistoryTab.xaml(.cs), RomForge/Controls/Util/CertsTab.xaml(.cs), RomForge/Controls/Util/CueTab.xaml(.cs)
// ViewModel: HashMainViewModel, TistoryMainViewModel, CertsMainViewModel, CueMainViewModel
// 유틸 하위 탭 공통 부분: 빈 목록 안내, 하단 버튼·목록 메뉴·드롭·삭제 처리기, 파일·폴더 대화상자
import AppKit
import SwiftUI

/// 빈 목록 안내(upstream HintVisibility 상자: 아이콘, 안내 문구, 형식 배지)
struct UtilHint: View {
    var icon = "Info.png"
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
                        UtilBadge(text: badge)
                    }
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// 형식 배지(CIA, BIN 등)
struct UtilBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
    }
}

/// 진행률 셀(upstream ProgressBar + "{Progress}%")
struct UtilProgressCell: View {
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
struct UtilColumnSort: SortComparator {
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

    static func sorted(_ items: [RemoteObject], by order: [UtilColumnSort]) -> [RemoteObject] {
        order.isEmpty ? items : items.sorted(using: order)
    }
}

/// code-behind의 버튼·메뉴 처리기(파일 추가, 폴더 추가, 선택 삭제, 전체 삭제, 폴더 열기)
@MainActor
enum UtilFileActions {
    /// BtnAddFiles_Click: OpenFileDialog{Multiselect, Filter=<filterType>.GetFileDialogFilter()} → AddPaths
    static func addFiles(_ engine: EngineClient, _ vm: RemoteObject, filterType: String) {
        Task {
            let filter = await engine.callStatic(filterType, "GetFileDialogFilter")?.string
            let paths = openFiles(filter: filter)
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

    /// 첫 선택 항목(목록 순서)
    static func firstSelected(_ engine: EngineClient, _ vm: RemoteObject, _ ids: Set<Int>) -> RemoteObject? {
        engine.items(vm, "FileItems").first { ids.contains($0.id) }
    }

    /// dir?.OpenFolder(): 폴더가 있으면 Finder로 연다.
    static func openDirectory(_ directory: String?) {
        guard let directory, !directory.isEmpty else { return }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue {
            NSWorkspace.shared.open(URL(fileURLWithPath: directory, isDirectory: true))
        }
    }

    /// Path.GetDirectoryName(path)
    nonisolated static func directoryName(_ path: String) -> String? {
        path.isEmpty ? nil : (path as NSString).deletingLastPathComponent
    }

    /// 폴더 입력란의 PreviewDragOver + Drop: 첫 경로가 있는 폴더일 때만 받아 그 경로를 돌려준다.
    /// (Drop은 파일이면 그 폴더를 쓰지만 PreviewDragOver가 폴더가 아닌 드롭을 막는다)
    nonisolated static func droppedFolder(_ urls: [URL]) -> String? {
        guard let first = urls.first else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: first.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return first.path
    }

    /// 엔진이 띄우는 파일 대화상자와 같은 처리(WPF 필터 해석 포함)를 쓴다.
    static func openFiles(filter: String?, title: String? = nil, multiselect: Bool = true) -> [String] {
        var params: [String: JSONValue] = ["multiselect": .bool(multiselect)]
        if let filter { params["filter"] = .string(filter) }
        if let title { params["title"] = .string(title) }
        return UiHostHandler.handle("ui.openFile", .object(params)).array?.compactMap(\.string) ?? []
    }

    static func openFolder(title: String, initialDirectory: String? = nil) -> String? {
        var params: [String: JSONValue] = ["title": .string(title)]
        if let initialDirectory { params["initialDirectory"] = .string(initialDirectory) }
        return UiHostHandler.handle("ui.openFolder", .object(params)).array?.first?.string
    }
}

/// upstream ListView의 드롭·Delete 키·컨텍스트 메뉴(폴더 열기 / 선택 삭제 / 전체 삭제)
struct UtilFileListBehavior: ViewModifier {
    let engine: EngineClient
    let vm: RemoteObject
    @Binding var selection: Set<Int>
    var enabled: Bool
    /// AllowDrop: 드롭한 경로를 AddPaths로 넘긴다(false면 드롭을 받지 않는다).
    var acceptsDrop = true
    /// MenuItem_OpenFolder_Click: 첫 선택 항목에서 열 폴더(기본: FilePath의 폴더)
    var folderOf: (RemoteObject) -> String? = { UtilFileActions.directoryName($0.string("FilePath")) }

    func body(content: Content) -> some View {
        let list = menuAndDelete(content.disabled(!enabled))

        if acceptsDrop {
            list.dropDestination(for: URL.self) { urls, _ in
                guard enabled, !urls.isEmpty else { return false }
                engine.invoke(vm, "AddPaths", [.strings(urls.map(\.path))])
                return true
            }
        } else {
            list
        }
    }

    private func menuAndDelete(_ content: some View) -> some View {
        content
            .onDeleteCommand {
                guard enabled else { return }
                UtilFileActions.remove(engine, vm, selection)
                selection.removeAll()
            }
            .contextMenu(forSelectionType: Int.self) { ids in
                // LvFiles_ContextMenuOpening: 선택이 없으면 메뉴를 열지 않는다.
                if !ids.isEmpty {
                    Button("폴더 열기") {
                        if let item = UtilFileActions.firstSelected(engine, vm, ids) {
                            UtilFileActions.openDirectory(folderOf(item))
                        }
                    }
                    Divider()
                    Button("선택 삭제") {
                        UtilFileActions.remove(engine, vm, ids)
                        selection.subtract(ids)
                    }
                    Button("전체 삭제") {
                        UtilFileActions.clear(engine, vm)
                        selection.removeAll()
                    }
                }
            }
    }
}
