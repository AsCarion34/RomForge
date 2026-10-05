// upstream: RomForge/Controls/3DS/RepackTab.xaml(.cs)
// ViewModel: RepackMainViewModel (Main3DsVM.RepackVM), TitleViewModel(RomInfo)
import AppKit
import SwiftUI

/// 3DS 리팩: 롬파일 / 한글패치 / 작업 폴더, 언팩·리팩 버튼, 롬 정보(게임명·배급사 수정), 출력 포맷, 진행 상황.
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
                romRow(vm, idle: idle)
                HStack(alignment: .top, spacing: 10) {
                    patchColumn(vm, idle: idle)
                    outputColumn(vm, idle: idle)
                }
                modeButtons(vm)
                romInfo(vm, idle: idle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                formatRow(vm, idle: idle)
                ThreeDSRepackProgress(vm: vm)
            }
            .padding(10)
        }
    }

    // MARK: 입력

    private func romRow(_ vm: RemoteObject, idle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("롬파일").font(.subheadline.weight(.semibold))
            HStack(spacing: 5) {
                HStack {
                    ThreeDSTextField(title: "롬파일(.3ds, .cci, .zcci, .cia)을 드래그&드롭하세요", vm: vm, prop: "InputPath")
                        .textFieldStyle(.roundedBorder)
                        .disabled(!idle)
                }
                .dropDestination(for: URL.self) { urls, _ in dropRom(vm, urls) }

                Button { engine.run(vm, "BrowseInputCommand") } label: { UpstreamIcon(name: "AddFile.png", size: 24) }
                    .buttonStyle(.borderless)
                    .disabled(!idle || !engine.canRun(vm, "BrowseInputCommand"))
            }
        }
    }

    private func patchColumn(_ vm: RemoteObject, idle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("한글패치 / xdelta (폴더 or zip,7z)").font(.subheadline.weight(.semibold))
            HStack {
                ThreeDSTextField(title: "한글패치 폴더 또는 zip/7z파일을 드래그&드롭하세요", vm: vm, prop: "PatchPath")
                    .textFieldStyle(.roundedBorder)
                    .disabled(!idle)
            }
            .dropDestination(for: URL.self) { urls, _ in dropPatch(vm, urls) }
        }
        .frame(maxWidth: .infinity)
    }

    private func outputColumn(_ vm: RemoteObject, idle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("작업 폴더").font(.subheadline.weight(.semibold))
            HStack(spacing: 5) {
                ThreeDSTextField(title: "작업 폴더를 선택하세요", vm: vm, prop: "OutputPath")
                    .textFieldStyle(.roundedBorder)
                    .disabled(!idle)
                Button { engine.run(vm, "BrowseOutputCommand") } label: { UpstreamIcon(name: "AddFolder.png", size: 24) }
                    .buttonStyle(.borderless)
                    .disabled(!idle || !engine.canRun(vm, "BrowseOutputCommand"))
            }
        }
        .frame(maxWidth: .infinity)
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

                RunCancelButton(title: "언팩 + 리팩 (스트리밍 기반)", icon: "Run.png", isRunning: vm["IsFullRunning"]?.bool ?? false) {
                    click(vm, "FullProcess")
                }
                .frame(width: unit * 2)
                .disabled(!(vm["StartEnabled"]?.bool ?? true))
            }
        }
        .frame(height: 36)
    }

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

    // MARK: 롬 정보

    @ViewBuilder
    private func romInfo(_ vm: RemoteObject, idle: Bool) -> some View {
        if vm.isVisible("RomInfoVisibility") {
            ThreeDSDescribed(id: vm.ref("RomInfo")) { info in
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
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
}

/// StartAsync를 부른 뒤 끝날 때까지의 RepackMainViewModel 번호
@MainActor private var threeDSRepackStarting: Set<Int> = []

/// 하단 진행 상황(ProgressLabel, ProgressPercent, ProgressSpeed, ProgressTime, 막대 = ProgressPct)
private struct ThreeDSRepackProgress: View {
    let vm: RemoteObject

    var body: some View {
        HStack(spacing: 10) {
            Text(vm.string("ProgressLabel"))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(vm.string("ProgressPercent")).fontWeight(.semibold)
            Text(vm.string("ProgressSpeed")).foregroundStyle(.secondary)
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
