// upstream: RomForge/Controls/PS/PackingTab.xaml(.cs)
// ViewModel: PackingMainViewModel (PS1MainViewModel.PackingVM)
import AppKit
import SwiftUI

/// PBP 패킹: [디스크 목록 | 기본 이미지·부트 로고] / POPS 에뮬레이터 설정 / 진행 상태 / 버튼
struct PSPackingTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject
    @State private var selection = Set<Int>()

    private var isUnlocked: Bool { vm["IsUnlocked"]?.bool ?? true }

    var body: some View {
        ToolLayout(vm: vm, lists: ["FileItems", "LogEntries", "FmvFixPresets"]) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    fileList
                    PSPackingArtwork(vm: vm)
                        .frame(width: 400)
                        .disabled(!isUnlocked)
                }
                .padding(8)
                .frame(maxHeight: .infinity)

                Divider()

                VStack(spacing: 8) {
                    popsSettings
                    progressRow
                    buttonBar
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .overlay {
                if vm["IsDownloading"]?.bool == true { downloadingOverlay }
            }
        }
    }

    // MARK: 목록

    private var fileList: some View {
        Table(engine.items(vm, "FileItems"), selection: $selection) {
            TableColumn("파일명") { item in
                Text(item.string("FileName"))
                    .lineLimit(1)
                    .help(item.string("FilePath"))
            }
            TableColumn("확장자") { item in ExtensionBadge(item: item) }
                .width(min: 60, ideal: 66)
            TableColumn("게임ID") { item in Text(item.string("GameId")) }
                .width(min: 70, ideal: 90)
            TableColumn("용량") { item in
                Text(item.string("FileSize"))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 80)
        }
        .overlay {
            if vm.isVisible("HintVisibility") {
                PSHint(title: "파일 또는 폴더를 여기에 드래그&드롭하세요",
                       detail: "최대 5개의 파일까지 패킹 가능",
                       badges: ["M3U", "CUE", "CHD"])
            }
        }
        .modifier(PSFileListBehavior(engine: engine, vm: vm, selection: $selection, enabled: isUnlocked))
    }

    // MARK: POPS 설정

    private var popsSettings: some View {
        OptionCard {
            HStack(spacing: 10) {
                Text("POPS 에뮬레이터 설정").font(.caption.weight(.bold))
                if vm["HasPresetConfig"]?.bool == true {
                    Text("프리셋 설정 로드됨 (수동 설정 비활성화)").font(.caption).foregroundStyle(.green)
                }
            }

            HStack(spacing: 10) {
                Toggle("동영상 프리징 픽스 (cmd 0x00)", isOn: engine.bool(vm, "UseFmvFix"))

                // ComboBox ItemsSource=FmvFixPresets, DisplayMemberPath=Label, SelectedItem=SelectedFmvFix
                Picker("", selection: engine.selectedItem(vm, "SelectedFmvFix")) {
                    ForEach(engine.items(vm, "FmvFixPresets")) { option in
                        Text(option.string("Label")).tag(Optional(option.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(!(vm["UseFmvFix"]?.bool ?? false))

                Toggle("추가 옵션 (cmd 0x0B)", isOn: engine.bool(vm, "UseCdTimingFix"))
                    .padding(.leading, 10)

                Spacer(minLength: 0)
            }
        }
        .disabled(!(vm["CanEditPopsConfig"]?.bool ?? true))
    }

    // MARK: 진행 상태

    private var progressRow: some View {
        HStack(spacing: 10) {
            Text(vm.string("ProgressLabel"))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(vm.string("ProgressSpeed")).foregroundStyle(.secondary)
            Text(vm.string("ProgressTime")).foregroundStyle(.green)
            ProgressView(value: min(max(vm["ProgressPct"]?.double ?? 0, 0), 100), total: 100)
                .frame(width: 140)
        }
        .font(.caption)
    }

    // MARK: 버튼

    private var buttonBar: some View {
        let canAdd = vm["CanAdd"]?.bool ?? false

        return HStack(spacing: 6) {
            IconButton(title: "파일 추가", icon: "AddFile.png", enabled: canAdd) {
                PSFileActions.addFiles(engine, vm, filterType: "PackingMainViewModel")
            }
            IconButton(title: "폴더 추가", icon: "AddFolder.png", enabled: canAdd) {
                PSFileActions.addFolder(engine, vm)
            }
            IconButton(title: "선택 삭제", icon: "Delete.png", enabled: isUnlocked) {
                PSFileActions.remove(engine, vm, selection)
                selection.removeAll()
            }
            IconButton(title: "전체 삭제", icon: "Clear.png", enabled: isUnlocked) {
                PSFileActions.clear(engine, vm)
                selection.removeAll()
            }
            CommandIconButton(title: "설정", icon: "Settings.png", vm: vm, command: "SettingsCommand", enabled: isUnlocked)

            Spacer()

            CommandIconButton(title: "시작", icon: "Run.png", vm: vm, command: "RunCommand",
                            enabled: vm["CanRun"]?.bool ?? false, prominent: true)
            CommandIconButton(title: "취소", icon: "Cancel.png", vm: vm, command: "CancelCommand")
        }
    }

    // MARK: 이미지 다운로드 중(IsDownloading)

    private var downloadingOverlay: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            VStack(spacing: 12) {
                Text("⏳").font(.system(size: 36))
                Text("이미지 다운로드 중...")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: 240)
            }
        }
    }
}

