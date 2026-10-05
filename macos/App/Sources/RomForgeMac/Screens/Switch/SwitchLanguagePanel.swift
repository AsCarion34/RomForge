// upstream: NSW.WPF/UI/LanguageTabControl.xaml(.cs)
// ViewModel: 없음(컨트롤 상태). 메타데이터는 엔진의 NSW.HacPack.Models.GameMetadata, 읽기는 NSW.WPF.Services.MetadataService
import AppKit
import SwiftUI

/// LanguageTabControl의 상태와 code-behind 동작.
/// 엔진 빌드는 .xaml.cs를 빼므로 컨트롤 클래스를 부를 수 없어, 같은 순서로 upstream 서비스(MetadataService 등)를 호출한다.
@MainActor
@Observable
final class SwitchLanguageState {
    /// NSW.WPF.Models.LanguageItem(목록 표시용 복사본). id는 GameMetadata.Languages의 LanguageInfo 객체 번호
    struct Item: Identifiable, Equatable {
        let id: Int
        let language: String
        var titleName: String
        var publisher: String
        var isSelected: Bool
        var logo: JSONValue?
    }

    private(set) var items: [Item] = []
    private(set) var selectedId: Int?
    private(set) var gameName = ""
    private(set) var publisher = ""
    private(set) var overrideTitleId = ""
    private(set) var indices: [Int] = []
    var selectedIndex: Int?
    private(set) var image: JSONValue?
    /// CurrentMetadata(GameMetadata 객체 번호)
    private(set) var metadataId: Int?
    /// ForcedLanguage(ApplicationControlProperty.Language 이름)
    private(set) var forcedLanguage = "None"
    @ObservationIgnored private var metadataIndices: [Int] = []

    static let imageExtensions = ["jpg", "jpeg", "png", "bmp", "gif", "webp"]

    private var selectedItem: Item? { items.first { $0.id == selectedId } }

    // MARK: UpdateLanguageTabAsync

    func update(_ engine: EngineClient, files: [RemoteObject], unpackedDir: String?) async {
        resetUI()

        if let metadata = await loadGameMetadata(engine, files: files, unpackedDir: unpackedDir) {
            metadataId = metadata
            await bind(engine, metadata)
        }

        let source = files.first { $0.string("FileType").contains("B") } ?? files.first { !$0.string("TitleID").isEmpty }
        overrideTitleId = source?.string("TitleID") ?? ""
    }

    /// SyncMetadataFromUI: 체크 상태를 CurrentMetadata.Languages[].Flag에 쓴다.
    func syncMetadataFromUI(_ engine: EngineClient) async {
        guard metadataId != nil else { return }
        for item in items {
            await engine.set(item.id, "Flag", .bool(item.isSelected))
        }
    }

    /// TargetIdOffset(멀티롬 인덱스 콤보 선택)
    var targetIdOffset: JSONValue { selectedIndex.map { .int($0) } ?? .null }

    /// OverrideTitleId(16진수 → ulong?)를 BuildContext 인자로. 비었거나 16진수가 아니면 null.
    /// 엔진과 주고받는 JSON 숫자는 Double이라 2^53을 넘는 Title ID가 깨지므로 10진 문자열로 보낸다(엔진이 ulong으로 읽는다).
    var overrideTitleIdArgument: JSONValue {
        let text = overrideTitleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let value = UInt64(text, radix: 16) else { return .null }
        return .string(String(value))
    }

    private func resetUI() {
        items = []
        selectedId = nil
        gameName = ""
        publisher = ""
        overrideTitleId = ""
        image = nil
    }

    /// LoadGameMetadata
    private func loadGameMetadata(_ engine: EngineClient, files: [RemoteObject], unpackedDir: String?) async -> Int? {
        guard let keySet = await SwitchBridge.keySet(engine) else { return nil }

        let validPaths = files.filter { $0["IsKeyMissing"]?.bool != true }.map { $0.string("FilePath") }

        // upstream은 LoadGameMetadata 전체를 Task.Run으로 돌린다.
        if !validPaths.isEmpty {
            return await engine.callStatic("NSW.WPF.Services.MetadataService", "GetGameMetadata",
                                           [EngineClient.ref(keySet), .strings(validPaths)], options: .background)?.refId
        }

        if let unpackedDir {
            return await engine.callStatic("NSW.WPF.Services.MetadataService", "GetGameMetadataFromUnpacked",
                                           [.string(unpackedDir)], options: .background)?.refId
        }

        return nil
    }

