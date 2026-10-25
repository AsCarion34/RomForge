// upstream: RomForge/Controls/3DS/RepackTab.xaml(.cs)
// ViewModel: RepackMainViewModel (Main3DsVM.RepackVM), TitleViewModel(RomInfo), PatchDisplay(PatchInfo)
import AppKit
import SwiftUI

/// 3DS 리팩: 원본 / 패치 DropZone, 언팩·리팩 버튼, 롬 정보(게임명·배급사 수정)와 패치 정보, 출력 포맷, 작업 폴더, 진행 상황.
struct ThreeDSRepackTab: View {
    @Environment(EngineClient.self) private var engine
    let vmId: Int?

    /// code-behind SupportedExtensions(TxtRom_Drop)
    private static let romExtensions: Set<String> = ["3ds", "cci", "zcci", "cia"]
    private static let helpURL = URL(string: "https://sinjunyoung.github.io/RomForge/3ds-merge/")!

    var body: some View {
        ChildVM(id: vmId) { vm in
            let idle = vm["IsIdle"]?.bool ?? true

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    romZone(vm, idle: idle)
                    patchZone(vm, idle: idle)
                }
                .frame(height: 65)

                modeButtons(vm)
                Divider()

                infoRow(vm, idle: idle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                formatRow(vm, idle: idle)
                outputRow(vm, idle: idle)

                // progressArea
                ToolProgressBar(vm: vm)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(10)
        }
    }

    // MARK: 원본 / 패치

    /// 원본 DropZone: Cartridge.png + InputPath(비어 있으면 안내). 클릭하면 TxtRom_Click, 드롭하면 TxtRom_Drop.
    private func romZone(_ vm: RemoteObject, idle: Bool) -> some View {
        let hint = vm.isVisible("InputHintVisibility")

        return ThreeDSDropZone(icon: "Cartridge.png", caption: "원본",
                               text: hint ? "롬파일(.3ds, .cci, .zcci, .cia)을 드래그하거나 클릭하세요" : vm.string("InputPath"),
                               isHint: hint,
                               // ToolTip="{Binding InputPath}"(값이 있을 때만)
                               tooltip: vm.string("InputPath"),
                               enabled: idle,
                               onClick: { browseRom(vm) },
                               onDrop: { urls in dropRom(vm, urls) })
    }

    /// 패치 DropZone: Patch.png + PatchPath(비어 있으면 안내). 왼쪽 클릭(TxtPatch_MouseLeftButtonDown)·오른쪽 클릭 모두
    /// Border.ContextMenu [폴더 선택... | 파일 선택 (*.zip, *.7z)...]를 연다. 드롭하면 TxtPatch_Drop.
    private func patchZone(_ vm: RemoteObject, idle: Bool) -> some View {
        let hint = vm.isVisible("PatchHintVisibility")

        return ThreeDSDropZone(icon: "Patch.png", caption: "패치",
                               text: hint ? "패치 폴더 또는 zip/7z파일을 드래그하거나 클릭하세요" : vm.string("PatchPath"),
                               isHint: hint,
                               // ToolTip="{Binding PatchPath}". upstream은 ToolTipService.IsEnabled를 InputPath 값 유무에 묶었다.
                               tooltip: vm.string("InputPath").isEmpty ? "" : vm.string("PatchPath"),
                               enabled: idle,
                               onClick: { ThreeDSPopupMenu.show(patchMenu(vm)) },
                               onDrop: { urls in dropPatch(vm, urls) },
                               menu: patchMenu(vm))
    }

    private func patchMenu(_ vm: RemoteObject) -> [ThreeDSMenuItem] {
        [
            ThreeDSMenuItem(title: "폴더 선택...", icon: "AddFolder.png") { selectPatchFolder(vm) },
            ThreeDSMenuItem(title: "파일 선택 (*.zip, *.7z)...", icon: "ZipFolder.png") { selectPatchFile(vm) },
        ]
    }

    /// TxtRom_Click: OpenFileDialog(Title "3DS 롬 파일 선택") → InputPath
    private func browseRom(_ vm: RemoteObject) {
        guard let path = ThreeDSDialogs.openFiles(title: "3DS 롬 파일 선택",
                                                  filter: "3DS 롬 파일|*.3ds;*.cci;*.zcci;*.cia|모든 파일|*.*",
                                                  multiple: false).first else { return }
        engine.string(vm, "InputPath").wrappedValue = path
    }

