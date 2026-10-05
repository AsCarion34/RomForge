// upstream: RomForge/Controls/3DS/InstallMainTab.xaml(.cs)
// ViewModel: InstallerMainViewModel (Main3DsVM.InstallerVM)
import AppKit
import Combine
import DiskArbitration
import SwiftUI

/// 3DS 설치: SD 카드 선택 + movable.sed, 하위 탭(설치된 게임목록 / 신규 게임 설치), 하단 상태 줄.
/// upstream code-behind는 UsbDetector(WM_DEVICECHANGE)로 SD 카드 연결을 감지해 드라이브 목록을 다시 만든다.
/// macOS에서는 NSWorkspace 마운트·언마운트 알림으로 같은 일(InitializeDrivesAsync)을 한다.
struct ThreeDSInstallMainTab: View {
    @Environment(EngineClient.self) private var engine
    let vmId: Int?

    /// SdDriveComboBox 항목(upstream DriveInfos)
    @State private var drives: [ThreeDSSdDrive] = []
    @State private var selectedDrive = ""
    /// 드라이브가 없을 때 code-behind는 MovablePathBox.Text만 비운다(ViewModel.MovablePath는 그대로).
    @State private var movableCleared = false

    private static let movableTip = "1. GodMode9 실행 ( START + POWER )\n2. SYSNAND CTRNAND → private → movable.sed 선택\n3. 가장 하단 Copy to 0:/gm9/out 실행"

    private static let tabs = [
        SubTab(title: "설치된 게임목록", icon: "List.png", vmProp: "InstalledTitles"),
        SubTab(title: "신규 게임 설치", icon: "Installer.png", vmProp: "Install"),
    ]

