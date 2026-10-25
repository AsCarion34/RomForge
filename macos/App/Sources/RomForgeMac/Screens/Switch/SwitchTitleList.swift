// upstream: RomForge/Controls/Switch/TitleListControl.xaml(.cs)
// ViewModel: RomForge.ViewModels.Switch.TitleListViewModel(컨트롤이 만든다), 항목 NSW.WPF.ViewModels.GameFile
import AppKit
import SwiftUI

/// 리팩 탭의 '파일' 목록. 파일 추가·교체·삭제·패치 지정은 엔진의 TitleListViewModel이 한다.
struct SwitchTitleList: View {
    @Environment(EngineClient.self) private var engine
    let list: SwitchGameFileList
    var enabled = true
    /// FileListChanged(파일 추가·삭제 후)
    let onFileListChanged: () -> Void

    @State private var selection = Set<Int>()

    private static let patchSource = "RomForge.Core.Services.Switch.PatchSource"
    private static let bulkMatcher = "RomForge.Core.Services.Switch.BulkPatchMatcher"
    /// TitleListViewModel.GetExpectedIds의 대리자 타입 Func<GameFile, IReadOnlyList<string>>
    private static let expectedIdsType = "System.Func`2[[NSW.WPF.ViewModels.GameFile, NSW.WPF],"
        + "[System.Collections.Generic.IReadOnlyList`1[[System.String, System.Private.CoreLib]], System.Private.CoreLib]]"

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
            // 머리글: Categories.png(글자 없음)
            TableColumn("") { item in
                SwitchBadge(text: item.string("FileType"), background: item["TypeBackground"]?.color, foreground: item["TypeForeground"]?.color)
                    .frame(maxWidth: .infinity)
            }
            .width(70)
            TableColumn("타이틀") { item in SwitchTitleCell(item: item).cellEnvironment(engine) }
                .width(min: 200, ideal: 300)
            TableColumn("버전") { item in
                Text(item.string("Version")).fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(90)
            TableColumn("패치") { item in
                SwitchPatchCell(item: item,
                                drop: { path in dropPatch(item, path) },
                                selectFolder: { selectPatchFolder(item) },
                                selectArchive: { selectPatchArchive(item) },
                                clear: { clearPatch(item) })
            }
            .width(80)
            // 머리글: Extension.png(글자 없음)
            TableColumn("") { item in
                SwitchBadge(text: item.string("Extension"), background: item["ExtensionBackground"]?.color, foreground: item["ExtensionForeground"]?.color)
                    .frame(maxWidth: .infinity)
            }
            .width(50)
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
                Button("선택 삭제") { removeFiles(ids, from: items) }
                Button("전체 삭제") { removeAll() }
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
            // BtnBulkPatch_Click: 단추의 ContextMenu를 연다.
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
            ToolIconButton(icon: "Clear.png", help: "전체 삭제") { removeAll() }
            ToolIconButton(icon: "Help.png", help: "도움말") {
                SwitchPanels.openURL("https://sinjunyoung.github.io/RomForge/switch-unpack-repack/")
            }
        }
    }

    // MARK: 파일 추가·삭제

    /// LvFiles_Drop / BtnAddFile_Click / BtnAddFolder_Click: _viewModel.AddFilesAsync(Common.Utils.ExpandPaths(paths))
    private func addFiles(_ paths: [String]) async {
        guard let titleVM = list.titleVMId else { return }
        let expanded = await SwitchBridge.expandPaths(engine, paths)
        await engine.call(titleVM, "AddFilesAsync", [expanded])
        onFileListChanged()
    }

    /// BtnRemoveFile_Click: 선택 항목마다 _viewModel.RemoveFile(item)(패치 동기화 해제 → 제거 → 다시 정렬)
    private func removeFiles(_ ids: Set<Int>, from items: [RemoteObject]) {
        guard let titleVM = list.titleVMId, !ids.isEmpty else { return }
        let ordered = SwitchBridge.ordered(ids, in: items)
        selection.removeAll()

        Task {
            for id in ordered {
                await engine.call(titleVM, "RemoveFile", [EngineClient.ref(id)])
            }
            onFileListChanged()
        }
    }

    /// BtnRemoveAllFiles_Click: _viewModel.RemoveAllFiles()
    private func removeAll() {
        guard let titleVM = list.titleVMId else { return }
        selection.removeAll()

        Task {
            await engine.call(titleVM, "RemoveAllFiles")
            onFileListChanged()
        }
    }

    // MARK: 한글패치

    /// MenuItem_RemovePatch_Click: _viewModel.ClearPatch(file)
    private func clearPatch(_ item: RemoteObject) {
        guard let titleVM = list.titleVMId else { return }
        Task { await engine.call(titleVM, "ClearPatch", [EngineClient.ref(item.id)]) }
    }

    /// PatchMenu_SelectFolder_Click
    private func selectPatchFolder(_ item: RemoteObject) {
        if let folder = SwitchPanels.openFolder(title: "\(item.string("TitleName"))에 적용할 한글패치 폴더 선택") {
            Task { await assignFolderPatch(item, folder) }
        }
    }

    /// PatchMenu_SelectArchive_Click
    private func selectPatchArchive(_ item: RemoteObject) {
        let paths = SwitchPanels.openFiles(title: "\(item.string("TitleName"))에 적용할 한글패치 압축파일 선택", extensions: ["zip", "7z"])
        if let path = paths.first { Task { await assignArchivePatch(item, path) } }
    }

    /// PatchDropTarget_Drop: PatchDropValidator.IsValidPatchPath → 압축이면 TryAssignArchivePatchAsync, 아니면 폴더 패치
    private func dropPatch(_ item: RemoteObject, _ path: String) {
        Task {
            guard await engine.callStatic("Common.WPF.PatchDropValidator", "IsValidPatchPath", [.string(path)])?.bool == true else { return }

            if await engine.callStatic("Patch.Core.Services.ArchivePatchSourceFactory", "IsArchivePath", [.string(path)])?.bool == true {
                await assignArchivePatch(item, path)
            } else {
                await assignFolderPatch(item, path)
            }
        }
    }

    /// _viewModel.TryAssignPatch(file, PatchSource.FromFolder(path), null)
    private func assignFolderPatch(_ item: RemoteObject, _ folder: String) async {
        guard let titleVM = list.titleVMId,
              let source = await engine.callStatic(Self.patchSource, "FromFolder", [.string(folder)]), source.refId != nil else { return }
        await engine.call(titleVM, "TryAssignPatch", [EngineClient.ref(item.id), source, .null])
    }

    /// TryAssignArchivePatchAsync: 압축을 열고(비밀번호 확인) PatchSource.FromArchive → Dispose → TryAssignPatch
    @discardableResult
    private func assignArchivePatch(_ item: RemoteObject, _ archivePath: String) async -> Bool {
        guard let titleVM = list.titleVMId else { return false }

        do {
            let opened = try await SwitchBridge.openArchive(engine, archivePath, keep: true)
            guard opened.opened, let archive = opened.archive else { return false }

            let source: JSONValue
            do {
                source = try await SwitchBridge.callStatic(engine, Self.patchSource, "FromArchive", [.string(archivePath), archive])
            } catch {
                await engine.call(archive.refId, "Dispose")
                throw error
            }
            // opened.Value.Archive.Dispose()
            await engine.call(archive.refId, "Dispose")

            return try await engine.callThrowing(titleVM, "TryAssignPatch", [EngineClient.ref(item.id), source, opened.password]).bool ?? false
        } catch {
            await logArchiveError(titleVM, error)
            return false
        }
    }

    /// catch: _viewModel.AppendLog($"압축파일을 여는 중 오류가 발생했습니다: {ex.Message}", LogLevel.Error); await SoundPlayer.PlayErrorAsync();
    private func logArchiveError(_ titleVM: Int, _ error: Error) async {
        await SwitchBridge.appendLog(engine, titleVM, "압축파일을 여는 중 오류가 발생했습니다: \(SwitchBridge.errorMessage(error))", "Error")
        await SwitchBridge.playError(engine)
    }

    /// GetBulkPatchTargets: TitleID가 있는 항목. 없으면 _viewModel.AppendLog("타이틀 정보가 있는 항목이 없습니다.", LogLevel.Info)
    private func bulkTargets(_ titleVM: Int, _ items: [RemoteObject]) async -> [Int]? {
        let targets = items.filter { !$0.string("TitleID").isEmpty }.map(\.id)
        if targets.isEmpty {
            await SwitchBridge.appendLog(engine, titleVM, "타이틀 정보가 있는 항목이 없습니다.", "Info")
            return nil
        }
        return targets
    }

    /// BulkPatchMenu_FromFolder_Click: BulkPatchMatcher.MatchFromFolder(targets, folder, _viewModel.GetExpectedIds) → ProcessBulkPatchResult
    private func bulkFromFolder(_ items: [RemoteObject]) {
        guard let titleVM = list.titleVMId else { return }

        Task {
            guard let targets = await bulkTargets(titleVM, items),
                  let folder = SwitchPanels.openFolder(title: "한글패치 루트 폴더 선택 (titleId 이름의 폴더 또는 titleId.zip/titleId.7z 파일을 자동 매칭합니다)"),
                  let expectedIds = await SwitchBridge.methodDelegate(engine, type: Self.expectedIdsType, target: titleVM, method: "GetExpectedIds"),
                  let report = await engine.callStatic(Self.bulkMatcher, "MatchFromFolder", [EngineClient.refs(targets), .string(folder), expectedIds]),
                  report.refId != nil
            else { return }

            await engine.call(titleVM, "ProcessBulkPatchResult", [report])
        }
    }

    /// BulkPatchMenu_FromArchive_Click: 압축을 열고 BulkPatchMatcher.MatchFromArchive(…, _viewModel.GetExpectedIds) → ProcessBulkPatchResult
    private func bulkFromArchive(_ items: [RemoteObject]) {
        guard let titleVM = list.titleVMId else { return }

        Task {
            guard let targets = await bulkTargets(titleVM, items),
                  let path = SwitchPanels.openFiles(title: "한글패치 루트 압축파일 선택 (안에서 titleId 이름의 폴더를 자동 매칭합니다)",
                                                    extensions: ["zip", "7z"]).first
            else { return }

            do {
                let opened = try await SwitchBridge.openArchive(engine, path, keep: true)
                guard opened.opened, let archive = opened.archive else { return }

                // using var archive = opened.Value.Archive
                do {
                    guard let expectedIds = await SwitchBridge.methodDelegate(engine, type: Self.expectedIdsType, target: titleVM, method: "GetExpectedIds") else {
                        await engine.call(archive.refId, "Dispose")
                        return
                    }
                    let report = try await SwitchBridge.callStatic(engine, Self.bulkMatcher, "MatchFromArchive",
                                                                   [EngineClient.refs(targets), archive, .string(path), opened.password, expectedIds])
                    _ = try await engine.callThrowing(titleVM, "ProcessBulkPatchResult", [report])
                    await engine.call(archive.refId, "Dispose")
                } catch {
                    await engine.call(archive.refId, "Dispose")
                    throw error
                }
            } catch {
                await logArchiveError(titleVM, error)
            }
        }
    }
}

/// 패치 칸: 누르면 메뉴(폴더 선택 / 압축파일 선택 / 선택 취소), 파일 하나를 끌어다 놓으면 지정(PatchDropTarget_*)
private struct SwitchPatchCell: View {
    let item: RemoteObject
    let drop: (String) -> Void
    let selectFolder: () -> Void
    let selectArchive: () -> Void
    let clear: () -> Void

    var body: some View {
        Menu {
            Button("폴더 선택...", action: selectFolder)
            Button("압축파일 선택(zip/7z)...", action: selectArchive)
            Button("선택 취소", action: clear)
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
            drop(path)
            return true
        }
    }
}
