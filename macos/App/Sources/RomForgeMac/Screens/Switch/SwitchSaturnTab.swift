// upstream: RomForge/Controls/Switch/ConvertSaturnTab.xaml(.cs)
// ViewModel: RomForge.ViewModels.Switch.ConvertSaturnMainViewModel (SwitchMainViewModel.ConvertSaturnVM)
import AppKit
import SwiftUI

/// NSP 변환 탭: 새턴 CUE/CHD를 원본 NSP에 넣어 다시 만든다(파싱·표지·변환은 ViewModel).
struct SwitchSaturnTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    var body: some View {
        let idle = vm["IsIdle"]?.bool ?? true

        ToolLayout(vm: vm, lists: ["SoundVolumeItems", "LogEntries"]) {
            ScrollView {
                VStack(spacing: 8) {
                    VStack(spacing: 5) {
                        pathRow("CuePath", hint: "CUE/CHD 파일을 드래그&드롭하세요", icon: "AddFile.png", command: "BrowseCueCommand",
                                drop: dropTo("CuePath", extensions: ["cue", "chd"]))
                        pathRow("NspPath", hint: "원본 NSP/NSZ 파일을 드래그&드롭하세요", icon: "AddFile.png", command: "BrowseNspCommand",
                                drop: dropTo("NspPath", extensions: ["nsp", "nsz"]))
                        // upstream XAML도 작업 폴더 칸의 PreviewDrop이 Nsp_Drop이다.
                        pathRow("WorkPath", hint: "작업 폴더를 선택하세요", icon: "AddFolder.png", command: "BrowseWorkCommand",
                                drop: dropTo("NspPath", extensions: ["nsp", "nsz"]))
                    }
                    .disabled(!idle)

                    HStack(alignment: .top, spacing: 15) {
                        cover
                            .frame(width: 200, height: 205)
                            .disabled(!idle)
                        info(idle: idle)
                    }
                }
                .padding(10)
            }
        } options: {
            VStack(spacing: 8) {
                settings
                    .disabled(!idle)

                RunCancelButton(title: "작업 시작", icon: "Run.png", isRunning: vm["IsConverting"]?.bool ?? false) {
                    // BtnStart_Click
                    if vm["IsLocked"]?.bool == true {
                        engine.invoke(vm, "Cancel")
                    } else {
                        engine.invoke(vm, "ConvertAsync")
                    }
                }

                progress
            }
        }
    }

    // MARK: 경로

    private func pathRow(_ prop: String, hint: String, icon: String, command: String, drop: @escaping ([URL]) -> Bool) -> some View {
        HStack(spacing: 5) {
            TextField(hint, text: engine.string(vm, prop))
                .textFieldStyle(.roundedBorder)
            ToolIconButton(icon: icon) { engine.run(vm, command) }
        }
        .dropDestination(for: URL.self) { urls, _ in drop(urls) }
    }

    /// Cue_Drop / Nsp_Drop: 첫 파일의 확장자가 맞으면 경로 속성에 넣는다.
    private func dropTo(_ prop: String, extensions: [String]) -> ([URL]) -> Bool {
        { urls in
            guard let path = urls.first?.path, extensions.contains((path as NSString).pathExtension.lowercased()) else { return false }
            Task { await engine.set(vm.id, prop, .string(path)) }
            return true
        }
    }

    // MARK: 표지 · 정보

    private var cover: some View {
        let image = engine.image(vm["CoverImageSource"])

        return ZStack {
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.secondary.opacity(0.08))

            if vm.isVisible("CoverHintVisibility") {
                VStack(spacing: 4) {
                    UpstreamIcon(name: "Drag.png", size: 28)
                    Text("이미지 파일을")
                    Text("드래그&드롭 하세요")
                    SwitchFormatRows(formats: ["PNG", "JPG", "GIF", "BMP", "WEBP"])
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 200, height: 205)
                    .clipped()
                    .onDrag { SwitchImageDrag.provider(image, fileName: "\(vm.string("GameTitle"))_Saturn.png") }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .dropDestination(for: URL.self) { urls, _ in
            // Cover_Drop
            guard let path = urls.first?.path else { return false }
            Task { await engine.set(vm.id, "CoverImagePath", .string(path)) }
            return true
        }
    }

    private func info(idle: Bool) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
            GridRow {
                Text("게임명").fontWeight(.semibold)
                Text("배급사").fontWeight(.semibold)
            }
            GridRow {
                TextField("", text: engine.string(vm, "GameTitle")).disabled(!idle)
                TextField("", text: engine.string(vm, "Publisher")).disabled(!idle)
            }
            GridRow {
                Text("게임 ID").fontWeight(.semibold)
                Text("버전").fontWeight(.semibold)
            }
            .padding(.top, 5)
            GridRow {
                SwitchReadOnlyField(text: vm.string("GameId"))
                SwitchReadOnlyField(text: vm.string("GameVersion"))
            }
            GridRow {
                Text("NSP 타이틀 ID").fontWeight(.semibold)
            }
            .padding(.top, 10)
            GridRow {
                SwitchReadOnlyField(text: vm.string("NspTitleId"))
            }
        }
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: 설정 · 진행

    private var settings: some View {
        let loaded = engine.store.items(vm.ref("SoundVolumeItems")).compactMap(\.string)
        let volumes = loaded.isEmpty ? [vm.string("SelectedSoundVolume")] : loaded

        return HStack(spacing: 15) {
            Text("설정").fontWeight(.bold).foregroundStyle(.orange)
            Toggle("와이드 스크린", isOn: engine.bool(vm, "WideScreen"))
            HStack(spacing: 5) {
                Text("사운드 볼륨:")
                Picker("", selection: engine.string(vm, "SelectedSoundVolume")) {
                    ForEach(volumes, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 90)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var progress: some View {
        HStack(spacing: 10) {
            Text(vm.string("ProgressLabel"))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Text(vm.string("ProgressPercent")).foregroundStyle(.green).fontWeight(.semibold)
            Text(vm.string("ProgressSpeed")).foregroundStyle(.secondary)
            Text(vm.string("ProgressTime")).foregroundStyle(.green)
            ProgressView(value: min(max((vm["ProgressPct"]?.double ?? 0) / 100, 0), 1))
                .frame(width: 140)
        }
        .font(.caption.monospacedDigit())
    }
}

/// 읽기 전용 TextBox(IsReadOnly=True): 선택·복사만 된다.
private struct SwitchReadOnlyField: View {
    let text: String

    var body: some View {
        Text(text.isEmpty ? " " : text)
            .textSelection(.enabled)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.4)))
    }
}

/// 형식 배지 묶음(줄바꿈 WrapPanel 자리: 3개씩)
private struct SwitchFormatRows: View {
    let formats: [String]

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(stride(from: 0, to: formats.count, by: 3)), id: \.self) { start in
                HStack(spacing: 3) {
                    ForEach(formats[start..<min(start + 3, formats.count)], id: \.self) { SwitchBadge(text: $0) }
                }
            }
        }
    }
}
