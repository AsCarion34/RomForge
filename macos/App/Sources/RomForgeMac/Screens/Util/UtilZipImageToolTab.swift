// upstream: RomForge/Controls/Util/ZipImageToolTab.xaml(.cs)
// ViewModel: ZipImageToolMainViewModel (UtilMainViewModel.ZipImageToolVM)
import AppKit
import Combine
import SwiftUI

/// SD 굽기: 드라이브 선택 / [굽기 | 저장] 탭 / 상태 줄.
/// code-behind의 UsbDetector(Windows 장치 메시지) 대신 볼륨 마운트·해제 알림으로 드라이브 목록을 다시 읽는다.
struct UtilZipImageToolTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    private var isIdle: Bool { vm["IsIdle"]?.bool ?? true }

    var body: some View {
        ToolLayout(vm: vm, lists: ["UsbDrives", "SegmentSizeOptions", "CompressionLevelOptions", "LogEntries"]) {
            VStack(alignment: .leading, spacing: 6) {
                driveRow
                // TabControl SelectedIndex="{Binding SelectedTabIndex}": [굽기 | 저장]
                InnerTabs(titles: ["굽기", "저장"], selection: engine.int(vm, "SelectedTabIndex")) { index in
                    Group {
                        if index == 1 { readTab } else { writeTab }
                    }
                    .padding(8)
                }
                statusBar
            }
            .padding(8)
        }
        // ZipImageToolTab_Loaded → InitializeDrivesAsync
        .task(id: vm.id) { await initializeDrives() }
        // UsbDetector.DeviceChanged → 500ms 뒤 InitializeDrivesAsync
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            scheduleRefresh()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            scheduleRefresh()
        }
    }

    // MARK: 드라이브

    /// ComboBox ItemsSource=UsbDrives, SelectedItem=SelectedDrive, DisplayMemberPath=DisplayName
    private var driveRow: some View {
        HStack(spacing: 12) {
            UpstreamIcon(name: "Usb.png", size: 32)
            Picker("", selection: engine.selectedItem(vm, "SelectedDrive")) {
                ForEach(engine.items(vm, "UsbDrives")) { drive in
                    Text(drive.string("DisplayName")).tag(Optional(drive.id))
                }
            }
            .labelsHidden()
            .disabled(!isIdle)
        }
    }

    // MARK: 굽기

    private var writeTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                RemoteImage(value: vm["WriteFileIcon"], size: 24)
                TextField("", text: engine.string(vm, "WriteImagePath"))
                    .disabled(!isIdle)
                CommandIconButton(title: "열기", icon: "ReadOpen.png", vm: vm, command: "OpenWriteFileCommand", enabled: isIdle)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                // ToggleCommand: 작업 중에는 같은 버튼이 "취소"가 된다.
                CommandIconButton(title: vm.string("WriteButtonText"), icon: "SD.png", vm: vm, command: "WriteCommand")
            }
        }
    }

    // MARK: 저장

    private var readTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                RemoteImage(value: vm["ReadFileIcon"], size: 24)
                TextField("", text: engine.string(vm, "ReadImagePath"))
                    .disabled(!isIdle)
                CommandIconButton(title: "열기", icon: "WriteOpen.png", vm: vm, command: "OpenReadFileCommand", enabled: isIdle)
            }

            if vm["SegmentOptionsVisible"]?.bool == true {
                HStack(spacing: 8) {
                    UpstreamIcon(name: "Size.png", size: 24)
                    indexPicker(list: "SegmentSizeOptions", selection: "SelectedSegmentIndex")
                }
                HStack(spacing: 8) {
                    UpstreamIcon(name: "Compress.png", size: 24)
                    indexPicker(list: "CompressionLevelOptions", selection: "SelectedCompressionIndex")
                }
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                CommandIconButton(title: vm.string("ReadButtonText"), icon: "HDD.png", vm: vm, command: "ReadCommand")
            }
        }
    }

    /// ComboBox ItemsSource=문자열 목록, SelectedIndex=정수 속성
    private func indexPicker(list: String, selection: String) -> some View {
        let options = engine.store.items(vm.ref(list)).compactMap(\.string)

        return Picker("", selection: engine.int(vm, selection)) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Text(option).tag(index)
            }
        }
        .labelsHidden()
        .disabled(!isIdle)
    }

    // MARK: 상태 줄

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text(vm.string("StatusText1"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(vm.string("StatusText2"))
            if vm["IsLocked"]?.bool == true {
                ProgressView(value: min(max(vm["Progress"]?.double ?? 0, 0), 100), total: 100)
                    .frame(width: 150)
            }
        }
        .font(.callout)
        .frame(minHeight: 24)
    }

    // MARK: 드라이브 목록 갱신(code-behind InitializeDrivesAsync)

    private func scheduleRefresh() {
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await initializeDrives()
        }
    }

    /// DriveInfos.GetDriveInfos() → UsbDrives를 비우고 채운 뒤, 항목이 있으면 마지막 항목을 SelectedDrive로
    private func initializeDrives() async {
        guard let usbDrives = vm.ref("UsbDrives"),
              let infosId = await engine.callStatic("PickPack.Disk.DriveInfos", "GetDriveInfos")?.refId else { return }

        await engine.observeList(infosId)
        let infos = engine.store.items(infosId)

        await engine.call(usbDrives, "Clear")
        for info in infos {
            await engine.call(usbDrives, "Add", [info])
        }

        if let last = infos.last {
            await engine.set(vm.id, "SelectedDrive", last)
        }
    }
}
