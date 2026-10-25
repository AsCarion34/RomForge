// upstream: RomForge/Controls/PSP/PackingTab.xaml(.cs)
// ViewModel: PackingMainViewModel (PSPMainViewModel.PackingVM)
//            하위: Files(DiscListViewModel), Images(PackingImagesViewModel), Bgm(BgmViewModel, Bgm.Preview: BgmPreviewViewModel), PopsOptions(PopsOptionsViewModel)
import AppKit
import SwiftUI

/// PBP 패킹: [디스크 목록 | 기본 이미지·부트 로고·배경음] / POPS 에뮬레이터 설정 / 진행 상태 / 버튼
struct PSPPackingTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject
    @State private var selection = Set<Int>()

    /// 하위 ViewModel(describe되기 전에는 nil)
    private var files: RemoteObject? { engine.store.object(vm.ref("Files")) }
    private var images: RemoteObject? { engine.store.object(vm.ref("Images")) }
    private var popsOptions: RemoteObject? { engine.store.object(vm.ref("PopsOptions")) }

    private var isUnlocked: Bool { vm["IsUnlocked"]?.bool ?? true }

    var body: some View {
        ToolLayout(vm: vm, lists: ["LogEntries"]) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    fileList
                    // TabControl IsEnabled="{Binding IsUnlocked}"
                    PSPPackingAssets(vm: vm)
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
                if images?["IsDownloading"]?.bool == true { downloadingOverlay }
            }
        }
        .pspDescribeChildren(engine, vm, ["Files", "Images", "Bgm", "PopsOptions"])
        .observeLists(engine, files, ["FileItems"])
        .observeLists(engine, popsOptions, ["FmvFixPresets"])
    }

    // MARK: 목록(Files.FileItems)

    private var fileList: some View {
        Table(engine.items(files, "FileItems"), selection: $selection) {
            TableColumn("파일명") { item in
                Text(item.string("FileName"))
                    .lineLimit(1)
                    .help(item.string("FilePath"))
            }
            .width(min: 140, ideal: 240)

            // 머리글은 Extension.png 아이콘뿐이다.
            TableColumn("") { item in
                ExtensionBadge(item: item).frame(maxWidth: .infinity, alignment: .center)
            }
            .width(min: 44, ideal: 50)

            TableColumn("ID") { item in
                Text(item.string("GameId"))
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .width(min: 70, ideal: 80)

            TableColumn("용량") { item in
                Text(item.string("FileSize"))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 90)
        }
        .overlay {
            if files?.isVisible("HintVisibility") == true {
                PSPHint(title: "파일 또는 폴더를 여기에 드래그&드롭하세요",
                        detail: "최대 5개의 파일까지 패킹 가능",
                        badges: ["M3U", "CUE", "CHD"])
            }
        }
        // LvFiles_Drop → Files.AddPaths, Delete 키·선택 삭제 → Files.Remove, 전체 삭제 → Files.Clear
        .modifier(PSPFileListBehavior(engine: engine, owner: files, selection: $selection, enabled: isUnlocked,
                                      removeMethod: "Remove", clearMethod: "Clear"))
    }

    // MARK: POPS 에뮬레이터 설정(PopsOptions)

    private var popsSettings: some View {
        OptionCard {
            HStack(spacing: 10) {
                Text("POPS 에뮬레이터 설정").font(.caption.weight(.bold))
                if files?["HasPresetConfig"]?.bool == true {
                    Text("프리셋 설정 로드됨 (수동 설정 비활성화)").font(.caption).foregroundStyle(.green)
                }
            }

            HStack(spacing: 10) {
                Toggle("동영상 프리징 픽스 (cmd 0x00)", isOn: engine.bool(popsOptions, "UseFmvFix"))

                // ComboBox ItemsSource=PopsOptions.FmvFixPresets, DisplayMemberPath=Label, SelectedItem=PopsOptions.SelectedFmvFix
                Picker("", selection: engine.selectedItem(popsOptions, "SelectedFmvFix")) {
                    ForEach(engine.items(popsOptions, "FmvFixPresets")) { option in
                        Text(option.string("Label")).tag(Optional(option.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(!(popsOptions?["UseFmvFix"]?.bool ?? false))

                Toggle("추가 옵션 (cmd 0x0B)", isOn: engine.bool(popsOptions, "UseCdTimingFix"))
                    .padding(.leading, 10)

                Spacer(minLength: 0)
            }
        }
        // Border IsEnabled="{Binding CanEditPopsConfig}"
        .disabled(!(vm["CanEditPopsConfig"]?.bool ?? true))
    }

    // MARK: 진행 상태(ProgressLabel · ProgressSpeed · ProgressTime · ProgressPct 막대)

    private var progressRow: some View {
        HStack(spacing: 10) {
            Text(vm.string("ProgressLabel"))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(vm.string("ProgressSpeed")).foregroundStyle(.secondary)
            Text(vm.string("ProgressTime")).foregroundStyle(.green)
            ProgressView(value: min(max((vm["ProgressPct"]?.double ?? 0) / 100, 0), 1))
                .frame(width: 140)
        }
        .font(.caption.monospacedDigit())
    }

    // MARK: 버튼

    private var buttonBar: some View {
        let canAdd = vm["CanAdd"]?.bool ?? false

        return HStack(spacing: 6) {
            // BtnAddFiles_Click: Filter = DiscListViewModel.GetFileDialogFilter() → Files.AddPaths
            IconButton(title: "파일 추가", icon: "AddFile.png", enabled: canAdd) {
                PSPFileActions.addFiles(engine, files, filterType: "RomForge.ViewModels.PSP.DiscListViewModel")
            }
            IconButton(title: "폴더 추가", icon: "AddFolder.png", enabled: canAdd) {
                PSPFileActions.addFolder(engine, files)
            }
            IconButton(title: "선택 삭제", icon: "Delete.png", enabled: isUnlocked) {
                PSPFileActions.remove(engine, files, selection, method: "Remove")
                selection.removeAll()
            }
            IconButton(title: "전체 삭제", icon: "Clear.png", enabled: isUnlocked) {
                PSPFileActions.clear(engine, files, method: "Clear")
                selection.removeAll()
            }
            CommandIconButton(title: "설정", icon: "Settings.png", vm: vm, command: "SettingsCommand", enabled: isUnlocked)

            Spacer()

            CommandIconButton(title: "시작", icon: "Run.png", vm: vm, command: "RunCommand",
                              enabled: vm["CanRun"]?.bool ?? false, prominent: true)
            // XAML의 IsEnabled="{Binding IsConverting}"는 PackingMainViewModel에 없는 속성이라 CanExecute(IsLocked)만 따른다.
            CommandIconButton(title: "취소", icon: "Cancel.png", vm: vm, command: "CancelCommand")
        }
    }

    // MARK: 이미지 다운로드 중(Images.IsDownloading)

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

/// 오른쪽 탭(기본 이미지 / 부트 로고 / 배경음). 480×272(PSP 화면) 칸은 폭에 맞춰 줄여 그린다(Viewbox Stretch=Uniform).
struct PSPPackingAssets: View {
    @Environment(EngineClient.self) private var engine
    /// PackingMainViewModel(GameTitle, Images, Bgm)
    let vm: RemoteObject

    @State private var page = 0

    private var images: RemoteObject? { engine.store.object(vm.ref("Images")) }
    /// TabControl IsEnabled="{Binding IsUnlocked}"(끌어다 놓기도 막는다)
    private var enabled: Bool { vm["IsUnlocked"]?.bool ?? true }

    var body: some View {
        VStack(spacing: 6) {
            Picker("", selection: $page) {
                Text("기본 이미지").tag(0)
                Text("부트 로고").tag(1)
                Text("배경음").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch page {
            case 0:
                PSPArtworkCanvas { scale in baseImages(scale) }
                // BaseImage_Reset_Click
                Button("비우기") { engine.invoke(images, "ResetBaseImages") }
            case 1:
                PSPArtworkCanvas { scale in bootLogo(scale) }
                // BootLogo_Reset_Click
                Button("비우기") { engine.invoke(images, "ResetBootLogo") }
            default:
                PSPBgmPanel(bgm: engine.store.object(vm.ref("Bgm")), enabled: enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
    }

    private func slot(_ imageProp: String, _ setMethod: String, _ exportName: String,
                      alignment: Alignment = .center) -> PSPArtworkSlot {
        PSPArtworkSlot(images: images, gameTitle: vm.string("GameTitle"), imageProp: imageProp, setMethod: setMethod,
                       exportName: exportName, enabled: enabled, alignment: alignment)
    }

    /// 배경(PIC1) 위에 아이콘(ICON0, 왼쪽 위)과 로고(PIC0, 왼쪽 아래)
    private func baseImages(_ scale: CGFloat) -> some View {
        slot("Pic1Image", "SetPic1FromBytes", "Background.PNG")
            .overlay(alignment: .topLeading) {
                slot("Icon0Image", "SetIcon0FromBytes", "Cover.PNG")
                    .frame(width: 80 * scale, height: 80 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 10 * scale))
                    .padding(15 * scale)
            }
            .overlay(alignment: .bottomLeading) {
                slot("Pic0Image", "SetPic0FromBytes", "Logo.PNG", alignment: .bottomLeading)
                    .frame(width: 270 * scale, height: 150 * scale)
                    .padding(15 * scale)
            }
            .clipShape(RoundedRectangle(cornerRadius: 15 * scale))
    }

    private func bootLogo(_ scale: CGFloat) -> some View {
        slot("BootLogoImage", "SetBootLogoFromBytes", "BootLogo.PNG")
            .overlay {
                if images?["ShowBootLogoHint"]?.bool ?? true {
                    PSPHint(icon: "Drag.png", title: "이미지 파일을 드래그&드롭하세요",
                            badges: ["PNG", "JPG", "GIF", "BMP", "WEBP"])
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 15 * scale))
            .overlay(RoundedRectangle(cornerRadius: 15 * scale).strokeBorder(.separator))
    }
}

/// 480×272 비율 칸. 내용에는 원래 크기 대비 배율을 넘긴다.
struct PSPArtworkCanvas<Content: View>: View {
    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View {
        GeometryReader { geometry in
            content(geometry.size.width / 480)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(480.0 / 272.0, contentMode: .fit)
    }
}

/// 이미지 한 칸. code-behind의 XxxDrop(이미지 파일 → Images.SetXxxFromBytes)과
/// XxxMouseLeftButtonDown(ExportImage: PNG 파일로 끌어내기)을 옮긴 것.
struct PSPArtworkSlot: View {
    @Environment(EngineClient.self) private var engine
    /// PackingImagesViewModel
    let images: RemoteObject?
    /// PackingMainViewModel.GameTitle(끌어낸 파일 이름 앞에 붙는다)
    let gameTitle: String
    let imageProp: String
    let setMethod: String
    let exportName: String
    var enabled = true
    var alignment: Alignment = .center

    /// code-behind _imgExts
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "bmp", "webp"]

    var body: some View {
        let slot = ZStack(alignment: alignment) {
            Color.clear
            RemoteImage(value: images?[imageProp])
        }
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            guard enabled, let images, let url = urls.first,
                  Self.imageExtensions.contains(url.pathExtension.lowercased()),
                  let data = try? Data(contentsOf: url) else { return false }
            // File.ReadAllBytes → SetXxxFromBytes(byte[]) (byte[]는 base64 문자열로 넘긴다)
            engine.invoke(images, setMethod, [.string(data.base64EncodedString())])
            return true
        }

        if engine.image(images?[imageProp]) != nil {
            slot.onDrag { exportProvider() }
        } else {
            slot
        }
    }

    /// ExportImage: 임시 폴더에 PNG로 저장해 파일로 끌어낸다.
    /// upstream은 DoDragDrop이 끝나면 임시 파일을 지우지만, macOS는 받는 쪽이 비동기로 읽으므로 남겨 둔다.
    private func exportProvider() -> NSItemProvider {
        guard let image = engine.image(images?[imageProp]),
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
        let safeTitle = gameTitle
            .components(separatedBy: invalid)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        return safeTitle.isEmpty ? exportName : "\(safeTitle)_\(exportName)"
    }
}

/// 배경음 탭: 오디오 파일 드롭·클릭(Bgm_Drop / Bgm_MouseLeftButtonDown → Bgm.SetPathAsync),
/// 미리듣기(Bgm.Preview), 품질(Bgm.IsHighQualityMode), 비우기(Bgm_Reset_Click → Bgm.Reset)
struct PSPBgmPanel: View {
    @Environment(EngineClient.self) private var engine
    /// BgmViewModel
    let bgm: RemoteObject?
    var enabled = true

    /// code-behind _audioExts
    private static let audioExtensions: Set<String> = ["mp3", "wav", "at3"]
    /// Bgm_MouseLeftButtonDown의 OpenFileDialog Filter
    private static let audioFilter =
        "Audio Files (*.mp3;*.wav;*.at3)|*.mp3;*.wav;*.at3|MP3 Files (*.mp3)|*.mp3|WAV Files (*.wav)|*.wav|AT3 Files (*.at3)|*.at3"

    /// BgmPreviewViewModel(describe되기 전에는 nil)
    private var preview: RemoteObject? { engine.store.object(bgm?.ref("Preview")) }
    private var isConverting: Bool { bgm?["IsConverting"]?.bool ?? false }

    var body: some View {
        VStack(spacing: 8) {
            PSPArtworkCanvas { scale in
                ZStack {
                    // Border MouseLeftButtonDown: 빈 곳(안내 문구 포함)을 누르면 오디오 파일을 고른다.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { browseAudio() }

                    if bgm?["HasBgm"]?.bool == true {
                        loadedView
                    } else {
                        PSPHint(icon: "Info.png", title: "오디오 파일을 드래그&드롭하거나 클릭하세요",
                                detail: "MP3, WAV 파일 추가 시 자동으로 AT3 포맷으로 변환됩니다.",
                                badges: ["MP3", "WAV", "AT3"])
                    }

                    if isConverting { convertingOverlay }
                }
                // Bgm_Drop: 첫 파일만 ProcessAudioFile
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    return processAudioFile(url)
                }
                .clipShape(RoundedRectangle(cornerRadius: 15 * scale))
                .overlay(RoundedRectangle(cornerRadius: 15 * scale).strokeBorder(.separator))
            }

            HStack(spacing: 8) {
                HStack(spacing: 10) {
                    Text("품질").font(.caption.weight(.bold))
                    // RadioButton IsChecked="{Binding Bgm.IsHighQualityMode}" / "{… Converter=InverseBool}"
                    Picker("", selection: engine.bool(bgm, "IsHighQualityMode")) {
                        Text("30초 (132k)").tag(true)
                        Text("60초 (66k)").tag(false)
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                    .labelsHidden()
                    .disabled(isConverting)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

                // Bgm_Reset_Click: 변환 중이면 무시한다.
                Button("비우기") {
                    guard !isConverting else { return }
                    engine.invoke(bgm, "Reset")
                }
            }
        }
        .pspDescribeChildren(engine, bgm, ["Preview"])
    }

    /// 배경음이 있을 때(Bgm.HasBgm): 파일 이름, 미리듣기 막대, 재생/일시정지, 안내 문구
    private var loadedView: some View {
        VStack(spacing: 8) {
            Text(bgm?.string("FileName") ?? "")
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .allowsHitTesting(false)

            if preview?["HasPreview"]?.bool == true {
                previewBar
            }

            // TogglePlayCommand: IsPlaying이면 일시정지 모양
            Button {
                engine.run(preview, "TogglePlayCommand")
            } label: {
                Image(systemName: preview?["IsPlaying"]?.bool == true ? "pause.fill" : "play.fill")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .help("재생/일시정지")

            Text("클릭하거나 파일을 드롭하여 변경할 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 20)
    }

    /// Slider(0…DurationSeconds, PositionSeconds TwoWay) + PositionText / DurationText.
    /// 끌기 시작·끝(Thumb.DragStarted / DragCompleted)에 BeginSeek() / EndSeek()를 부른다.
    private var previewBar: some View {
        VStack(spacing: 4) {
            Slider(value: engine.double(preview, "PositionSeconds"),
                   in: 0...max(preview?["DurationSeconds"]?.double ?? 0, 0.001),
                   onEditingChanged: { editing in
                       engine.invoke(preview, editing ? "BeginSeek" : "EndSeek")
                   })
            HStack {
                Text(preview?.string("PositionText") ?? "")
                Spacer()
                Text(preview?.string("DurationText") ?? "")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 300)
        // BgmPlayer_MouseLeftButtonDown(e.Handled = true): 재생 막대 둘레를 눌러도 파일 대화상자를 열지 않는다.
        .background(Color.clear.contentShape(Rectangle()).onTapGesture {})
    }

    /// Bgm.IsConverting: "AT3로 변환 중..." + Bgm.ProgressPct 막대 + Bgm.ProgressText
    private var convertingOverlay: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            VStack(spacing: 8) {
                Text("AT3로 변환 중...").font(.headline)
                ProgressView(value: min(max((bgm?["ProgressPct"]?.double ?? 0) / 100, 0), 1))
                    .frame(width: 240)
                Text(bgm?.string("ProgressText") ?? "")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Bgm_MouseLeftButtonDown: 변환 중이 아니면 오디오 파일 하나를 고른다.
    private func browseAudio() {
        guard enabled, !isConverting else { return }
        if let path = PSPFileActions.openFiles(filter: Self.audioFilter, multiselect: false).first {
            processAudioFile(URL(fileURLWithPath: path))
        }
    }

    /// ProcessAudioFile: 확장자가 mp3·wav·at3면 Bgm.SetPathAsync(경로)
    @discardableResult
    private func processAudioFile(_ url: URL) -> Bool {
        guard enabled, let bgm, Self.audioExtensions.contains(url.pathExtension.lowercased()) else { return false }
        engine.invoke(bgm, "SetPathAsync", [.string(url.path)])
        return true
    }
}