    /// SelectFolder_Click: OpenFolderDialog(Title "패치 폴더 선택") → PatchPath
    private func selectPatchFolder(_ vm: RemoteObject) {
        guard let path = ThreeDSDialogs.openFolder(title: "패치 폴더 선택") else { return }
        engine.string(vm, "PatchPath").wrappedValue = path
    }

    /// SelectFile_Click: OpenFileDialog(Title "패치 파일 선택", zip/7z) → PatchPath
    private func selectPatchFile(_ vm: RemoteObject) {
        guard let path = ThreeDSDialogs.openFiles(title: "패치 파일 선택",
                                                  filter: "패치 파일 (*.zip;*.7z)|*.zip;*.7z|ZIP 파일 (*.zip)|*.zip|7Z 파일 (*.7z)|*.7z",
                                                  multiple: false).first else { return }
        engine.string(vm, "PatchPath").wrappedValue = path
    }

    /// TxtRom_Drop: 첫 파일이 지원 확장자면 InputPath
    private func dropRom(_ vm: RemoteObject, _ urls: [URL]) -> Bool {
        if let first = urls.first, Self.romExtensions.contains(first.pathExtension.lowercased()) {
            engine.string(vm, "InputPath").wrappedValue = first.path
        }
        return true
    }

    /// TxtPatch_Drop: upstream PatchDropValidator.IsValidPatchPath를 만족하는 첫 경로를 PatchPath로
    private func dropPatch(_ vm: RemoteObject, _ urls: [URL]) -> Bool {
        let paths = urls.map(\.path)
        Task {
            for path in paths {
                if await engine.callStatic("Common.WPF.PatchDropValidator", "IsValidPatchPath", [.string(path)])?.bool == true {
                    engine.string(vm, "PatchPath").wrappedValue = path
                    return
                }
            }
        }
        return true
    }

    // MARK: 실행 버튼

    /// IconButton 3개(1:1:2). BtnXxx_Click: 작업 중이면 Cancel(), 아니면 StartAsync(BuildMode)
    private func modeButtons(_ vm: RemoteObject) -> some View {
        GeometryReader { geo in
            let unit = max((geo.size.width - 10) / 4, 0)
            HStack(spacing: 5) {
                RunCancelButton(title: "언팩", icon: "Unpack.png", isRunning: vm["IsUnpackRunning"]?.bool ?? false) {
                    click(vm, "UnpackOnly")
                }
                .frame(width: unit)
                .disabled(!(vm["UnpackEnabled"]?.bool ?? true))

                RunCancelButton(title: "리팩 (폴더 기반)", icon: "Repack.png", isRunning: vm["IsRebuildRunning"]?.bool ?? false) {
                    click(vm, "RebuildOnly")
                }
                .frame(width: unit)
                .disabled(!(vm["RebuildEnabled"]?.bool ?? true))

                RunCancelButton(title: "언팩 + 리팩 (스트리밍 기반)", icon: "UnRepack.png", isRunning: vm["IsFullRunning"]?.bool ?? false) {
                    click(vm, "FullProcess")
                }
                .frame(width: unit * 2)
                .disabled(!(vm["StartEnabled"]?.bool ?? true))
            }
        }
        .frame(height: 36)
    }

    /// 패치 정보를 읽는 동안(RefreshPatchAsync)도 IsLocked라 세 번째 버튼이 "취소"가 되고, 누르면 Cancel()이 패치 읽기를 멈춘다.
    private func click(_ vm: RemoteObject, _ mode: String) {
        if vm["IsLocked"]?.bool == true {
            engine.invoke(vm, "Cancel")
            return
        }
        // upstream은 StartAsync가 곧바로 IsLocked를 켠다. 엔진의 IsLocked가 도착하기 전 두 번째 클릭으로 두 번 시작하지 않게 막는다.
        guard !threeDSRepackStarting.contains(vm.id) else { return }
        threeDSRepackStarting.insert(vm.id)
        let id = vm.id
        Task {
            await engine.call(id, "StartAsync", [.string(mode)])
            threeDSRepackStarting.remove(id)
        }
    }

    // MARK: 롬 정보 / 패치 정보