/// 오른쪽 이미지 탭(기본 이미지 / 부트 로고). 480×272(PSP 화면) 배치를 폭에 맞춰 줄여 그린다(Viewbox Stretch=Uniform).
struct PSPackingArtwork: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    @State private var page = 0

    var body: some View {
        VStack(spacing: 6) {
            Picker("", selection: $page) {
                Text("기본 이미지").tag(0)
                Text("부트 로고").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if page == 0 {
                PSArtworkCanvas { scale in baseImages(scale) }
                Button("비우기") { engine.invoke(vm, "ResetBaseImages") }
            } else {
                PSArtworkCanvas { scale in bootLogo(scale) }
                Button("비우기") { engine.invoke(vm, "ResetBootLogo") }
            }
            Spacer(minLength: 0)
        }
        .padding(6)
    }

    /// 배경(PIC1) 위에 아이콘(ICON0, 왼쪽 위)과 로고(PIC0, 왼쪽 아래)
    private func baseImages(_ scale: CGFloat) -> some View {
        PSArtworkSlot(vm: vm, imageProp: "Pic1Image", setMethod: "SetPic1FromBytes", exportName: "Background.PNG")
            .overlay(alignment: .topLeading) {
                PSArtworkSlot(vm: vm, imageProp: "Icon0Image", setMethod: "SetIcon0FromBytes", exportName: "Cover.PNG")
                    .frame(width: 80 * scale, height: 80 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 10 * scale))
                    .padding(15 * scale)
            }
            .overlay(alignment: .bottomLeading) {
                PSArtworkSlot(vm: vm, imageProp: "Pic0Image", setMethod: "SetPic0FromBytes", exportName: "Logo.PNG",
                              alignment: .bottomLeading)
                    .frame(width: 270 * scale, height: 150 * scale)
                    .padding(15 * scale)
            }
            .clipShape(RoundedRectangle(cornerRadius: 15 * scale))
    }

    private func bootLogo(_ scale: CGFloat) -> some View {
        PSArtworkSlot(vm: vm, imageProp: "BootLogoImage", setMethod: "SetBootLogoFromBytes", exportName: "BootLogo.PNG")
            .overlay {
                if vm["ShowBootLogoHint"]?.bool ?? true {
                    PSHint(icon: "Drag.png", title: "이미지 파일을 드래그&드롭하세요",
                           badges: ["PNG", "JPG", "GIF", "BMP", "WEBP"])
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 15 * scale))
            .overlay(RoundedRectangle(cornerRadius: 15 * scale).strokeBorder(.separator))
    }
}

/// 480×272 비율 칸. 내용에는 원래 크기 대비 배율을 넘긴다.
struct PSArtworkCanvas<Content: View>: View {
    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View {
        GeometryReader { geometry in
            content(geometry.size.width / 480)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(480.0 / 272.0, contentMode: .fit)
    }
}

/// 이미지 한 칸. code-behind의 XxxDrop(이미지 파일 → SetXxxFromBytes)과
/// XxxMouseLeftButtonDown(ExportImage: PNG 파일로 끌어내기)을 옮긴 것.
struct PSArtworkSlot: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject
    let imageProp: String
    let setMethod: String
    let exportName: String
    var alignment: Alignment = .center

    /// code-behind _imgExts
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "bmp", "webp"]

    var body: some View {
        let slot = ZStack(alignment: alignment) {
            Color.clear
            RemoteImage(value: vm[imageProp])
        }
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first,
                  Self.imageExtensions.contains(url.pathExtension.lowercased()),
                  let data = try? Data(contentsOf: url) else { return false }
            // File.ReadAllBytes → SetXxxFromBytes(byte[]) (byte[]는 base64 문자열로 넘긴다)
            engine.invoke(vm, setMethod, [.string(data.base64EncodedString())])
            return true
        }

        if engine.image(vm[imageProp]) != nil {
            slot.onDrag { exportProvider() }
        } else {
            slot
        }
    }

    /// ExportImage: 임시 폴더에 PNG로 저장해 파일로 끌어낸다.
    /// upstream은 DoDragDrop이 끝나면 임시 파일을 지우지만, macOS는 받는 쪽이 비동기로 읽으므로 남겨 둔다.
    private func exportProvider() -> NSItemProvider {
        guard let image = engine.image(vm[imageProp]),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            return NSItemProvider()
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(exportFileName())
        guard (try? png.write(to: url)) != nil else { return NSItemProvider() }
        return NSItemProvider(contentsOf: url) ?? NSItemProvider()
    }

    /// "{게임 제목}_{이름}"(제목에서 파일 이름에 못 쓰는 문자는 "_"로 잇는다). 제목이 없으면 이름만.
    private func exportFileName() -> String {
        let invalid = CharacterSet(charactersIn: "<>:\"/\\|?*").union(.controlCharacters)
        let safeTitle = vm.string("GameTitle")
            .components(separatedBy: invalid)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        return safeTitle.isEmpty ? exportName : "\(safeTitle)_\(exportName)"
    }
}
