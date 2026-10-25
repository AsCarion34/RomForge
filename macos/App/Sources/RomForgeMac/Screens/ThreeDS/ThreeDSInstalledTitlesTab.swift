// upstream: RomForge/Controls/3DS/InstalledTitlesTab.xaml(.cs)
// ViewModel: InstallerMainViewModel (Main3DsVM.InstallerVM), InstalledTitlesMainViewModel (InstallerVM.InstalledTitles), TitleViewModel
import AppKit
import SwiftUI

/// 3DS 설치된 게임목록: 검색·종류 필터, title.db 복구, 게임목록 불러오기, 목록(CIA/CCI로 추출).
/// DataContext는 InstallerMainViewModel(vm)이고 목록은 vm.InstalledTitles.FilteredTitles다.
struct ThreeDSInstalledTitlesTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    @State private var selection = Set<Int>()
    /// SearchBox.Text, 필터 ToggleButton(Tag). upstream 컨트롤은 탭을 바꿔도 남아 있으므로 화면이 다시 만들어져도 유지한다.
    @State private var search: String
    @State private var filter: String

    private static let recoverTip = """
        3DS 실기에서 title.db 오류로 설치한 게임이 HOME 메뉴에 나타나지 않거나 인식되지 않을 때 사용합니다.

        SD 카드에 설치된 타이틀을 기준으로 title.db와 import.db를 새로 만듭니다.
        기존 title.db / import.db는 삭제되며, 게임 파일은 변경되지 않습니다.
        정상적으로 인식되고 있다면 누를 필요가 없습니다.
        """

    init(vm: RemoteObject) {
        self.vm = vm
        _search = State(initialValue: threeDSTitleSearch[vm.id]?.search ?? "")
        _filter = State(initialValue: threeDSTitleSearch[vm.id]?.filter ?? "All")
    }

    var body: some View {
        ChildVM(id: vm.ref("InstalledTitles")) { titles in
            VStack(spacing: 0) {
                toolbar(titles)
                content(titles)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .observeLists(engine, titles, ["FilteredTitles"])
        }
    }

    // MARK: 상단

    private func toolbar(_ titles: RemoteObject) -> some View {
        let unlocked = vm["IsUnlocked"]?.bool ?? true
        let canLoad = vm["CanLoad"]?.bool ?? false

        return HStack(spacing: 8) {
            TextField("🔍   게임 검색...", text: $search)
                .textFieldStyle(.roundedBorder)
                .onChange(of: search) { _, text in
                    // Search_TextChanged → InstalledTitles.RefreshFilter(SearchBox.Text)
                    remember()
                    engine.invoke(titles, "RefreshFilter", [.string(text)])
                }

            // FilterAll / FilterGame / FilterUpdate / FilterDlc(Tag) → Filter_Click
            Picker("", selection: filterBinding(titles)) {
                Text("전체").tag("All")
                Text("본편").tag("Game")
                Text("업데이트").tag("Update")
                Text("DLC").tag("Dlc")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(!unlocked)

            Button { recover() } label: { IconLabel(title: "title.db 복구", icon: "Recover.png") }
                .buttonStyle(.borderedProminent)
                .disabled(!canLoad)
                .help(Self.recoverTip)

            Button { load() } label: { IconLabel(title: "게임목록 불러오기", icon: "Loading.png") }
                .buttonStyle(.borderedProminent)
                .disabled(!canLoad)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func filterBinding(_ titles: RemoteObject) -> Binding<String> {
        Binding(get: { filter }, set: { tag in
            filter = tag
            remember()
            engine.invoke(titles, "SetFilter", [.string(tag), .string(search)])
        })
    }

    private func remember() {
        threeDSTitleSearch[vm.id] = (search, filter)
    }

    // MARK: 본문(로딩 / 비어 있음 / 목록)

    @ViewBuilder
    private func content(_ titles: RemoteObject) -> some View {
        ZStack {
            if titles.isVisible("LoadingVisibility") {
                // LoadingText·LoadingProgress: code-behind의 onProgress가 "로딩 중... 현재 / 전체"와 현재/전체로 바꾼다.
                // 같은 때 ViewModel도 ProgressLabel·ProgressPct를 같은 값으로 바꾸므로 그것을 보여 준다
                // (아직 진행 보고가 없으면 XAML 기본값 "로딩 중...").
                let label = vm.string("ProgressLabel")
                VStack(spacing: 12) {
                    Text("⏳").font(.system(size: 36))
                    Text(label.hasPrefix("로딩 중") ? label : "로딩 중...")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: min(max((vm["ProgressPct"]?.double ?? 0) / 100, 0), 1))
                        .frame(width: 240)
                }
            }

            if titles.isVisible("EmptyVisibility") {
                ThreeDSHint(icon: "SdCard.png", iconSize: 48, title: "SD 카드를 선택하고 설치 목록을 불러오세요")
            }

            if titles.isVisible("ListVisibility") {
                table(titles)
            }
        }
    }

    private func table(_ titles: RemoteObject) -> some View {
        let rows = engine.items(titles, "FilteredTitles")

        return Table(rows, selection: $selection) {
            TableColumn("타이틀") { item in
                ThreeDSTitleCell(item: item, pathTooltip: false)
                    .task(id: item.ref("Title")) { await describeTitle(item) }
                    .cellEnvironment(engine)
            }
            .width(min: 200, ideal: 300)
            TableColumn("종류") { item in ThreeDSTypeBadge(item: item) }
                .width(90)
            TableColumn("제품 코드") { item in ThreeDSCodeCell(item: item) }
                .width(140)
            TableColumn("") { item in ThreeDSRegionCell(item: item).cellEnvironment(engine) }
                .width(60)
            TableColumn("") { item in ThreeDSLockCell(item: item).cellEnvironment(engine) }
                .width(60)
            TableColumn("용량") { item in
                Text(item.string("SizeText"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(90)
        }
        .disabled(!(vm["IsUnlocked"]?.bool ?? true))
        .contextMenu(forSelectionType: Int.self) { ids in
            // ContextMenu_Opening: InstalledTitles가 작업 중이면 열지 않는다. CCI 추출은 모두 본편(IsApplication)일 때만.
            if !ids.isEmpty, !(titles["IsLocked"]?.bool ?? false) {
                Button { extract(rows, ids, asCci: false) } label: { MenuLabel(title: "CIA로 추출", icon: "DLC.png") }
                if allApplications(ids) {
                    Button { extract(rows, ids, asCci: true) } label: { MenuLabel(title: "CCI로 추출", icon: "Cartridge.png") }
                }
            }
        }
    }

    /// 메뉴 판단에 쓰는 TitleViewModel.Title(InstalledTitle)을 받아 둔다.
    private func describeTitle(_ item: RemoteObject) async {
        guard let id = item.ref("Title"), engine.store.object(id) == nil else { return }
        await engine.describe(id)
    }

    /// selected.All(t => t.Title.IsApplication)
    private func allApplications(_ ids: Set<Int>) -> Bool {
        ids.allSatisfy { id in
            engine.store.object(engine.store.object(id)?.ref("Title"))?["IsApplication"]?.bool == true
        }
    }

    // MARK: code-behind 처리기

    /// LoadTitles_Click: LoadTitlesAsync(onProgress) — 실패하면 "로드 실패: …" + 오류음
    /// (onProgress가 하던 LoadingText·LoadingProgress 갱신은 ViewModel의 ProgressLabel·ProgressPct로 보여 준다)
    private func load() {
        run("LoadTitlesAsync", [.null, .null], failure: "로드 실패")
    }

    /// RecoverTitleDb_Click: RecoverTitleDbAsync() — 실패하면 "복구 실패: …" + 오류음
    private func recover() {
        run("RecoverTitleDbAsync", [.null], failure: "복구 실패")
    }

    /// upstream은 메서드가 곧바로 CanLoad를 끈다. 엔진의 CanLoad가 도착하기 전 두 번째 클릭으로 두 번 부르지 않게 막는다.
    private func run(_ method: String, _ args: [JSONValue], failure: String) {
        let installer = vm
        guard !threeDSTitlesBusy.contains(installer.id) else { return }
        threeDSTitlesBusy.insert(installer.id)
        Task {
            if case .failure(let error) = await ThreeDSBridge.call(engine, installer.id, method, args) {
                await ThreeDSBridge.fail(engine, installer, "\(failure): \(error.localizedDescription)")
            }
            threeDSTitlesBusy.remove(installer.id)
        }
    }

    /// ExtractTitle_Click: SaveFileDialog → ExtractTitleAsync(선택, 경로, asCci) → 파일이 있으면 "추출 완료: …"
    /// (실패하면 "추출 실패: …" + 오류음)
    private func extract(_ rows: [RemoteObject], _ ids: Set<Int>, asCci: Bool) {
        guard let selected = rows.first(where: { ids.contains($0.id) }) else { return }

        let (ext, desc) = asCci ? ("cci", "CCI(CTR Cartridge Image)") : ("cia", "CIA(CTR Importable Archive)")
        guard let path = ThreeDSDialogs.saveFile(title: "\(desc) 저장 위치 선택",
                                                 filter: "\(desc) 파일|*.\(ext)",
                                                 fileName: "\(selected.string("ShortDescription")).\(ext)") else { return }

        let installer = vm
        Task {
            switch await ThreeDSBridge.call(engine, installer.id, "ExtractTitleAsync", [EngineClient.ref(selected.id), .string(path), .bool(asCci)]) {
            case .success:
                if FileManager.default.fileExists(atPath: path) {
                    ThreeDSBridge.log(engine, installer, "추출 완료: \(path)", "Ok")
                }
            case .failure(let error):
                await ThreeDSBridge.fail(engine, installer, "추출 실패: \(error.localizedDescription)")
            }
        }
    }
}

@MainActor private var threeDSTitleSearch: [Int: (search: String, filter: String)] = [:]

/// LoadTitlesAsync / RecoverTitleDbAsync를 부른 뒤 끝날 때까지의 InstallerMainViewModel 번호
@MainActor private var threeDSTitlesBusy: Set<Int> = []