    /// 왼쪽 롬 정보(RomInfoVisibility), 오른쪽 패치 정보(PatchInfoVisibility). 두 칸은 너비가 같고 숨겨진 칸은 비워 둔다.
    private func infoRow(_ vm: RemoteObject, idle: Bool) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Group {
                if vm.isVisible("RomInfoVisibility") {
                    ThreeDSDescribed(id: vm.ref("RomInfo")) { info in romInfo(info, idle: idle) }
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Group {
                if vm.isVisible("PatchInfoVisibility") {
                    ThreeDSDescribed(id: vm.ref("PatchInfo")) { info in ThreeDSPatchInfoBox(info: info) }
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // 두 상자의 높이를 큰 쪽에 맞춘다.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func romInfo(_ info: RemoteObject, idle: Bool) -> some View {
        HStack(spacing: 12) {
            RemoteImage(value: info["Icon"], size: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                // TextBox MaxLength="63"
                ThreeDSTextField(title: "", vm: info, prop: "ShortDescription", maxLength: 63)
                    .font(.body.weight(.semibold))
                    .help("게임명 (최대 63자)")
                ThreeDSTextField(title: "", vm: info, prop: "Publisher", maxLength: 63)
                    .font(.caption)
                    .help("배급사 (최대 63자)")
                Text("\(info.string("ProductCode")) · \(info.string("TitleId"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .textFieldStyle(.roundedBorder)
            .disabled(!idle)

            HStack(spacing: 8) {
                ThreeDSRegionCell(item: info)
                ThreeDSLockCell(item: info)
            }
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: 출력 포맷

    private func formatRow(_ vm: RemoteObject, idle: Bool) -> some View {
        HStack(spacing: 10) {
            Text("출력 포맷:").font(.subheadline.weight(.semibold))
            Picker("", selection: radio(vm, ["IsCciFormat", "IsCiaFormat", "IsZcciFormat"])) {
                Text("CCI ( 에뮬레이터 )").tag("IsCciFormat")
                Text("CIA ( 실기 )").tag("IsCiaFormat")
                Text("ZCCI ( Azahar 전용 압축 )").tag("IsZcciFormat")
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .labelsHidden()
            .disabled(!idle)

            Spacer()

            // BtnHelp_Click
            Button { NSWorkspace.shared.open(Self.helpURL) } label: { UpstreamIcon(name: "Help.png", size: 24) }
                .buttonStyle(.borderless)
                .help("도움말")
                .disabled(!idle)
        }
    }

    /// RadioButton IsChecked="{Binding IsXxxFormat}" 묶음. WPF처럼 다른 단추는 false, 고른 단추는 true로 보낸다.
    private func radio(_ vm: RemoteObject, _ props: [String]) -> Binding<String> {
        Binding(get: { props.first { vm[$0]?.bool == true } ?? "" },
                set: { selected in
                    for prop in props where prop != selected { engine.bool(vm, prop).wrappedValue = false }
                    engine.bool(vm, selected).wrappedValue = true
                })
    }

    // MARK: 작업 폴더

    /// TextBox(OutputPath, 비어 있으면 안내) + 폴더 버튼(BrowseOutputCommand). 폴더를 끌어다 놓을 수 있다.
    private func outputRow(_ vm: RemoteObject, idle: Bool) -> some View {
        HStack(spacing: 5) {
            HStack {
                ThreeDSTextField(title: "작업 폴더를 드래그하거나 선택하세요", vm: vm, prop: "OutputPath")
                    .textFieldStyle(.roundedBorder)
                    .disabled(!idle)
            }
            .dropDestination(for: URL.self) { urls, _ in dropOutput(vm, urls, idle: idle) }

            Button { engine.run(vm, "BrowseOutputCommand") } label: { UpstreamIcon(name: "AddFolder.png", size: 24) }
                .buttonStyle(.borderless)
                .disabled(!idle || !engine.canRun(vm, "BrowseOutputCommand"))
        }
    }

    /// TxtOutputPath_PreviewDragOver: 첫 경로가 있는 폴더일 때만 놓을 수 있다. TxtOutputPath_Drop: 그 폴더를 OutputPath로.
    private func dropOutput(_ vm: RemoteObject, _ urls: [URL], idle: Bool) -> Bool {
        guard idle, let first = urls.first else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: first.path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
        engine.string(vm, "OutputPath").wrappedValue = first.path
        return true
    }
}

/// StartAsync를 부른 뒤 끝날 때까지의 RepackMainViewModel 번호
@MainActor private var threeDSRepackStarting: Set<Int> = []

// MARK: - 패치 정보

/// 패치 정보 상자(PatchInfo: PatchDisplay): 종류 배지 + 이름, 대상 타이틀 ID, 파일 수, 상태(IsError면 빨강, 아니면 초록)
private struct ThreeDSPatchInfoBox: View {
    let info: RemoteObject

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("패치 정보")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            HStack(spacing: 8) {
                Text(info.string("KindText"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                Text(info.string("Name"))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text(info.string("TargetText"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 6)
            Text(info.string("FileCountText"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 3)
            // TextWrapping="Wrap"
            Text(info.string("StatusText"))
                .font(.callout.weight(.semibold))
                .foregroundStyle(info["IsError"]?.bool == true ? Color.red : Color.green)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - DropZone

/// ContextMenu의 MenuItem(Header, Icon, Click)
private struct ThreeDSMenuItem {
    let title: String
    let icon: String
    let action: @MainActor () -> Void
}

/// upstream DropZone 스타일 Border(높이 65): 가운데 [아이콘 + 경로 또는 안내], 오른쪽 위 작은 제목.
/// 왼쪽 클릭과 파일 드롭을 받고, menu가 있으면 오른쪽 클릭 메뉴(Border.ContextMenu)도 붙인다.
/// IsEnabled="{Binding IsIdle}"가 꺼지면 모두 막는다.
private struct ThreeDSDropZone: View {
    let icon: String
    let caption: String
    let text: String
    let isHint: Bool
    let tooltip: String
    let enabled: Bool
    let onClick: () -> Void
    let onDrop: ([URL]) -> Bool
    var menu: [ThreeDSMenuItem] = []

    @State private var targeted = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8)

        HStack(spacing: 6) {
            UpstreamIcon(name: icon, size: 28)
            Text(text)
                .font(isHint ? .caption : .callout)
                .foregroundStyle(isHint ? .tertiary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 3)
                .padding(.trailing, 6)
        }
        .background(shape.fill(targeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06)))
        .overlay(shape.strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.35),
                                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .contentShape(shape)
        .onTapGesture {
            if enabled { onClick() }
        }
        .contextMenu {
            if enabled {
                ForEach(menu.indices, id: \.self) { index in
                    Button(action: menu[index].action) {
                        ThreeDSMenuLabel(title: menu[index].title, icon: menu[index].icon)
                    }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard enabled, !urls.isEmpty else { return false }
            return onDrop(urls)
        } isTargeted: { targeted = $0 && enabled }
        .help(tooltip)
        .opacity(enabled ? 1 : 0.55)
    }
}

/// TxtPatch_MouseLeftButtonDown(ContextMenu.PlacementTarget = 요소, IsOpen = true) 자리.
/// SwiftUI contextMenu는 코드로 열 수 없으므로 같은 항목의 NSMenu를 마우스 위치에 띄운다.
@MainActor
private enum ThreeDSPopupMenu {
    static func show(_ items: [ThreeDSMenuItem]) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for item in items {
            let target = Target(item.action)
            let menuItem = NSMenuItem(title: item.title, action: #selector(Target.click), keyEquivalent: "")
            menuItem.target = target
            menuItem.representedObject = target   // NSMenuItem.target은 약한 참조라 항목이 붙잡아 둔다.
            menuItem.image = icon(item.icon)
            menu.addItem(menuItem)
        }

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// 메뉴 아이콘. 원본 PNG(수백 px)를 그대로 넣으면 메뉴가 커지므로 크기를 정한 사본을 쓴다.
    private static func icon(_ name: String, size: CGFloat = 16) -> NSImage? {
        guard let copy = UpstreamAssets.nsImage(name)?.copy() as? NSImage else { return nil }
        copy.size = NSSize(width: size, height: size)
        return copy
    }

    @MainActor
    private final class Target: NSObject {
        let action: @MainActor () -> Void

        init(_ action: @escaping @MainActor () -> Void) {
            self.action = action
        }

        /// MenuItem Click
        @objc func click() { action() }
    }
}
