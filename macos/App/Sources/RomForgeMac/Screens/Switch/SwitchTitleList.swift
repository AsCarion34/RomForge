// upstream: RomForge/Controls/Switch/SwitchTitleListControl.xaml(.cs) (+ SwitchGameFileImporter, GameFilePatchSyncManager, SwitchGameFileListOrganizer, SwitchBulkPatchMatcher, Common.WPF/PatchDropValidator)
// ViewModel: NSW.WPF/ViewModels/GameFile(항목). 목록은 컨트롤이 가진 ObservableCollection<GameFile>(엔진에 생성)
import AppKit
import SwiftUI

/// 리팩 탭의 '파일' 목록. 파일 추가·교체·패치 동기화는 엔진의 SwitchGameFileImporter·GameFilePatchSyncManager가 한다.
struct SwitchTitleList: View {
    @Environment(EngineClient.self) private var engine
    let list: SwitchGameFileList
    var enabled = true
    /// FileListChanged(파일 추가·삭제 후)
    let onFileListChanged: () -> Void

    @State private var selection = Set<Int>()

    private static let bulkCaption = "한글패치 일괄 지정"

    var body: some View {
        let items = list.items(engine)

        HStack(alignment: .top, spacing: 12) {
            table(items)
            sideButtons(items)
        }
        .padding(10)
        .disabled(!enabled)
    }

    // MARK: 목록