    var body: some View {
        ChildVM(id: vmId) { vm in
            let idle = vm["IsIdle"]?.bool ?? true

            VStack(spacing: 0) {
                header(vm, idle: idle)
                Divider()
                // 내부 TabControl(x:Name="Tab"): 두 탭 모두 DataContext가 InstallerMainViewModel이다.
                ThreeDSTabs(owner: vm, tabs: Self.tabs, memoryKey: "3ds.install.\(vm.id)", enabled: idle) { index, _ in
                    if index == 0 {
                        ThreeDSInstalledTitlesTab(vm: vm)
                    } else {
                        ThreeDSInstallTab(vm: vm)
                    }
                }
                Divider()
                statusBar(vm)
            }
            // MainTab_Loaded → InitializeDrivesAsync
            .task(id: vm.id) { await initializeDrives(vm, keepCurrent: true) }
            // UsbDetector.DeviceChanged → 500ms 뒤 InitializeDrivesAsync
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
                deviceChanged(vm)
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
                deviceChanged(vm)
            }
        }
    }

    // MARK: 상단(SD 카드 / movable.sed)

    private func header(_ vm: RemoteObject, idle: Bool) -> some View {
        HStack(spacing: 24) {
            HStack(spacing: 15) {
                UpstreamIcon(name: "SdCard.png", size: 32)
                Picker("", selection: driveSelection(vm)) {
                    ForEach(drives) { drive in
                        Text(drive.display).tag(drive.path)
                    }
                }
                .labelsHidden()
                .disabled(!idle || drives.isEmpty)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                UpstreamIcon(name: "Seed.png", size: 24)
                    .help(Self.movableTip)
                Text("movable.sed")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .help(Self.movableTip)
                    .padding(.trailing, 9)

                // MovablePathBox(IsReadOnly, Text="{Binding MovablePath, Mode=OneWay}")
                Text(movableCleared ? "" : vm.string("MovablePath"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                    .padding(.horizontal, 6)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                    .help(movableCleared ? "" : vm.string("MovablePath"))

                Button { browseMovable(vm) } label: { UpstreamIcon(name: "AddFile.png", size: 28) }
                    .buttonStyle(.borderless)
                    .padding(.leading, 9)
                    .disabled(!idle)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// SdDriveComboBox_SelectionChanged(사용자가 고를 때만. 코드가 바꿀 때는 _suppressSelectionChanged처럼 부르지 않는다)
    private func driveSelection(_ vm: RemoteObject) -> Binding<String> {
        Binding(get: { selectedDrive }, set: { path in
            guard path != selectedDrive else { return }
            selectedDrive = path
            Task { await selectDrive(vm, path) }
        })
    }

    /// ViewModel.SdPath = 드라이브; 비어 있지 않으면 CheckAndSetMovablePathAsync(SdPath)
    private func selectDrive(_ vm: RemoteObject, _ path: String) async {
        movableCleared = false
        await engine.set(vm.id, "SdPath", .string(path))
        guard !path.isEmpty else { return }
        await engine.call(vm.id, "CheckAndSetMovablePathAsync", [.string(path)])
    }

    /// BrowseMovable_Click: OpenFileDialog(Title "movable.sed 선택", Filter "movable.sed|movable.sed|모든 파일|*.*") → MovablePath
    private func browseMovable(_ vm: RemoteObject) {
        guard let path = ThreeDSDialogs.openFiles(title: "movable.sed 선택", filter: "movable.sed|movable.sed|모든 파일|*.*", multiple: false).first else { return }
        movableCleared = false
        engine.string(vm, "MovablePath").wrappedValue = path
    }

    // MARK: 드라이브 목록

    private func deviceChanged(_ vm: RemoteObject) {
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await initializeDrives(vm, keepCurrent: false)
        }
    }

    /// InitializeDrivesAsync: 드라이브 목록을 다시 만들고 마지막 드라이브를 골라 SdPath·movable.sed를 맞춘다.
    /// keepCurrent: 화면이 다시 만들어진 경우(upstream은 컨트롤이 살아 있어 Loaded에서 한 번만 한다).
    /// ViewModel의 SdPath가 아직 연결돼 있으면 사용자가 고른 드라이브·movable.sed를 그대로 둔다.
    private func initializeDrives(_ vm: RemoteObject, keepCurrent: Bool) async {
        let volumes = await Task.detached(priority: .userInitiated) { ThreeDSVolumeScanner.scan() }.value

        var entries: [ThreeDSSdDrive] = []
        for volume in volumes {
            entries.append(ThreeDSSdDrive(path: volume.path, display: await displayName(volume) ?? volume.path))
        }
        drives = entries

        let current = vm.string("SdPath")

        guard let last = entries.last else {
            // 드라이브 없음: SdPath = "", MovablePathBox.Text = "", 콤보 비활성
            selectedDrive = ""
            movableCleared = true
            if !current.isEmpty { await engine.set(vm.id, "SdPath", .string("")) }
            return
        }

        if keepCurrent, entries.contains(where: { $0.path == current }) {
            selectedDrive = current
            movableCleared = false
            return
        }

        selectedDrive = last.path
        await selectDrive(vm, last.path)
    }

    /// ComboBox 항목 표시는 DriveInfos.ToString()이다. 같은 upstream 클래스로 만든다.
    /// ("[드라이브] (용량) 모델". macOS에서는 드라이브 문자 대신 마운트 경로)
    private func displayName(_ volume: ThreeDSVolume) async -> String? {
        let args: [JSONValue] = [
            .string(volume.devicePath), .string(volume.model), .number(Double(volume.sizeBytes)),
            .int(volume.diskNumber), .string(volume.path),
        ]
        guard let id = await engine.create("PickPack.Disk.DriveInfos", args) else { return nil }
        let text = await engine.call(id, "ToString")?.string
        _ = try? await engine.request("release", ["objs": .array([.int(id)])])
        return text
    }

    // MARK: 하단 상태 줄

    private func statusBar(_ vm: RemoteObject) -> some View {
        let busy = vm.isVisible("ProgressPanelVisibility")

        return HStack(spacing: 10) {
            Text(vm.string("StatusMessage"))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if busy {
                Text(vm.string("ProgressSpeed")).foregroundStyle(.secondary)
                Text(vm.string("ProgressTime"))
            }
            if vm.isVisible("CancelButtonVisibility") {
                // Cancel_Click → CancelExtract()
                Button("취소") { engine.invoke(vm, "CancelExtract") }
                    .controlSize(.small)
            }
            if busy {
                ProgressView(value: min(max((vm["Progress"]?.double ?? 0) / 100, 0), 1))
                    .frame(width: 140)
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - SD 카드(드라이브) 찾기

struct ThreeDSSdDrive: Identifiable, Hashable {
    /// DriveLetter 자리(마운트 경로). ViewModel.SdPath로 넘긴다.
    let path: String
    let display: String
    var id: String { path }
}

struct ThreeDSVolume: Sendable {
    let path: String
    let devicePath: String
    let model: String
    let sizeBytes: Int64
    let diskNumber: Int
}

/// upstream DriveInfos.GetDriveInfos() 자리. macOS 엔진의 DriveInfos는 빈 목록을 돌려주므로(물리 디스크 쓰기 미구현)
/// 연결된 로컬 볼륨 중 디스크 장치가 있는 것(시동 디스크 제외)을 찾는다. upstream처럼 이동식·고정 디스크를 모두 넣는다.
enum ThreeDSVolumeScanner {
    static func scan() -> [ThreeDSVolume] {
        let keys: [URLResourceKey] = [.volumeIsRootFileSystemKey, .volumeIsLocalKey, .volumeIsBrowsableKey, .volumeNameKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]),
              let session = DASessionCreate(kCFAllocatorDefault) else { return [] }

        return urls.compactMap { url -> ThreeDSVolume? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsRootFileSystem != true,
                  values.volumeIsLocal != false,
                  values.volumeIsBrowsable != false,
                  let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
                  let info = DADiskCopyDescription(disk) as? [String: Any],
                  let bsdName = info[kDADiskDescriptionMediaBSDNameKey as String] as? String
            else { return nil }

            // Win32_DiskDrive처럼 물리 디스크 전체의 크기·모델·번호
            let whole = DADiskCopyWholeDisk(disk).flatMap { DADiskCopyDescription($0) as? [String: Any] } ?? info
            let model = (info[kDADiskDescriptionDeviceModelKey as String] as? String)?
                .trimmingCharacters(in: .whitespaces)
            let size = (whole[kDADiskDescriptionMediaSizeKey as String] as? NSNumber)?.int64Value ?? 0
            let number = Int(String(bsdName.dropFirst(4).prefix { $0.isNumber })) ?? -1

            return ThreeDSVolume(path: url.path,
                                 devicePath: "/dev/" + bsdName,
                                 model: model?.nonEmpty ?? values.volumeName ?? "Unknown",
                                 sizeBytes: size,
                                 diskNumber: number)
        }
    }
}
