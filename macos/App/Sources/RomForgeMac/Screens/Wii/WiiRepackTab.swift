// upstream: RomForge/Controls/Wii/RepackTab.xaml(.cs)
// ViewModel: RomForge.ViewModels.Wii.RepackMainViewModel (WiiMainViewModel.RepackVM), GameInfo(GameDisplay), PatchInfo(PatchDisplay)
import SwiftUI

/// Wii 리팩 탭: [원본 | 패치] 드롭 영역, 언팩·리팩 버튼, 게임·패치 정보, 출력 포맷, 작업 폴더, 진행 상황 + 로그.
/// 암호가 걸린 패치 압축은 엔진이 비밀번호 입력 창(ui.password)을 띄운다.
struct WiiRepackTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    private static let viewModelType = "RomForge.ViewModels.Wii.RepackMainViewModel"
    private static let helpURL = "https://sinjunyoung.github.io/RomForge/wii-merge/"

    var body: some View {
        let idle = vm["IsIdle"]?.bool ?? true

        ToolLayout(vm: vm, lists: ["LogEntries"]) {
            VStack(alignment: .leading, spacing: 10) {
                dropZones(idle: idle)
                VStack(spacing: 5) {
                    modeButtons
                    Divider()
                }
                infoCards
                formatRow(idle: idle)
                outputRow(idle: idle)
                ToolProgressBar(vm: vm)
            }
            .padding(10)
        }
    }

    // MARK: 원본 / 패치

    /// DropZone 2개(IsEnabled = IsIdle).
    /// 원본: Drop → TxtRom_Drop, 클릭 → TxtRom_Click. 패치: Drop → TxtPatch_Drop, 클릭·오른쪽 클릭 → ContextMenu
    private func dropZones(idle: Bool) -> some View {
        HStack(spacing: 5) {
            WiiDropZone(enabled: idle, onDrop: dropDisc, onClick: chooseDisc) {
                WiiZoneLabel(icon: "DVD.png", path: vm.string("InputPath"),
                             hint: vm.isVisible("InputHintVisibility") ? "Wii 디스크(.iso, .wbfs, .wia, .rvz)를 드래그하거나 클릭하세요" : nil,
                             caption: "원본")
            }
            .help(vm.string("InputPath"))

            WiiDropZone(enabled: idle, onDrop: dropPatch, onClick: showPatchMenu) {
                WiiZoneLabel(icon: "Patch.png", path: vm.string("PatchPath"),
                             hint: vm.isVisible("PatchHintVisibility") ? "Riivolution 패치 폴더 또는 zip/7z/xml을 드래그하거나 클릭하세요" : nil,
                             caption: "패치")
            }
            .help(vm.string("PatchPath"))
            .contextMenu {
                Button(action: selectPatchFolder) { MenuLabel(title: "폴더 선택...", icon: "AddFolder.png") }
                    .disabled(!idle)
                Button(action: selectPatchFile) { MenuLabel(title: "파일 선택 (*.zip, *.7z, *.xml)...", icon: "ZipFolder.png") }
                    .disabled(!idle)
            }
        }
        .frame(height: 65)
    }

    /// TxtRom_Drop: 작업 중이 아니면 RepackMainViewModel.IsSupportedDisc를 만족하는 첫 경로를 InputPath로
    private func dropDisc(_ paths: [String]) {
        guard vm["IsIdle"]?.bool ?? true else { return }

        Task {
            for path in paths {
                if await engine.callStatic(Self.viewModelType, "IsSupportedDisc", [.string(path)])?.bool == true {
                    engine.string(vm, "InputPath").wrappedValue = path
                    return
                }
            }
        }
    }

    /// TxtPatch_Drop: 작업 중이 아니면 RiivolutionWorkspace.IsSupported를 만족하는 첫 경로를 PatchPath로
    private func dropPatch(_ paths: [String]) {
        guard vm["IsIdle"]?.bool ?? true else { return }

        Task {
            for path in paths {
                if await engine.callStatic("RomForge.Core.Services.Wii.RiivolutionWorkspace", "IsSupported", [.string(path)])?.bool == true {
                    engine.string(vm, "PatchPath").wrappedValue = path
                    return
                }
            }
        }
    }

    /// TxtRom_Click
    private func chooseDisc() {
        if let path = FilePanels.openFiles(title: "Wii 디스크 파일 선택", filter: "Wii 디스크 파일|*.iso;*.wbfs;*.rvz;*.wia|모든 파일|*.*").first {
            engine.string(vm, "InputPath").wrappedValue = path
        }
    }

    /// TxtPatch_MouseLeftButtonDown: Border.ContextMenu를 연다(MenuItem.Icon 24×24를 메뉴 크기 18로).
    private func showPatchMenu() {
        PopUpMenu.show([
            ContextMenuItem(title: "폴더 선택...", icon: "AddFolder.png", action: selectPatchFolder),
            ContextMenuItem(title: "파일 선택 (*.zip, *.7z, *.xml)...", icon: "ZipFolder.png", action: selectPatchFile),
        ], iconSize: 18)
    }

    /// SelectFolder_Click
    private func selectPatchFolder() {
        if let path = FilePanels.openFolder(title: "패치 폴더 선택") {
            engine.string(vm, "PatchPath").wrappedValue = path
        }
    }

    /// SelectFile_Click
    private func selectPatchFile() {
        let filter = "패치 파일 (*.zip;*.7z;*.xml)|*.zip;*.7z;*.xml|ZIP 파일 (*.zip)|*.zip|7Z 파일 (*.7z)|*.7z|XML 파일 (*.xml)|*.xml|모든 파일 (*.*)|*.*"
        if let path = FilePanels.openFiles(title: "패치 파일 선택", filter: filter).first {
            engine.string(vm, "PatchPath").wrappedValue = path
        }
    }

    // MARK: 실행 버튼

    /// IconButton 3개(열 너비 * : * : 2*). BtnXxx_Click: 작업 중이면 Cancel(), 아니면 StartAsync(BuildMode)
    private var modeButtons: some View {
        HStack(spacing: 5) {
            HStack(spacing: 5) {
                RunCancelButton(title: "언팩", icon: "Unpack.png",
                                isRunning: vm["IsUnpackRunning"]?.bool ?? false,
                                enabled: vm["UnpackEnabled"]?.bool ?? true) { click("UnpackOnly") }
                RunCancelButton(title: "리팩 (폴더 기반)", icon: "Repack.png",
                                isRunning: vm["IsRebuildRunning"]?.bool ?? false,
                                enabled: vm["RebuildEnabled"]?.bool ?? true) { click("RebuildOnly") }
            }
            RunCancelButton(title: "언팩 + 리팩 (스트리밍 기반)", icon: "UnRepack.png",
                            isRunning: vm["IsFullRunning"]?.bool ?? false,
                            enabled: vm["StartEnabled"]?.bool ?? true) { click("FullProcess") }
        }
    }

    private func click(_ mode: String) {
        if vm["IsLocked"]?.bool == true {
            engine.invoke(vm, "Cancel")
            return
        }
        // upstream은 StartAsync가 곧바로 IsLocked를 켠다. 엔진의 IsLocked가 도착하기 전 두 번째 클릭으로 두 번 시작하지 않게 막는다.
        guard !wiiRepackStarting.contains(vm.id) else { return }
        wiiRepackStarting.insert(vm.id)
        let id = vm.id
        Task {
            await engine.call(id, "StartAsync", [.string(mode)])
            wiiRepackStarting.remove(id)
        }
    }

    // MARK: 게임 정보 / 패치 정보

    /// 두 칸(* : *)이 남은 높이를 채운다. 정보가 없으면 그 칸은 비워 둔다(Visibility = Collapsed).
    private var infoCards: some View {
        HStack(alignment: .top, spacing: 5) {
            ZStack {
                if vm.isVisible("GameInfoVisibility") { gameInfo }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ZStack {
                if vm.isVisible("PatchInfoVisibility") { patchInfo }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gameInfo: some View {
        WiiDescribed(id: vm.ref("GameInfo")) { info in
            HStack(spacing: 12) {
                RemoteImage(value: vm["GameIcon"], size: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text(info.string("Title"))
                        .fontWeight(.semibold)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(info.string("Publisher"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(info.string("IdText"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                RemoteImage(value: engine.converted("RegionToImageConverter", info, "RegionKey"), size: 24)
                    .help(info.string("Region"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var patchInfo: some View {
        WiiDescribed(id: vm.ref("PatchInfo")) { info in
            VStack(alignment: .leading, spacing: 3) {
                Text("패치 정보")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 3)

                HStack(spacing: 8) {
                    Text(info.string("KindText"))
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.5)))
                    Text(info.string("XmlName"))
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Group {
                    Text(info.string("TargetText")).padding(.top, 3)
                    Text(info.string("FileCountText"))
                    Text(info.string("WarningText"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                // StatusText: IsError면 빨강, 아니면 초록(DataTrigger)
                Text(info.string("StatusText"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(info["IsError"]?.bool == true ? Color.red : Color.green)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: 출력 포맷 / 작업 폴더

    /// RadioButton IsChecked = IsIsoFormat / IsWbfsFormat / IsRvzFormat(OutputFormat Iso / Wbfs / Rvz) + 도움말(BtnHelp_Click)
    private func formatRow(idle: Bool) -> some View {
        HStack(spacing: 10) {
            Text("출력 포맷:").font(.subheadline.weight(.semibold))
            EnumPicker(vm: vm, prop: "OutputFormat",
                       labels: ["Iso": "ISO", "Wbfs": "WBFS ( USB 로더 )", "Rvz": "RVZ ( Dolphin 전용 압축 )"], style: .radio)
                .fixedSize()
                .disabled(!idle)
            Spacer()
            ToolIconButton(icon: "Help.png", help: "도움말", enabled: idle) {
                FilePanels.openURL(Self.helpURL)
            }
        }
    }

    /// TextBox(OutputPath, AllowDrop: TxtOutputPath_PreviewDragOver / TxtOutputPath_Drop) + 찾아보기(BrowseOutputCommand), IsEnabled = IsIdle
    private func outputRow(idle: Bool) -> some View {
        HStack(spacing: 5) {
            HStack {
                LiveTextField(title: "작업 폴더를 드래그하거나 선택하세요", vm: vm, prop: "OutputPath")
                    .textFieldStyle(.roundedBorder)
            }
            .folderDrop(engine, vm, "OutputPath", enabled: idle)

            ToolIconButton(icon: "AddFolder.png", enabled: engine.canRun(vm, "BrowseOutputCommand")) {
                engine.run(vm, "BrowseOutputCommand")
            }
        }
        .disabled(!idle)
    }
}

/// StartAsync를 부른 뒤 끝날 때까지의 RepackMainViewModel 번호
@MainActor private var wiiRepackStarting: Set<Int> = []

// MARK: - 보조 뷰

/// upstream DropZone 스타일 Border(Height 65): 드롭(PreviewDrop)과 클릭(MouseLeftButtonDown)을 받는다.
/// IsEnabled가 false이면 드롭·클릭을 받지 않는다.
private struct WiiDropZone<Content: View>: View {
    let enabled: Bool
    let onDrop: ([String]) -> Void
    let onClick: () -> Void
    @ViewBuilder var content: Content

    @State private var targeted = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6)

        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shape.fill(targeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08)))
            .overlay(shape.strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.35)))
            .contentShape(shape)
            .onTapGesture {
                if enabled { onClick() }
            }
            // Drag_Over: 파일 드롭이면 받는다(쓸 수 있는 경로인지는 Drop에서 고른다).
            .dropDestination(for: URL.self) { urls, _ in
                guard enabled, !urls.isEmpty else { return false }
                onDrop(urls.map(\.path))
                return true
            } isTargeted: { targeted = $0 && enabled }
            .opacity(enabled ? 1 : 0.55)
    }
}

/// DropZone 안: [아이콘 + 경로(비어 있으면 안내 문구)] 가운데, 오른쪽 위 작은 제목("원본" / "패치")
private struct WiiZoneLabel: View {
    let icon: String
    let path: String
    let hint: String?
    let caption: String

    var body: some View {
        HStack(spacing: 6) {
            UpstreamIcon(name: icon, size: 28)
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            } else {
                Text(path)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .padding(.trailing, 6)
        }
    }
}

/// GameInfo·PatchInfo(레코드)를 describe한 뒤 그린다. 불러오는 동안은 비워 둔다.
private struct WiiDescribed<Content: View>: View {
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
