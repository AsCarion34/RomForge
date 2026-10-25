// upstream: RomForge/Controls/Util/CertsTab.xaml(.cs)
// ViewModel: CertsMainViewModel (UtilMainViewModel.CertsVM)
import SwiftUI

/// certs.bin 추출: CIA 드롭 영역 / 롬 정보 / 진행 상태 / 버튼
struct UtilCertsTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    /// IsEnabled="{Binding IsLocked, Converter=InverseBool}"
    private var isUnlocked: Bool { !(vm["IsLocked"]?.bool ?? false) }

    var body: some View {
        ToolLayout(vm: vm, lists: ["LogEntries"]) {
            VStack(spacing: 8) {
                dropZone
                if vm.isVisible("RomInfoVisibility"), let romInfo = vm.ref("RomInfo") {
                    ChildVM(id: romInfo) { info in UtilCertsRomInfo(info: info) }
                        .frame(height: 68)
                }
                Spacer(minLength: 0)
                progressRow
            }
            .padding(8)
        } options: {
            HStack(spacing: 6) {
                CommandIconButton(title: "초기화", icon: "Clear.png", vm: vm, command: "ClearFileCommand", enabled: isUnlocked)
                IconButton(title: "파일 선택", icon: "AddFile.png", enabled: isUnlocked) { selectFile() }

                Spacer()

                CommandIconButton(title: "시작", icon: "Run.png", vm: vm, command: "RunCommand", enabled: isUnlocked, prominent: true)
                CommandIconButton(title: "취소", icon: "Cancel.png", vm: vm, command: "CancelCommand", enabled: !isUnlocked)
            }
        }
    }

    // MARK: 드롭 영역(CiaDrop_Drop, CiaDrop_Click)

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))

            if vm.isVisible("HintVisibility") {
                VStack(spacing: 4) {
                    UpstreamIcon(name: "Info.png", size: 24)
                    HStack(spacing: 6) {
                        UtilBadge(text: "CIA")
                        Text("파일을 여기에 드래그&드롭하세요").font(.headline)
                    }
                    Text("실행파일 위치에 certs.bin을 추출합니다").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Text("certs.bin 파일은 cia파일 생성시에 사용됩니다").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
            }

            if vm.isVisible("FileInfoVisibility"), let file = vm.ref("SelectedFile") {
                ChildVM(id: file) { file in
                    HStack(spacing: 6) {
                        UpstreamIcon(name: "AddFile.png", size: 28)
                        Text(file.string("FileName"))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .help(file.string("FilePath"))
                    .overlay(alignment: .topTrailing) {
                        Text("CIA").font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
        .frame(height: 150)
        .contentShape(Rectangle())
        .onTapGesture { if isUnlocked { selectFile() } }
        .dropDestination(for: URL.self) { urls, _ in
            // 드롭한 파일 중 첫 .cia → SetFile
            guard isUnlocked, let cia = urls.first(where: { $0.pathExtension.lowercased() == "cia" }) else { return false }
            engine.invoke(vm, "SetFile", [.string(cia.path)])
            return true
        }
        .disabled(!isUnlocked)
    }

    // MARK: 진행 상태

    private var progressRow: some View {
        HStack(spacing: 10) {
            Text(vm.string("ProgressStatus"))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(vm.string("ProgressText"))
                .fontWeight(.bold)
                .foregroundStyle(.green)
            // ScaleX="{Binding SelectedFile.Progress, Converter=ProgressToStarConverter, FallbackValue=0}"
            Group {
                if let file = vm.ref("SelectedFile") {
                    ChildVM(id: file) { file in
                        ProgressView(value: min(max(file["Progress"]?.double ?? 0, 0), 100), total: 100)
                    }
                } else {
                    ProgressView(value: 0, total: 100)
                }
            }
            .frame(width: 140)
        }
        .font(.caption)
    }

    /// BtnAddFile_Click: OpenFileDialog{Filter=CertsMainViewModel.FileDialogFilter(정적 속성), Title="CIA 파일 선택"} → SetFile
    private func selectFile() {
        Task {
            let filter = await engine.callStatic("CertsMainViewModel", "get_FileDialogFilter")?.string
            if let path = UtilFileActions.openFiles(filter: filter, title: "CIA 파일 선택", multiselect: false).first {
                engine.invoke(vm, "SetFile", [.string(path)])
            }
        }
    }
}

/// 롬 정보 상자(RomInfo: 아이콘, 설명, 배급사, 제품 코드 · 타이틀 ID, 지역 국기, 암호화 자물쇠)
struct UtilCertsRomInfo: View {
    @Environment(EngineClient.self) private var engine
    let info: RemoteObject

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(value: info["Icon"], size: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(info.string("ShortDescription")).fontWeight(.semibold).lineLimit(1)
                Text(info.string("Publisher")).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    Text(info.string("ProductCode")).foregroundStyle(.secondary)
                    Text(" · ").foregroundStyle(.tertiary)
                    Text(info.string("TitleId")).foregroundStyle(.tertiary)
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                RemoteImage(value: engine.converted("RegionToImageConverter", info, "ProductCode"), size: 24)
                    .help(info.string("Region"))
                RemoteImage(value: engine.converted("LockIconConverter", info, "Crypto"), size: 24)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
