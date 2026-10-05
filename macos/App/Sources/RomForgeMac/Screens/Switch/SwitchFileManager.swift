// upstream: NSW.WPF/UI/FileManagerControl.xaml(.cs)
// ViewModel: NSW.WPF/ViewModels/GameFile(항목). 목록은 컨트롤이 가진 ObservableCollection<GameFile>(엔진에 생성)
import AppKit
import SwiftUI

/// 병합·버전 무시 탭의 파일 목록.
struct SwitchFileManager: View {
    @Environment(EngineClient.self) private var engine
    let list: SwitchGameFileList
    var enabled = true
    /// FileListChanged(파일 추가·삭제 후)
    var onFileListChanged: () async -> Void = {}

    @State private var selection = Set<Int>()
    @State private var sortOrder: [SwitchColumnSort] = []

    var body: some View {
        let items = list.items(engine)

        HStack(alignment: .top, spacing: 12) {
            table(items)
            sideButtons(items)
        }
        .padding(10)
        .disabled(!enabled)
        .task { await list.prepare(engine, importer: false) }
    }

    private func table(_ items: [RemoteObject]) -> some View {
        Table(SwitchColumnSort.apply(sortOrder, to: items), selection: $selection, sortOrder: $sortOrder) {
            // Res.Header_Type
            TableColumn("종류", sortUsing: SwitchColumnSort(prop: "FileType")) { item in
                SwitchBadge(text: item.string("FileType"), background: item["TypeBackground"]?.color, foreground: item["TypeForeground"]?.color)
            }
            .width(80)
            TableColumn("타이틀", sortUsing: SwitchColumnSort(prop: "TitleName")) { item in SwitchTitleCell(item: item).cellEnvironment(engine) }
                .width(min: 200, ideal: 380)
            TableColumn("버전", sortUsing: SwitchColumnSort(prop: "Version")) { item in
                Text(item.string("Version"))
                    .fontWeight(.bold)
                    .help(item.string("Version"))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(120)
            // Res.Header_Ext
            TableColumn("확장자", sortUsing: SwitchColumnSort(prop: "Extension")) { item in
                SwitchBadge(text: item.string("Extension"), background: item["ExtensionBackground"]?.color, foreground: item["ExtensionForeground"]?.color)
            }
            .width(90)
            // Res.Header_Size
            TableColumn("용량", sortUsing: SwitchColumnSort(prop: "FileSize")) { item in
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
                        SwitchPanels.showContainingFolder(file.string("FilePath"))
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
                let paths = SwitchPanels.openFiles(title: "게임 파일 선택", extensions: SwitchPanels.switchExtensions, multiple: true)
                if !paths.isEmpty { Task { await addFiles(paths) } }
            }
            ToolIconButton(icon: "AddFolder.png", help: "폴더 추가") {
                if let folder = SwitchPanels.openFolder(title: "게임 폴더 선택") { Task { await addFiles([folder]) } }
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
        guard let listId = list.listId else { return }
        await SwitchFileManagerImport.addFiles(engine, listId: listId, paths: paths)
        await onFileListChanged()
    }

    /// BtnRemoveFile_Click
    private func removeFiles(_ ids: Set<Int>, from items: [RemoteObject]) {
        guard let listId = list.listId, !ids.isEmpty else { return }
        let ordered = SwitchBridge.ordered(ids, in: items)
        selection.removeAll()

        Task {
            for id in ordered {
                await engine.call(listId, "Remove", [EngineClient.ref(id)])
            }
            await onFileListChanged()
        }
    }

    /// BtnRemoveAllFiles_Click
    private func removeAll() {
        guard let listId = list.listId else { return }
        selection.removeAll()

        Task {
            await engine.call(listId, "Clear")
            await onFileListChanged()
        }
    }
}

/// FileManagerControl.AddFilesAsync.
/// 이 메서드는 upstream .xaml.cs 안에 있어 엔진에 없다(엔진 빌드는 .xaml.cs를 뺀다). 같은 순서로 upstream 메서드
/// (MetadataReader.GetGameFileInfo/GetMetadataFromContainer, MetadataResult.GetEffectiveDisplayVersion,
/// Extensions.ToBitmapImage, new GameFile)를 엔진에서 부른다. SwitchGameFileImporter와 달리 기존 항목을 교체하지 않는다.
@MainActor
enum SwitchFileManagerImport {
    private static let reader = "NSW.Core.MetadataReader"

    static func addFiles(_ engine: EngineClient, listId: Int, paths: [String]) async {
        let keySet = await SwitchBridge.keySet(engine)

        // 기존 경로(OrdinalIgnoreCase)
        var existing = Set(engine.store.items(listId).compactMap { engine.store.object($0.refId)?.string("FilePath").lowercased() })

        let expanded = await SwitchBridge.values(engine, of: await SwitchBridge.expandPaths(engine, paths)).compactMap(\.string)
        let supported = SwitchGameFileList.supportedExtensions.map { String($0.dropFirst()) }
        let newPaths = expanded
            .filter { supported.contains(($0 as NSString).pathExtension.lowercased()) }
            .filter { existing.insert($0.lowercased()).inserted }

        guard !newPaths.isEmpty else { return }

        let noKey = await SwitchBridge.resource(engine, "Status_NoKey")
        let analyzing = await SwitchBridge.resource(engine, "Status_Analyzing")

        for path in newPaths {
            var titleName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            var icon = JSONValue.null

            if let keySet {
                if let info = await gameFileInfo(engine, keySet, path) {
                    if !info.string("TitleName").isEmpty { titleName = info.string("TitleName") }
                    if let iconData = info["IconData"], iconData.refId != nil {
                        icon = await engine.callStatic("NSW.WPF.Services.Extensions", "ToBitmapImage", [iconData]) ?? .null
                    }
                }

                // try { allMeta = MetadataReader.GetMetadataFromContainer(keySet, path); } catch { allMeta = []; }
                let allMeta = await metadata(engine, keySet, path)

                if !allMeta.isEmpty {
                    let apps = allMeta.filter { $0.string("Type") == "Application" }
                    for app in apps {
                        await add(engine, listId, path, fileType: "B", titleId: app["TitleId"], version: await version(engine, app), titleName: titleName, icon: icon)
                    }

                    let patches = allMeta.filter { $0.string("Type") == "Patch" }
                    for patch in patches {
                        await add(engine, listId, path, fileType: "U", titleId: patch["TitleId"], version: await version(engine, patch), titleName: titleName, icon: icon)
                    }

                    var seen = Set<String>()
                    let dlcs = allMeta
                        .filter { ["AddOnContent", "Delta"].contains($0.string("Type")) }
                        .filter { seen.insert($0.string("TitleId").lowercased()).inserted }
                    for dlc in dlcs {
                        let titleId = dlc.string("TitleId")
                        let name = titleName.isEmpty ? titleId : "\(titleName) (DLC \(titleId.suffix(4)))"
                        await add(engine, listId, path, fileType: "D", titleId: dlc["TitleId"], version: await version(engine, dlc), titleName: name, icon: icon)
                    }

                    if !apps.isEmpty || !patches.isEmpty || !dlcs.isEmpty { continue }
                }
            }

            var fileType = keySet == nil ? noKey : analyzing
            var titleId = JSONValue.null
            var version = JSONValue.null

            if let keySet, let info = await gameFileInfo(engine, keySet, path) {
                titleId = info["TitleId"] ?? .null
                version = info["DisplayVersion"] ?? .null
                fileType = info.string("Type")
            }

            await add(engine, listId, path, fileType: fileType, titleId: titleId, version: version, titleName: titleName, icon: icon)
        }
    }

    private static func gameFileInfo(_ engine: EngineClient, _ keySet: Int, _ path: String) async -> RemoteObject? {
        await SwitchBridge.object(engine, await engine.callStatic(reader, "GetGameFileInfo", [EngineClient.ref(keySet), .string(path)]))
    }

    private static func metadata(_ engine: EngineClient, _ keySet: Int, _ path: String) async -> [RemoteObject] {
        guard let list = try? await SwitchBridge.callStatic(engine, reader, "GetMetadataFromContainer", [EngineClient.ref(keySet), .string(path)]) else { return [] }

        var result: [RemoteObject] = []
        for value in await SwitchBridge.values(engine, of: list) {
            if let meta = await SwitchBridge.object(engine, value) { result.append(meta) }
        }
        return result
    }

    private static func version(_ engine: EngineClient, _ meta: RemoteObject) async -> JSONValue? {
        await engine.call(meta.id, "GetEffectiveDisplayVersion")
    }

    /// GameFiles.Add(new GameFile(path) { FileType, TitleID, Version, TitleName, Icon })
    private static func add(_ engine: EngineClient, _ listId: Int, _ path: String, fileType: String, titleId: JSONValue?, version: JSONValue?,
                            titleName: String, icon: JSONValue) async {
        guard let file = await engine.create("NSW.WPF.ViewModels.GameFile", [.string(path)]) else { return }

        await engine.set(file, "FileType", .string(fileType))
        await engine.set(file, "TitleID", titleId ?? .null)
        await engine.set(file, "Version", version ?? .null)
        await engine.set(file, "TitleName", .string(titleName))
        if icon != .null { await engine.set(file, "Icon", icon) }

        await engine.call(listId, "Add", [EngineClient.ref(file)])
    }
}
