// upstream: RomForge/Controls/PSP/PackingTab.xaml(.cs), RomForge/Controls/PSP/UnpackingTab.xaml(.cs), RomForge/Controls/PSP/ConverterTab.xaml(.cs)
// 공통 부분: 빈 목록 안내, 진행률 셀, 하위 ViewModel describe, 목록 메뉴·드롭·삭제, 파일 대화상자
// ViewModel: DiscListViewModel(PackingMainViewModel.Files), UnpackingMainViewModel, ConverterViewModel
import SwiftUI

/// 빈 목록 안내(upstream HintVisibility 상자: 아이콘, 안내 문구, 형식 배지)
struct PSPHint: View {
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
struct PSPProgressCell: View {
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

extension View {
    /// 하위 ViewModel 속성(PackingMainViewModel.Files·Images 등)을 describe해 둔다.
    /// 그 뒤로는 engine.store.object(owner.ref(prop))로 읽고, 속성 변경도 그대로 반영된다.
    func pspDescribeChildren(_ engine: EngineClient, _ owner: RemoteObject?, _ props: [String]) -> some View {
        task(id: owner?.id) { @MainActor in
            for prop in props {
                if let id = owner?.ref(prop), engine.store.object(id) == nil {
                    await engine.describe(id)
                }
            }
        }
    }
}

/// code-behind의 버튼·메뉴 처리기(파일 추가, 폴더 추가, 선택 삭제, 전체 삭제, 폴더 열기).
/// owner는 목록(FileItems)과 AddPaths 등을 가진 ViewModel이다(패킹은 PackingMainViewModel.Files).
@MainActor
enum PSPFileActions {
    /// BtnAddFiles_Click: OpenFileDialog{Multiselect, Filter, Title} → AddPaths.
    /// filterType이 있으면 upstream `<filterType>.GetFileDialogFilter()`로 필터를 받는다.
    static func addFiles(_ engine: EngineClient, _ owner: RemoteObject?, filterType: String? = nil, filter: String? = nil, title: String? = nil) {
        Task {
            var dialogFilter = filter
            if let filterType {
                dialogFilter = await engine.callStatic(filterType, "GetFileDialogFilter")?.string
            }
            let paths = openFiles(filter: dialogFilter, title: title)
            if !paths.isEmpty {
                engine.invoke(owner, "AddPaths", [.strings(paths)])
            }
        }
    }

    /// BtnAddFolder_Click: VistaFolderBrowserDialog("추가할 폴더를 선택하세요") → AddPaths([폴더])
    static func addFolder(_ engine: EngineClient, _ owner: RemoteObject?) {
        if let folder = openFolder(title: "추가할 폴더를 선택하세요") {
            engine.invoke(owner, "AddPaths", [.strings([folder])])
        }
    }

    /// BtnRemove_Click / Delete 키: RemoveItems(선택 항목). 패킹은 Files.Remove
    static func remove(_ engine: EngineClient, _ owner: RemoteObject?, _ ids: Set<Int>, method: String = "RemoveItems") {
        guard !ids.isEmpty else { return }
        engine.invoke(owner, method, [EngineClient.refs(ids)])
    }

    /// BtnClear_Click: ClearItems(). 패킹은 Files.Clear
    static func clear(_ engine: EngineClient, _ owner: RemoteObject?, method: String = "ClearItems") {
        engine.invoke(owner, method)
    }

    /// MenuItem_OpenFolder_Click: 첫 선택 항목 FilePath의 폴더를 연다(Path.GetDirectoryName → OpenFolder)
    static func openFolder(_ engine: EngineClient, _ owner: RemoteObject?, _ ids: Set<Int>) {
        guard let item = engine.items(owner, "FileItems").first(where: { ids.contains($0.id) }) else { return }
        FilePanels.showContainingFolder(item.string("FilePath"))
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
struct PSPFileListBehavior: ViewModifier {
    let engine: EngineClient
    /// FileItems·AddPaths를 가진 ViewModel
    let owner: RemoteObject?
    @Binding var selection: Set<Int>
    var enabled: Bool
    var removeMethod = "RemoveItems"
    var clearMethod = "ClearItems"
    /// LvFiles_Drop: 드롭한 경로 중 AddPaths에 넘길 것
    var dropPaths: ([URL]) -> [String] = { $0.map(\.path) }

    func body(content: Content) -> some View {
        content
            .disabled(!enabled)
            .dropDestination(for: URL.self) { urls, _ in
                guard enabled, let owner else { return false }
                let paths = dropPaths(urls)
                guard !paths.isEmpty else { return false }
                engine.invoke(owner, "AddPaths", [.strings(paths)])
                return true
            }
            .onDeleteCommand {
                guard enabled else { return }
                PSPFileActions.remove(engine, owner, selection, method: removeMethod)
                selection.removeAll()
            }
            .contextMenu(forSelectionType: Int.self) { ids in
                // LvFiles_ContextMenuOpening: 선택이 없으면 메뉴를 열지 않는다.
                if !ids.isEmpty {
                    Button("폴더 열기") { PSPFileActions.openFolder(engine, owner, ids) }
                    Divider()
                    Button("선택 삭제") {
                        PSPFileActions.remove(engine, owner, ids, method: removeMethod)
                        selection.subtract(ids)
                    }
                    Button("전체 삭제") {
                        PSPFileActions.clear(engine, owner, method: clearMethod)
                        selection.removeAll()
                    }
                }
            }
    }
}
