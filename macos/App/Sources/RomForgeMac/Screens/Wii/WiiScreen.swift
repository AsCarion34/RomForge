// upstream: RomForge/Controls/Wii/MainTab.xaml(.cs)
// ViewModel: WiiMainViewModel (MainViewModel.WiiMainVM), WiiGameDisplay(GameInfo), WiiPatchDisplay(PatchInfo)
import AppKit
import SwiftUI

/// Wii 탭: 원본 디스크 / Riivolution 패치 / 작업 폴더, 언팩·리팩 버튼, 게임·패치 정보, 출력 포맷, 진행 상황 + 로그.
/// 암호가 걸린 패치 압축은 엔진이 비밀번호 입력 창(ui.password)을 띄운다.
struct WiiScreen: View {
    @Environment(EngineClient.self) private var engine
    let vmId: Int

    var body: some View {
        ChildVM(id: vmId) { vm in
            ToolLayout(vm: vm, lists: ["LogEntries"]) {
                WiiMainContent(vm: vm)
            }
        }
    }
}

private struct WiiMainContent: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    var body: some View {
        let idle = vm["IsIdle"]?.bool ?? true

        VStack(alignment: .leading, spacing: 10) {
            discRow(idle: idle)
            HStack(alignment: .top, spacing: 10) {
                patchColumn(idle: idle)
                outputColumn(idle: idle)
            }
            modeButtons
            HStack(alignment: .top, spacing: 6) {
                gameInfo
                    .frame(maxWidth: .infinity, alignment: .top)
                patchInfo
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            formatRow(idle: idle)
            WiiProgressFooter(vm: vm)
        }
        .padding(10)
    }

    // MARK: 입력

