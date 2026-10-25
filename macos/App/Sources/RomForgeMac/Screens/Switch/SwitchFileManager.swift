// upstream: NSW.WPF/UI/FileManagerControl.xaml(.cs)
// ViewModel: 없음(컨트롤이 가진 ObservableCollection<GameFile>을 엔진에 만든다), 항목 NSW.WPF.ViewModels.GameFile
import AppKit
import SwiftUI

/// 병합·버전 무시 탭의 파일 목록. FileListChanged는 이제 구독하는 탭이 없어 옮기지 않는다.
/// ExtraButton1·2는 upstream에서 숨김(Collapsed)이고 쓰는 곳이 없어 옮기지 않는다.
struct SwitchFileManager: View {
    @Environment(EngineClient.self) private var engine
    let list: SwitchGameFileList
    var enabled = true

    @State private var selection = Set<Int>()
    @State private var sortOrder: [ColumnSort] = []

    var body: some View {
        let items = list.items(engine)

        HStack(alignment: .top, spacing: 12) {
            table(items)
            sideButtons(items)
        }
        .padding(10)
        .disabled(!enabled)
        .task { await list.prepare(engine, titleList: false) }
    }

    private func table(_ items: [RemoteObject]) -> some View {
        Table(ColumnSort.sorted(items, by: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            // 머리글: Categories.png(글자 없음), Tag="FileType"
            TableColumn("", sortUsing: ColumnSort("FileType")) { item in
                SwitchBadge(text: item.string("FileType"), background: item["TypeBackground"]?.color, foreground: item["TypeForeground"]?.color)
                    .frame(maxWidth: .infinity)
            }
            .width(70)
            TableColumn("타이틀", sortUsing: ColumnSort("TitleName")) { item in SwitchTitleCell(item: item).cellEnvironment(engine) }
                .width(min: 200, ideal: 380)
            TableColumn("버전", sortUsing: ColumnSort("Version")) { item in
                Text(item.string("Version"))
                    .fontWeight(.bold)
                    .help(item.string("Version"))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(120)
            // 머리글: Extension.png(글자 없음), Tag="Extension"
            TableColumn("", sortUsing: ColumnSort("Extension")) { item in
                SwitchBadge(text: item.string("Extension"), background: item["ExtensionBackground"]?.color, foreground: item["ExtensionForeground"]?.color)
                    .frame(maxWidth: .infinity)
            }
            .width(50)
            // Res.Header_Size
            TableColumn("용량", sortUsing: ColumnSort("FileSize")) { item in
                Text(item.string("FileSize")).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(75)
        }
        .overlay {
            if items.isEmpty {
                SwitchDropHint(title: "파일 또는 폴더를 여기에 드래그&드롭하세요")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await addFiles(urls.map(\.path)) }
            return true
        }
        .onDeleteCommand { removeFiles(selection, from: items) }
        .contextMenu(forSelectionType: Int.self) { ids in
            if !ids.isEmpty {
                Button("폴더 열기") {
                    if let id = SwitchBridge.ordered(ids, in: items).first, let file = engine.store.object(id) {
                        FilePanels.showContainingFolder(file.string("FilePath"))
                    }
                }
                Divider()
                Button("선택 삭제") { removeFiles(ids, from: items) }
                Button("전체 삭제") { removeAll() }
            }
        }
    }

    private func sideButtons(_ items: [RemoteObject]) -> some View {
        VStack(spacing: 8) {
            // Res.ToolTip_AddFile
            ToolIconButton(icon: "AddFile.png", help: "파일 추가") {
                // Res.Dialog_SelectGameFile, Res.Filter_SwitchFiles(… *.nsp;*.xci;*.nsz;*.xcz)|Res.Filter_AllFiles|*.*
                let paths = FilePanels.openFiles(title: "게임 파일 선택", extensions: SwitchPanels.switchExtensions, multiple: true)
                if !paths.isEmpty { Task { await addFiles(paths) } }
            }
            ToolIconButton(icon: "AddFolder.png", help: "폴더 추가") {
                if let folder = FilePanels.openFolder(title: "게임 폴더 선택") { Task { await addFiles([folder]) } }
            }
            // Res.ToolTip_RemoveSelected
            ToolIconButton(icon: "Delete.png", help: "선택 항목 제거") { removeFiles(selection, from: items) }
            // Res.ToolTip_RemoveAll
            ToolIconButton(icon: "Clear.png", help: "전체 항목 제거") { removeAll() }
        }
    }

    // MARK: 동작

    /// AddFilesAsync(Common.Utils.ExpandPaths(paths))
    private func addFiles(_ paths: [String]) async {
        await SwitchFileManagerImport.addFiles(engine, list: list, paths: paths)
    }

    /// BtnRemoveFile_Click: GameFiles.Remove(item)
    private func removeFiles(_ ids: Set<Int>, from items: [RemoteObject]) {
        guard let listId = list.listId, !ids.isEmpty else { return }
        let ordered = SwitchBridge.ordered(ids, in: items)
        selection.removeAll()

        Task {
            for id in ordered {
                await engine.call(listId, "Remove", [EngineClient.ref(id)])
            }
        }
    }

    /// BtnRemoveAllFiles_Click: GameFiles.Clear()
    private func removeAll() {
        guard let listId = list.listId else { return }
        selection.removeAll()
        Task { await engine.call(listId, "Clear") }
    }
}

/// FileManagerControl.AddFilesAsync · RecalcKeyMissingFilesAsync · ApplyInfo.
/// 이 메서드들은 upstream .xaml.cs 안에 있어 엔진에 없다(엔진 빌드는 .xaml.cs를 뺀다). 같은 순서로 upstream 메서드
/// (Common.Utils.ExpandPaths, new GameFile, KeySet.Clone, MetadataReader.ReadGameFileInfo, Extensions.ToBitmapImage)를 엔진에서 부른다.
@MainActor
enum SwitchFileManagerImport {
    private static let reader = "NSW.Core.MetadataReader"

    /// 먼저 '분석중…'(키가 없으면 '키 없음') 항목을 모두 넣고, 키가 있으면 하나씩 정보를 읽어 채운다.
    static func addFiles(_ engine: EngineClient, list: SwitchGameFileList, paths: [String]) async {
        guard let listId = list.listId else { return }
        let keySet = await SwitchBridge.keySet(engine)

        // candidates = paths.Where(p => SupportedExtensions.Contains(Path.GetExtension(p)))
        let expanded = await SwitchBridge.values(engine, of: await SwitchBridge.expandPaths(engine, paths)).compactMap(\.string)
        let candidates = expanded.filter { SwitchGameFileList.supports($0) }

        // GameFiles.Any(f => string.Equals(f.FilePath, path, StringComparison.OrdinalIgnoreCase))
        var existing = Set(await list.refreshedItems(engine).map { $0.string("FilePath").lowercased() })
        let fileType = await SwitchBridge.resource(engine, keySet == nil ? "Status_NoKey" : "Status_Analyzing")
        var added: [(id: Int, path: String)] = []

        for path in candidates where existing.insert(path.lowercased()).inserted {
            // new GameFile(path) { FileType, TitleName = Path.GetFileNameWithoutExtension(path) }
            guard let file = await engine.create("NSW.WPF.ViewModels.GameFile", [.string(path)]) else { continue }
            await engine.set(file, "FileType", .string(fileType))
            await engine.set(file, "TitleName", .string(((path as NSString).lastPathComponent as NSString).deletingPathExtension))
            await engine.call(listId, "Add", [EngineClient.ref(file)])
            added.append((file, path))
        }

        guard let keySet else { return }

        for file in added {
            await applyInfo(engine, file.id, keySet: keySet, path: file.path)
        }
    }

    /// RecalcKeyMissingFilesAsync: '키 없음' 항목의 정보를 다시 읽는다.
    static func recalcKeyMissing(_ engine: EngineClient, list: SwitchGameFileList) async {
        guard let keySet = await SwitchBridge.keySet(engine) else { return }

        let targets = await list.refreshedItems(engine).filter { $0["IsKeyMissing"]?.bool == true }
        for file in targets {
            await applyInfo(engine, file.id, keySet: keySet, path: file.string("FilePath"))
        }
    }

    /// `info = await Task.Run(() => { try { return MetadataReader.ReadGameFileInfo(keySet.Clone(), path); } catch { return null; } });`
    /// `ApplyInfo(vm, info)`
    private static func applyInfo(_ engine: EngineClient, _ file: Int, keySet: Int, path: String) async {
        var temporary: [Int] = []
        var info: RemoteObject?

        if let clone = await engine.call(keySet, "Clone")?.refId {
            temporary.append(clone)
            let result = try? await engine.callStaticThrowing(reader, "ReadGameFileInfo", [EngineClient.ref(clone), .string(path)], options: .background)
            if let id = result?.refId {
                temporary.append(id)
                info = await engine.describe(id)
            }
        }

        guard let info else {
            await engine.set(file, "FileType", .string("?"))
            await SwitchBridge.release(engine, temporary)
            return
        }

        let titleName = info.string("TitleName")
        if !titleName.isEmpty {
            await engine.set(file, "TitleName", .string(titleName))
        }

        if let iconData = info["IconData"], let iconDataId = iconData.refId {
            temporary.append(iconDataId)
            let icon = await engine.callStatic("NSW.WPF.Services.Extensions", "ToBitmapImage", [iconData])
            await engine.set(file, "Icon", icon ?? .null)
        }

        await engine.set(file, "Naming", info["Naming"] ?? .null)
        await engine.set(file, "TitleID", info["TitleId"] ?? .null)
        await engine.set(file, "Version", info["DisplayVersion"] ?? .null)
        await engine.set(file, "FileType", info["Type"] ?? .string("?"))
        await SwitchBridge.release(engine, temporary)
    }
}
