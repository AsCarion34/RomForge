// upstream: RomForge/Controls/PSVita/RepackTab.xaml(.cs)
// ViewModel: RomForge.ViewModels.PSVita.RepackMainViewModel (PSVitaMainViewModel.RepackVM), 항목 SourceRowViewModel
import SwiftUI

/// PS Vita > 리팩: pkg·zip·폴더 목록(종류 · 타이틀 · 키 · 패치 · 용량 · 경로), 출력 포맷 · 게임에 패치 병합 · 작업 폴더,
/// 언팩 / 리팩 (폴더 기반) / 언팩 + 리팩 (Full), 진행 줄.
struct PSVitaRepackTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    var body: some View {
        let idle = vm["IsIdle"]?.bool ?? true

        ToolLayout(vm: vm, lists: ["SourceRows", "LogEntries"]) {
            // Border IsEnabled="{Binding IsIdle}": 목록 + 오른쪽 버튼
            HStack(alignment: .top, spacing: 5) {
                rowsTable(idle: idle)
                PSVitaSideButtons(vm: vm)
            }
            .padding(5)
            .disabled(!idle)
        } options: {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    PSVitaRadioPair(vm: vm, title: "출력 포맷:",
                                    first: ("에뮬 (app, addcont)", "BuildEmu"),
                                    second: ("실기 (rePatch, reAddcont)", "BuildRetail"))

                    Toggle(isOn: engine.bool(vm, "MergePatchIntoGame")) {
                        HStack(spacing: 12) {
                            Text("게임에 패치 병합").bold()
                            Text("에뮬: 복호화 후 app/addcont 덮어씌우기 / 실기: rePatch/reAddcont 추가")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 작업 폴더: OutputPath TextBox(폴더 드롭, OutputHintVisibility 안내) + 폴더 선택(BrowseOutputCommand)
                    FolderPathRow(vm: vm, placeholder: "작업 폴더를 드래그하거나 선택하세요")
                }
                .disabled(!idle)

                // 열 너비 * : * : 2*. 실행 중인 단추만 "취소"가 되고 나머지는 꺼진다(XxxEnabled).
                HStack(spacing: 5) {
                    HStack(spacing: 5) {
                        RunCancelButton(title: "언팩", icon: "Unpack.png",
                                        isRunning: vm["IsUnpackRunning"]?.bool ?? false,
                                        enabled: vm["UnpackEnabled"]?.bool ?? true) { start("UnpackOnly") }
                        RunCancelButton(title: "리팩 (폴더 기반)", icon: "Repack.png",
                                        isRunning: vm["IsRebuildRunning"]?.bool ?? false,
                                        enabled: vm["RebuildEnabled"]?.bool ?? true) { start("RebuildOnly") }
                    }
                    RunCancelButton(title: "언팩 + 리팩 (Full)", icon: "UnRepack.png",
                                    isRunning: vm["IsFullRunning"]?.bool ?? false,
                                    enabled: vm["StartEnabled"]?.bool ?? true) { start("FullProcess") }
                }

                ToolProgressBar(vm: vm)
            }
        }
    }

    // MARK: - 목록

    private func rowsTable(idle: Bool) -> some View {
        Table(engine.items(vm, "SourceRows"), selection: engine.selectedItem(vm, "SelectedRow")) {
            TableColumn("종류") { row in
                PSVitaCategoryBadge(row: row)
            }
            .width(80)

            TableColumn("타이틀") { row in
                PSVitaTitleCell(row: row)
                    .cellEnvironment(engine)
            }
            .width(min: 160, ideal: 260)

            TableColumn("키") { row in
                PSVitaLicenseCell(row: row,
                                  editable: row["IsLicenseEditable"]?.bool ?? true,
                                  help: "라이선스 파일 경로(work.bin, *.rif) / zRIF 문자열")
                    .cellEnvironment(engine)
            }
            .width(100)

            TableColumn("패치") { row in
                PSVitaPatchCell(row: row)
                    .cellEnvironment(engine)
            }
            .width(75)

            TableColumn("용량") { row in
                PSVitaSizeCell(row: row)
            }
            .width(80)

            TableColumn("경로") { row in
                PSVitaPathCell(row: row)
            }
            .width(min: 120, ideal: 200)
        }
        .overlay {
            if vm.isVisible("EntriesHintVisibility") {
                PSVitaHint(title: "PS Vita 파일(pkg, zip)/폴더를 여기에 드래그&드롭하세요",
                           details: ["App/Patch/AddCont는 자동으로 분류됩니다",
                                     "pkg의 경우 키(work.bin, *.rif / zRIF 문자열)가 필요합니다"])
            }
        }
        // Root_Drop: 파일마다 AddSourceFile(순서대로)
        .dropDestination(for: URL.self) { urls, _ in
            guard idle, !urls.isEmpty else { return false }
            let paths = urls.map(\.path)
            let vmId = vm.id
            Task {
                for path in paths {
                    await engine.call(vmId, "AddSourceFile", [.string(path)])
                }
            }
            return true
        }
        // LvPkg_KeyUp(Delete): RemoveSelectedCommand(CanExecute일 때)
        .onDeleteCommand {
            if engine.canRun(vm, "RemoveSelectedCommand") { engine.run(vm, "RemoveSelectedCommand") }
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            PSVitaRowMenu(engine: engine, vm: vm, ids: ids)
        }
    }

    // MARK: - 동작

    /// BtnUnpack_Click / BtnRebuild_Click / BtnStart_Click → RunAsync(BuildMode)
    private func start(_ mode: String) {
        PSVitaUI.startOrCancel(engine, vm, [.string(mode)])
    }
}

