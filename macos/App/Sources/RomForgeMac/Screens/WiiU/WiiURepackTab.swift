// upstream: RomForge/Controls/WiiU/RepackTab.xaml(.cs)
// ViewModel: RomForge.ViewModels.WiiU.RepackMainViewModel (WiiUMainViewModel.RepackVM), 항목 RomForge.Core.Models.WiiU.TitleInputEntry
import AppKit
import SwiftUI

/// WiiU 리팩 탭: 타이틀 목록(본편/업데이트/DLC), 출력 포맷, 작업 폴더, 언팩 / 리팩 (폴더 기반) / 언팩 + 리팩 (Full).
struct WiiURepackTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    var body: some View {
        let idle = vm["IsIdle"]?.bool ?? true

        ToolLayout(vm: vm, lists: ["Entries", "LogEntries"]) {
            HStack(alignment: .top, spacing: 5) {
                entries
                VStack(spacing: 8) {
                    ToolIconButton(icon: "Delete.png", help: "선택 삭제",
                                   enabled: engine.canRun(vm, "RemoveSelectedCommand")) { engine.run(vm, "RemoveSelectedCommand") }
                    ToolIconButton(icon: "Clear.png", help: "모두 삭제",
                                   enabled: engine.canRun(vm, "RemoveAllCommand")) { engine.run(vm, "RemoveAllCommand") }
                }
                .frame(width: 40)
            }
            .padding(5)
            .disabled(!idle)
        } options: {
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 10) {
                        Text("출력 포맷:").fontWeight(.semibold)
                        // IsWuaFormat / IsWupFormat(OutputFormat Wua / Wup)
                        EnumPicker(vm: vm, prop: "OutputFormat", labels: ["Wua": "WUA ( 에뮬레이터 )", "Wup": "WUP ( 실기 )"], style: .radio)
                            .fixedSize()
                    }
                    .disabled(!idle)
                    Spacer()
                    ToolIconButton(icon: "Help.png", help: "도움말") {
                        WiiUPanels.openURL("https://sinjunyoung.github.io/RomForge/wiiu-repack/")
                    }
                }

                HStack(spacing: 5) {
                    TextField("작업 폴더를 선택하세요", text: engine.string(vm, "OutputPath"))
                        .textFieldStyle(.roundedBorder)
                    ToolIconButton(icon: "AddFolder.png") { engine.run(vm, "BrowseOutputCommand") }
                }
                .disabled(!idle)

                // 열 너비 * : * : 2*
                HStack(spacing: 5) {
                    HStack(spacing: 5) {
                        RunCancelButton(title: "언팩", icon: "Unpack.png",
                                       isRunning: vm["IsUnpackRunning"]?.bool ?? false,
                                       enabled: vm["UnpackEnabled"]?.bool ?? true) { start("UnpackOnly") }
                        RunCancelButton(title: "리팩 (폴더 기반)", icon: "Repack.png",
                                       isRunning: vm["IsRebuildRunning"]?.bool ?? false,
                                       enabled: vm["RebuildEnabled"]?.bool ?? true) { start("RebuildOnly") }
                    }
                    RunCancelButton(title: "언팩 + 리팩 (Full)", icon: "Run.png",
                                   isRunning: vm["IsFullRunning"]?.bool ?? false,
                                   enabled: vm["StartEnabled"]?.bool ?? true) { start("FullProcess") }
                }

                WiiUProgressRow(vm: vm)
            }
        }
    }

    // MARK: 목록

    private var entries: some View {
        let items = engine.items(vm, "Entries")

        return Table(items, selection: engine.selectedItem(vm, "SelectedEntry")) {
            TableColumn("종류") { item in
                WiiUBadge(text: item.string("Kind"), background: item["KindBackground"]?.color, foreground: .white)
            }
            .width(90)
            TableColumn("타이틀") { item in
                WiiUTitleCell(item: item, title: "DisplayName", subtitle: "TitleIdVersionDisplay", tooltip: "DisplayName")
                    .cellEnvironment(engine)
            }
            .width(min: 180, ideal: 260)
            TableColumn("패치") { item in
                WiiUPatchCell(item: item,
                              assign: { path in assignPatch(item, path) },
                              selectFolder: { selectPatchFolder(item) },
                              selectArchive: { selectPatchArchive(item) })
            }
            .width(80)
            TableColumn("용량") { item in
                Text(item.string("Size")).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(90)
            TableColumn("경로") { item in
                Text(item.string("FilePath")).lineLimit(1).truncationMode(.middle).help(item.string("FilePath"))
            }
            .width(min: 120, ideal: 220)
        }
        .overlay {
            if vm.isVisible("EntriesHintVisibility") {
                hint
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            // Root_Drop: 항목마다 AddDroppedItemAsync
            let paths = urls.map(\.path)
            Task {
                for path in paths {
                    await engine.call(vm.id, "AddDroppedItemAsync", [.string(path)])
                }
            }
            return !paths.isEmpty
        }
        .onDeleteCommand {
            // LvFiles_KeyUp: Entries.Remove(SelectedEntry)
            if let selected = vm["SelectedEntry"]?.refId { removeEntry(selected) }
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            if let id = ids.first {
                Button("폴더 열기") {
                    if let entry = engine.store.object(id) {
                        WiiUPanels.showFolder((entry.string("FilePath") as NSString).deletingLastPathComponent)
                    }
                }
                Divider()
                Button("한글패치 취소") {
                    // BtnRemovePatch_Click: SelectedEntry.PatchPath = null
                    Task { await engine.set(id, "PatchPath", .null) }
                }
                Divider()
                Button("선택 삭제") { removeEntry(id) }
                Button("전체 삭제") {
                    // BtnClear_Click: Entries.Clear()
                    Task { await engine.call(vm.ref("Entries"), "Clear") }
                }
            }
        }
    }

    private var hint: some View {
        VStack(spacing: 6) {
            UpstreamIcon(name: "drag.png", size: 28)
            Text("게임 파일 / 폴더를 여기에 드래그&드롭하세요").font(.headline)
            Text("본편/업데이트/DLC는 title ID로 자동 분류됩니다").foregroundStyle(.orange)
            HStack(spacing: 6) {
                ForEach(["WUD", "WUX", "WUA", "WUP", "Loadiine"], id: \.self) { WiiUBadge(text: $0) }
            }
            .padding(.top, 2)
        }
        .multilineTextAlignment(.center)
        .padding()
        .allowsHitTesting(false)
    }

    // MARK: 동작

    private func removeEntry(_ id: Int) {
        Task { await engine.call(vm.ref("Entries"), "Remove", [EngineClient.ref(id)]) }
    }

    /// BtnUnpack_Click / BtnRebuild_Click / BtnStart_Click
    private func start(_ mode: String) {
        if vm["IsLocked"]?.bool == true {
            engine.invoke(vm, "Cancel")
        } else {
            engine.invoke(vm, "StartAsync", [.string(mode)])
        }
    }

    /// PatchMenu_SelectFolder_Click
    private func selectPatchFolder(_ entry: RemoteObject) {
        if let folder = WiiUPanels.openFolder(title: "\(entry.string("TitleName"))에 적용할 한글패치 폴더 선택") {
            Task { await engine.set(entry.id, "PatchPath", .string(folder)) }
        }
    }

    /// PatchMenu_SelectArchive_Click
    private func selectPatchArchive(_ entry: RemoteObject) {
        let files = WiiUPanels.openFiles(title: "\(entry.string("TitleName"))에 적용할 한글패치 압축파일 선택", extensions: ["zip", "7z"])
        if let file = files.first {
            Task { await engine.set(entry.id, "PatchPath", .string(file)) }
        }
    }

    /// PatchDropTarget_Drop: PatchDropValidator.IsValidPatchPath면 PatchPath에 넣는다.
    private func assignPatch(_ entry: RemoteObject, _ path: String) {
        Task {
            if await engine.callStatic("Common.WPF.PatchDropValidator", "IsValidPatchPath", [.string(path)])?.bool == true {
                await engine.set(entry.id, "PatchPath", .string(path))
            }
        }
    }
}

/// 패치 칸: 누르면 메뉴(폴더 선택/압축파일 선택), 하나를 끌어다 놓으면 지정
private struct WiiUPatchCell: View {
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
            // PatchDropTarget_DragEnter: IsValidPatchDrop(하나만)
            guard urls.count == 1, let path = urls.first?.path else { return false }
            assign(path)
            return true
        }
    }
}