    /// BindMetadataToUI
    private func bind(_ engine: EngineClient, _ metadata: Int) async {
        guard let meta = await engine.describe(metadata) else { return }

        let languages = meta.ref("Languages")
        await engine.observeList(languages)
        metadataIndices = await SwitchBridge.values(engine, of: meta["Indices"]).compactMap(\.int)

        items = engine.store.items(languages).compactMap { engine.store.object($0.refId) }.map { info in
            Item(id: info.id,
                 language: info.string("Language"),
                 titleName: info.string("TitleName"),
                 publisher: info.string("Publisher"),
                 isSelected: info["Flag"]?.bool ?? false,
                 logo: info["LogoData"])
        }

        if let first = items.first {
            await select(engine, id: first.id)
        }
    }

    // MARK: 화면 동작

    /// LbLanguages_SelectionChanged
    func select(_ engine: EngineClient, id: Int?) async {
        selectedId = id
        guard let item = selectedItem else { return }

        gameName = item.titleName
        publisher = item.publisher

        // cbxMultiRom.ItemsSource = selectedItem.Indices
        indices = metadataIndices
        if let index = selectedIndex, !indices.contains(index) { selectedIndex = nil }

        if let logo = item.logo, (logo["count"]?.int ?? 0) > 0 {
            image = await engine.callStatic("NSW.WPF.Services.Extensions", "ToBitmapImage", [logo])
        } else {
            image = nil
        }
    }

    func setSelected(_ id: Int, _ isOn: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isSelected = isOn
    }

    /// TxtGameName_TextChanged
    func setGameName(_ engine: EngineClient, _ text: String) {
        gameName = text
        guard metadataId != nil, let index = items.firstIndex(where: { $0.id == selectedId }) else { return }
        items[index].titleName = text
        let id = items[index].id
        Task { await engine.set(id, "TitleName", .string(text)) }
    }

    /// TxtPublisher_TextChanged
    func setPublisher(_ engine: EngineClient, _ text: String) {
        publisher = text
        guard metadataId != nil, let index = items.firstIndex(where: { $0.id == selectedId }) else { return }
        items[index].publisher = text
        let id = items[index].id
        Task { await engine.set(id, "Publisher", .string(text)) }
    }

    /// txtOverrideTitleId: MaxLength 16, CharacterCasing Upper, 16진수만 입력(PreviewTextInput·Pasting)
    func setOverrideTitleId(_ text: String) {
        overrideTitleId = String(text.uppercased().filter(\.isHexDigit).prefix(16))
    }

    /// BtnForceLanguage_Click
    func forceLanguage(_ engine: EngineClient) async {
        guard let item = selectedItem else { return }
        forcedLanguage = item.language
        await SwitchBridge.showInfo(engine, "강제 언어가 \(item.language)로 설정되었습니다.")
    }

    /// BtnForceLanguageCancel_Click
    func cancelForcedLanguage(_ engine: EngineClient) async {
        forcedLanguage = "None"
        await SwitchBridge.showInfo(engine, "강제 언어 설정이 취소되었습니다.")
    }

    /// ImgGame_Drop
    func dropImage(_ engine: EngineClient, _ path: String) async {
        guard Self.imageExtensions.contains((path as NSString).pathExtension.lowercased()) else { return }

        do {
            let bytes = try await SwitchBridge.callStatic(engine, "NSW.WPF.Services.Extensions", "ToImageBytes", [.string(path)])
            image = try await SwitchBridge.callStatic(engine, "NSW.WPF.Services.Extensions", "ToBitmapImage", [bytes])

            if metadataId != nil, let index = items.firstIndex(where: { $0.id == selectedId }) {
                items[index].logo = bytes
                await engine.set(items[index].id, "LogoData", bytes)
            }
        } catch {
            await SwitchBridge.showError(engine, "이미지 로드 실패: \(SwitchBridge.errorMessage(error))")
        }
    }