/// 패치 열: PatchIconSource 아이콘(툴팁 PatchPath). 클릭하면 메뉴(PatchDropTarget_Click → Border.ContextMenu),
/// 폴더 · .zip · .7z 하나를 끌어다 놓으면 PatchPath에 넣는다(PatchDropTarget_Drop).
/// PatchPath는 upstream이 모든 행에 똑같이 맞춘다(RepackMainViewModel.Row_PropertyChanged).
private struct PSVitaPatchCell: View {
    @Environment(EngineClient.self) private var engine
    let row: RemoteObject

    var body: some View {
        Menu {
            Button {
                // PatchMenu_SelectFolder_Click
                if let path = FilePanels.openFolder(title: "한글 패치 폴더 선택") {
                    setPatch(path)
                }
            } label: {
                MenuLabel(title: "폴더 선택...", icon: "AddFolder.png")
            }
            Button {
                // PatchMenu_SelectArchive_Click
                if let path = FilePanels.openFiles(title: "한글 패치 압축파일 선택",
                                                   filter: "Archive Files (*.zip;*.7z)|*.zip;*.7z|All Files (*.*)|*.*").first {
                    setPatch(path)
                }
            } label: {
                MenuLabel(title: "압축파일 선택(zip/7z)...", icon: "ZipFolder.png")
            }
            Button {
                // MenuItem_RemovePatch_Click: SelectedRow.PatchPath = ""(패치 칸을 누르면 WPF가 그 행을 선택한다)
                setPatch("")
            } label: {
                MenuLabel(title: "선택 취소", icon: "Cancel.png")
            }
        } label: {
            UpstreamAssets.menuImage((row.string("PatchIconSource") as NSString).lastPathComponent, size: 18)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 32, height: 32)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        .help(row.string("PatchPath"))
        .frame(maxWidth: .infinity)
        // PatchDropTarget_Drop: 폴더 · .zip · .7z만 받는다
        .dropDestination(for: URL.self) { urls, _ in
            guard let path = urls.first?.path else { return false }
            let ext = (path as NSString).pathExtension.lowercased()
            guard FilePanels.isDirectory(path) || ext == "zip" || ext == "7z" else { return false }
            setPatch(path)
            return true
        }
    }

    private func setPatch(_ path: String) {
        engine.string(row, "PatchPath").wrappedValue = path
    }
}