    private func table(_ items: [RemoteObject]) -> some View {
        Table(items, selection: $selection) {
            TableColumn("종류") { item in
                SwitchBadge(text: item.string("FileType"), background: item["TypeBackground"]?.color, foreground: item["TypeForeground"]?.color)
            }
            .width(80)
            TableColumn("타이틀") { item in SwitchTitleCell(item: item).cellEnvironment(engine) }
                .width(min: 200, ideal: 300)
            TableColumn("버전") { item in
                Text(item.string("Version")).fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(90)
            TableColumn("패치") { item in
                SwitchPatchCell(item: item, assign: { path in assignPatch(item, path) }, selectFolder: { selectPatchFolder(item) },
                                selectArchive: { selectPatchArchive(item) })
            }
            .width(80)
            TableColumn("확장자") { item in
                SwitchBadge(text: item.string("Extension"), background: item["ExtensionBackground"]?.color, foreground: item["ExtensionForeground"]?.color)
            }
            .width(90)
            TableColumn("용량") { item in
                Text(item.string("FileSize")).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(80)
        }
        .overlay {
            if items.isEmpty {
                SwitchDropHint(title: "게임 파일 / 폴더를 여기에 드래그&드롭하세요", detail: "본편/업데이트는 자동 교체, DLC는 계속 추가됩니다")
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
                Button("한글패치 취소") {
                    // _patchSync.ClearPatch(lvFiles.SelectedItem)
                    if let id = SwitchBridge.ordered(ids, in: items).first, let sync = list.patchSyncId {
                        Task { await engine.call(sync, "ClearPatch", [EngineClient.ref(id)]) }
                    }
                }
                Divider()
                Button("선택 삭제") { removeFiles(ids, from: items) }
                Button("전체 삭제") { removeAll(items) }
            }
        }
    }

    private func sideButtons(_ items: [RemoteObject]) -> some View {
        VStack(spacing: 8) {
            ToolIconButton(icon: "AddFile.png", help: "파일 추가") {
                // Res.Dialog_SelectGameFile, Res.Filter_SwitchFiles(… *.nsp;*.xci;*.nsz;*.xcz)|Res.Filter_AllFiles|*.*
                let paths = SwitchPanels.openFiles(title: "게임 파일 선택", extensions: SwitchPanels.switchExtensions, multiple: true)
                if !paths.isEmpty { Task { await addFiles(paths) } }
            }
            ToolIconButton(icon: "AddFolder.png", help: "폴더 추가") {
                if let folder = SwitchPanels.openFolder(title: "게임 폴더 선택") { Task { await addFiles([folder]) } }
            }
            Menu {
                Button("폴더에서 찾기...") { bulkFromFolder(items) }
                Button("압축파일에서 찾기(zip/7z)...") { bulkFromArchive(items) }
            } label: {
                UpstreamAssets.menuImage("Patch.png", size: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("한글패치 일괄 지정 (루트 폴더 또는 압축파일)")
            ToolIconButton(icon: "Delete.png", help: "선택 삭제") { removeFiles(selection, from: items) }
            ToolIconButton(icon: "Clear.png", help: "전체 삭제") { removeAll(items) }
            ToolIconButton(icon: "Help.png", help: "도움말") {
                SwitchPanels.openURL("https://sinjunyoung.github.io/RomForge/switch-unpack-repack/")
            }
        }
    }

    // MARK: 파일 추가·삭제

    /// _importer.AddFilesAsync(Common.Utils.ExpandPaths(paths), UpdateDropHint)
    private func addFiles(_ paths: [String]) async {
        guard let importer = list.importerId else { return }
        let expanded = await SwitchBridge.expandPaths(engine, paths)
        await engine.call(importer, "AddFilesAsync", [expanded, .null])
        onFileListChanged()
    }

    /// BtnRemoveFile_Click: 패치 동기화 해제 → 제거 → SwitchGameFileListOrganizer.Reorganize
    private func removeFiles(_ ids: Set<Int>, from items: [RemoteObject]) {
        guard let listId = list.listId, !ids.isEmpty else { return }
        let ordered = SwitchBridge.ordered(ids, in: items)
        selection.removeAll()

        Task {
            for id in ordered {
                if let sync = list.patchSyncId { await engine.call(sync, "Detach", [EngineClient.ref(id)]) }
                await engine.call(listId, "Remove", [EngineClient.ref(id)])
            }
            await engine.callStatic("RomForge.Controls.Switch.SwitchGameFileListOrganizer", "Reorganize", [EngineClient.ref(listId)])
            onFileListChanged()
        }
    }

    /// BtnRemoveAllFiles_Click
    private func removeAll(_ items: [RemoteObject]) {
        guard let listId = list.listId else { return }
        selection.removeAll()

        Task {
            if let sync = list.patchSyncId {
                for item in items { await engine.call(sync, "Detach", [EngineClient.ref(item.id)]) }
            }
            await engine.call(listId, "Clear")
            onFileListChanged()
        }
    }

    // MARK: 한글패치

    /// PatchMenu_SelectFolder_Click
    private func selectPatchFolder(_ item: RemoteObject) {
        if let folder = SwitchPanels.openFolder(title: "\(item.string("TitleName"))에 적용할 한글패치 폴더 선택") {
            Task { await engine.set(item.id, "PatchPath", .string(folder)) }
        }
    }

    /// PatchMenu_SelectArchive_Click
    private func selectPatchArchive(_ item: RemoteObject) {
        let paths = SwitchPanels.openFiles(title: "\(item.string("TitleName"))에 적용할 한글패치 압축파일 선택", extensions: ["zip", "7z"])
        if let path = paths.first { Task { await assignArchivePatch(item, path) } }
    }

    /// PatchDropTarget_Drop: PatchDropValidator.IsValidPatchPath → 압축이면 비밀번호 확인 후, 아니면 경로를 그대로
    private func assignPatch(_ item: RemoteObject, _ path: String) {
        Task {
            guard await engine.callStatic("Common.WPF.PatchDropValidator", "IsValidPatchPath", [.string(path)])?.bool == true else { return }

            if await engine.callStatic("Patch.Core.Services.ArchivePatchSourceFactory", "IsArchivePath", [.string(path)])?.bool == true {
                await assignArchivePatch(item, path)
            } else {
                await engine.set(item.id, "PatchPath", .string(path))
            }
        }
    }

    /// TryAssignArchivePatchAsync
    @discardableResult
    private func assignArchivePatch(_ item: RemoteObject, _ archivePath: String) async -> Bool {
        do {
            let opened = try await SwitchBridge.openArchive(engine, archivePath)
            guard opened.opened else { return false }

            await engine.set(item.id, "PatchPath", .string(archivePath))
            await engine.set(item.id, "PatchPassword", opened.password)
            return true
        } catch {
            SwitchAlert.show("압축파일을 여는 중 오류가 발생했습니다: \(SwitchBridge.errorMessage(error))", caption: "한글패치 지정", style: .critical)
            return false
        }
    }

    /// GetBulkPatchTargets: TitleID가 있는 항목
    private func bulkTargets(_ items: [RemoteObject]) -> [Int]? {
        let targets = items.filter { !$0.string("TitleID").isEmpty }.map(\.id)
        if targets.isEmpty {
            SwitchAlert.show("타이틀 정보가 있는 항목이 없습니다.", caption: Self.bulkCaption)
            return nil
        }
        return targets
    }

    /// BulkPatchMenu_FromFolder_Click
    private func bulkFromFolder(_ items: [RemoteObject]) {
        guard let targets = bulkTargets(items),
              let folder = SwitchPanels.openFolder(title: "한글패치 루트 폴더 선택 (titleId 이름의 폴더 또는 titleId.zip/titleId.7z 파일을 자동 매칭합니다)")
        else { return }

        Task {
            let matched = await engine.callStatic("RomForge.Controls.Switch.SwitchBulkPatchMatcher", "MatchFromFolder",
                                                  [EngineClient.refs(targets), .string(folder)])?.int ?? 0
            showBulkResult(targets.count, matched)
        }
    }

    /// BulkPatchMenu_FromArchive_Click
    private func bulkFromArchive(_ items: [RemoteObject]) {
        guard let targets = bulkTargets(items),
              let path = SwitchPanels.openFiles(title: "한글패치 루트 압축파일 선택 (안에서 titleId 이름의 폴더를 자동 매칭합니다)",
                                                extensions: ["zip", "7z"]).first
        else { return }

        Task {
            let matched: Int
            do {
                let opened = try await SwitchBridge.openArchive(engine, path, keep: true)
                guard opened.opened, let archive = opened.archive else { return }

                // using var archive = opened.Value.Archive
                do {
                    matched = try await SwitchBridge.callStatic(engine, "RomForge.Controls.Switch.SwitchBulkPatchMatcher", "MatchFromArchive",
                                                                [EngineClient.refs(targets), archive, .string(path), opened.password]).int ?? 0
                    await engine.call(archive.refId, "Dispose")
                } catch {
                    await engine.call(archive.refId, "Dispose")
                    throw error
                }
            } catch {
                SwitchAlert.show("압축파일을 여는 중 오류가 발생했습니다: \(SwitchBridge.errorMessage(error))", caption: Self.bulkCaption, style: .critical)
                return
            }

            showBulkResult(targets.count, matched)
        }
    }

    private func showBulkResult(_ total: Int, _ matched: Int) {
        SwitchAlert.show("\(total)개 중 \(matched)개에 패치 매칭됨.", caption: Self.bulkCaption)
    }
}

/// 패치 칸: 누르면 메뉴(폴더 선택/압축파일 선택), 파일 하나를 끌어다 놓으면 지정(PatchDropTarget_*)
private struct SwitchPatchCell: View {
    let item: RemoteObject
    let assign: (String) -> Void
    let selectFolder: () -> Void
    let selectArchive: () -> Void

    var body: some View {
        Menu {
            Button("폴더 선택...", action: selectFolder)
            Button("압축파일 선택(zip/7z)...", action: selectArchive)
        } label: {
            UpstreamAssets.menuImage((item.string("PatchIconSource") as NSString).lastPathComponent, size: 18)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(item.string("PatchDisplay"))
        .frame(maxWidth: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            // IsValidPatchDrop: 하나만
            guard urls.count == 1, let path = urls.first?.path else { return false }
            assign(path)
            return true
        }
    }
}