    /// ImgGame_MouseLeftButtonDown의 파일 이름
    var dragFileName: String {
        "\(selectedItem?.titleName ?? "")_\(selectedItem?.language ?? "").png"
    }
}

/// LanguageTabControl 화면: [지원 언어 목록] [이미지] [게임명 · ID · 배급사 · 멀티롬 인덱스 · 강제 언어]
struct SwitchLanguagePanel: View {
    @Environment(EngineClient.self) private var engine
    let state: SwitchLanguageState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            languageList
                .frame(width: 200)
            imageBox
                .frame(width: 265)
            details
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
    }

    private var languageList: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("지원 언어").font(.headline)
            List(selection: Binding(get: { state.selectedId },
                                    set: { id in Task { await state.select(engine, id: id) } })) {
                ForEach(state.items) { item in
                    SwitchLanguageRow(state: state, item: item)
                        .tag(item.id)
                }
            }
            .listStyle(.bordered)
        }
    }

    private var imageBox: some View {
        let image = engine.image(state.image)

        return ZStack {
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.secondary.opacity(0.08))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .onDrag { SwitchImageDrag.provider(image, fileName: state.dragFileName) }
            } else {
                SwitchDropHint(title: "이미지 파일을 드래그&드롭하세요",
                               formats: ["PNG", "JPG", "GIF", "BMP", "WEBP"])
                    .font(.caption)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .dropDestination(for: URL.self) { urls, _ in
            guard let path = urls.first?.path,
                  SwitchLanguageState.imageExtensions.contains((path as NSString).pathExtension.lowercased()) else { return false }
            Task { await state.dropImage(engine, path) }
            return true
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("게임명").font(.headline)
            TextField("", text: Binding(get: { state.gameName }, set: { state.setGameName(engine, $0) }))

            Text("ID").font(.headline).padding(.top, 5)
            TextField("", text: Binding(get: { state.overrideTitleId }, set: { state.setOverrideTitleId($0) }))
                .font(.body.monospaced())
                .help("16자리 16진수 (예: 0100000000010000). 비워두면 원본 Title ID 유지.")

            Text("배급사").font(.headline).padding(.top, 5)
            TextField("", text: Binding(get: { state.publisher }, set: { state.setPublisher(engine, $0) }))

            Text("멀티롬 인덱스").font(.headline).padding(.top, 5)
            Picker("", selection: Binding(get: { state.selectedIndex }, set: { state.selectedIndex = $0 })) {
                Text("").tag(Int?.none)
                ForEach(state.indices, id: \.self) { index in
                    Text("\(index)").tag(Int?.some(index))
                }
            }
            .labelsHidden()

            Spacer(minLength: 12)

            HStack {
                Spacer()
                Button {
                    Task { await state.forceLanguage(engine) }
                } label: {
                    IconLabel(title: "강제 언어 설정", icon: "Language.png", size: 22)
                }
                .help("리팩 진행 시 선택한 언어만 플래그를 켜고 나머지는 전부 끕니다.")

                Button {
                    Task { await state.cancelForcedLanguage(engine) }
                } label: {
                    IconLabel(title: "강제 언어 취소", icon: "CancelLanguage.png", size: 22)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
    }
}

/// 언어 한 줄: 체크(IsSelected) · 국기(LanguageToFlagImageConverter) · 이름(LanguageToFlagConverter)
private struct SwitchLanguageRow: View {
    @Environment(EngineClient.self) private var engine
    let state: SwitchLanguageState
    let item: SwitchLanguageState.Item

    var body: some View {
        let info = engine.store.object(item.id)

        HStack(spacing: 6) {
            Toggle("", isOn: Binding(get: { item.isSelected }, set: { state.setSelected(item.id, $0) }))
                .labelsHidden()
            RemoteImage(value: engine.converted("LanguageToFlagImageConverter", info, "Language"), size: 20)
            Text(engine.converted("LanguageToFlagConverter", info, "Language")?.string ?? item.language)
                .font(.callout)
        }
    }
}