    private func discRow(idle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("원본 디스크").font(.subheadline.weight(.semibold))
            HStack(spacing: 5) {
                HStack {
                    WiiTextField(title: "Wii 디스크(.iso)를 드래그&드롭하세요", vm: vm, prop: "InputPath")
                        .textFieldStyle(.roundedBorder)
                        .disabled(!idle)
                }
                .dropDestination(for: URL.self) { urls, _ in dropDisc(urls) }

                WiiBrowseButton(vm: vm, command: "BrowseInputCommand", icon: "AddFile.png", enabled: idle)
            }
        }
    }

    private func patchColumn(idle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Riivolution 패치 (폴더 or zip,7z,xml)").font(.subheadline.weight(.semibold))
            HStack(spacing: 5) {
                HStack {
                    WiiPatchPathField(vm: vm)
                        .disabled(!idle)
                }
                .dropDestination(for: URL.self) { urls, _ in dropPatch(urls) }

                WiiBrowseButton(vm: vm, command: "BrowsePatchFolderCommand", icon: "AddFolder.png", enabled: idle, help: "패치 폴더 선택")
                WiiBrowseButton(vm: vm, command: "BrowsePatchFileCommand", icon: "ZipFolder.png", enabled: idle, help: "zip / 7z / xml 선택")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func outputColumn(idle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("작업 폴더").font(.subheadline.weight(.semibold))
            HStack(spacing: 5) {
                WiiTextField(title: "작업 폴더를 선택하세요", vm: vm, prop: "OutputPath")
                    .textFieldStyle(.roundedBorder)
                    .disabled(!idle)
                WiiBrowseButton(vm: vm, command: "BrowseOutputCommand", icon: "AddFolder.png", enabled: idle)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// TxtRom_Drop: 작업 중이 아니면, 존재하는 .iso 파일 중 첫 번째를 InputPath로
    private func dropDisc(_ urls: [URL]) -> Bool {
        guard vm["IsIdle"]?.bool ?? true else { return true }

        let iso = urls.first { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
                && url.pathExtension.caseInsensitiveCompare("iso") == .orderedSame
        }
        if let iso { engine.string(vm, "InputPath").wrappedValue = iso.path }
        return true
    }

    /// TxtPatch_Drop: 작업 중이 아니면, upstream RiivolutionWorkspace.IsSupported를 만족하는 첫 경로를 PatchPath로
    private func dropPatch(_ urls: [URL]) -> Bool {
        guard vm["IsIdle"]?.bool ?? true else { return true }

        let paths = urls.map(\.path)
        Task {
            for path in paths {
                if await engine.callStatic("RomForge.Core.Services.Wii.RiivolutionWorkspace", "IsSupported", [.string(path)])?.bool == true {
                    engine.string(vm, "PatchPath").wrappedValue = path
                    return
                }
            }
        }
        return true
    }

    // MARK: 실행 버튼

    /// IconButton 3개(1:1:2). BtnXxx_Click: 작업 중이면 Cancel(), 아니면 StartAsync(BuildMode)
    private var modeButtons: some View {
        GeometryReader { geo in
            let unit = max((geo.size.width - 10) / 4, 0)
            HStack(spacing: 5) {
                RunCancelButton(title: "언팩", icon: "Unpack.png", isRunning: vm["IsUnpackRunning"]?.bool ?? false) {
                    click("UnpackOnly")
                }
                .frame(width: unit)
                .disabled(!(vm["UnpackEnabled"]?.bool ?? true))

                RunCancelButton(title: "리팩 (폴더 기반)", icon: "Repack.png", isRunning: vm["IsRebuildRunning"]?.bool ?? false) {
                    click("RebuildOnly")
                }
                .frame(width: unit)
                .disabled(!(vm["RebuildEnabled"]?.bool ?? true))

                RunCancelButton(title: "언팩 + 리팩 (스트리밍 기반)", icon: "Run.png", isRunning: vm["IsFullRunning"]?.bool ?? false) {
                    click("FullProcess")
                }
                .frame(width: unit * 2)
                .disabled(!(vm["StartEnabled"]?.bool ?? true))
            }
        }
        .frame(height: 36)
    }

    private func click(_ mode: String) {
        if vm["IsLocked"]?.bool == true {
            engine.invoke(vm, "Cancel")
            return
        }
        // upstream은 StartAsync가 곧바로 IsLocked를 켠다. 엔진의 IsLocked가 도착하기 전 두 번째 클릭으로 두 번 시작하지 않게 막는다.
        guard !wiiStarting.contains(vm.id) else { return }
        wiiStarting.insert(vm.id)
        let id = vm.id
        Task {
            await engine.call(id, "StartAsync", [.string(mode)])
            wiiStarting.remove(id)
        }
    }

    // MARK: 게임 정보 / 패치 정보

    @ViewBuilder
    private var gameInfo: some View {
        if vm.isVisible("GameInfoVisibility") {
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
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private var patchInfo: some View {
        if vm.isVisible("PatchInfoVisibility") {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: 출력 포맷

    private func formatRow(idle: Bool) -> some View {
        HStack(spacing: 10) {
            Text("출력 포맷:").font(.subheadline.weight(.semibold))
            Picker("", selection: radio(["IsIsoFormat", "IsWbfsFormat", "IsRvzFormat"])) {
                Text("ISO").tag("IsIsoFormat")
                Text("WBFS ( USB 로더 )").tag("IsWbfsFormat")
                Text("RVZ ( Dolphin 전용 압축 )").tag("IsRvzFormat")
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .labelsHidden()
            .disabled(!idle)
            Spacer()
        }
    }

    /// RadioButton IsChecked="{Binding IsXxxFormat}" 묶음. WPF처럼 다른 단추는 false, 고른 단추는 true로 보낸다.
    private func radio(_ props: [String]) -> Binding<String> {
        Binding(get: { props.first { vm[$0]?.bool == true } ?? "" },
                set: { selected in
                    for prop in props where prop != selected { engine.bool(vm, prop).wrappedValue = false }
                    engine.bool(vm, selected).wrappedValue = true
                })
    }
}

/// StartAsync를 부른 뒤 끝날 때까지의 WiiMainViewModel 번호
@MainActor private var wiiStarting: Set<Int> = []

/// TextBox Text="{Binding Prop, UpdateSourceTrigger=PropertyChanged}".
/// 입력할 때마다 ViewModel에 보내되, 엔진이 늦게 돌려주는 이전 값(내가 보낸 값의 메아리)으로 입력 중인 글자를 덮어쓰지 않는다.
/// 드롭·찾아보기처럼 ViewModel이 다른 값으로 바뀌면 바로 따른다.
private struct WiiTextField: View {
    @Environment(EngineClient.self) private var engine
    let title: String
    let vm: RemoteObject
    let prop: String

    @State private var text = ""
    @State private var sent: [String] = []

    var body: some View {
        TextField(title, text: $text)
            .onAppear(perform: reload)
            .onChange(of: vm.id) { _, _ in reload() }
            .onChange(of: text) { _, value in
                // 아직 돌아오지 않은 마지막 값(없으면 ViewModel 값)과 같으면 보낼 것이 없다.
                guard value != (sent.last ?? vm.string(prop)) else { return }
                sent.append(value)
                let id = vm.id, prop = prop
                Task { await engine.set(id, prop, .string(value)) }
            }
            .onChange(of: vm.string(prop)) { _, value in
                if let index = sent.lastIndex(of: value) {
                    // 내가 보낸 값이 돌아왔다. 그보다 앞서 보낸 값은 더 기다리지 않는다.
                    sent.removeFirst(index + 1)
                    if sent.isEmpty, value != text { text = value }
                    return
                }
                // 드롭·찾아보기 등 ViewModel 쪽 변경
                sent.removeAll()
                if value != text { text = value }
            }
    }

    private func reload() {
        sent.removeAll()
        text = vm.string(prop)
    }
}

/// 패치 경로 입력: Text="{Binding PatchPath, UpdateSourceTrigger=LostFocus}" + TxtPatch_KeyDown(Enter면 바로 반영)
private struct WiiPatchPathField: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("패치 폴더 또는 zip/7z/xml을 드래그&드롭하세요", text: $text)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .onAppear { text = vm.string("PatchPath") }
            .onChange(of: vm.string("PatchPath")) { _, value in text = value }
    }

    private func commit() {
        guard text != vm.string("PatchPath") else { return }
        engine.string(vm, "PatchPath").wrappedValue = text
    }
}

/// 찾아보기 단추(Command + IsEnabled="{Binding IsIdle}")
private struct WiiBrowseButton: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject
    let command: String
    let icon: String
    let enabled: Bool
    var help: String?

    var body: some View {
        Button { engine.run(vm, command) } label: { UpstreamIcon(name: icon, size: 24) }
            .buttonStyle(.borderless)
            .help(help ?? "")
            .disabled(!enabled || !engine.canRun(vm, command))
    }
}

/// 하단 진행 상황(ProgressLabel, ProgressPercent, ProgressTime, 막대 = ProgressPct)
private struct WiiProgressFooter: View {
    let vm: RemoteObject

    var body: some View {
        HStack(spacing: 10) {
            Text(vm.string("ProgressLabel"))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(vm.string("ProgressPercent")).fontWeight(.semibold)
            Text(vm.string("ProgressTime"))
            ProgressView(value: min(max((vm["ProgressPct"]?.double ?? 0) / 100, 0), 1))
                .frame(width: 140)
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
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
