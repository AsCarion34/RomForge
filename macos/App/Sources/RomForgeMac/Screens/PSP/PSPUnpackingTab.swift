// upstream: RomForge/Controls/PSP/UnpackingTab.xaml(.cs)
// ViewModel: UnpackingMainViewModel (PSPMainViewModel.UnPackingVM)
import SwiftUI

/// PBP 언팩: PBP 목록(아이콘·타이틀·로컬 타이틀·언어 국기) → BIN+CUE 복원
struct PSPUnpackingTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject
    @State private var selection = Set<Int>()
    @State private var sortOrder: [ColumnSort] = []

    /// IsEnabled="{Binding IsConverting, Converter=InverseBool}"
    private var isIdle: Bool { !(vm["IsConverting"]?.bool ?? false) }

    var body: some View {
        ToolLayout(vm: vm) {
            Table(ColumnSort.sorted(engine.items(vm, "FileItems"), by: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                TableColumn("No.", sortUsing: ColumnSort("No", natural: true)) { item in
                    Text(item.string("No"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .width(min: 40, ideal: 50)

                TableColumn("타이틀", sortUsing: ColumnSort("FileName", natural: true)) { item in
                    HStack(spacing: 10) {
                        RemoteImage(value: item["Icon"], size: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.string("TitleName")).fontWeight(.semibold).lineLimit(1)
                            Text(item.string("TitleId")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(.vertical, 4)
                    .help(item.string("FilePath"))
                    .cellEnvironment(engine)
                }
                .width(min: 180, ideal: 270)

                TableColumn("로컬 타이틀", sortUsing: ColumnSort("TitleLocalName", natural: true)) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.string("TitleLocalName")).fontWeight(.semibold).lineLimit(1)
                        PSPLanguageFlags(item: item)
                    }
                    .padding(.vertical, 4)
                    .cellEnvironment(engine)
                }
                .width(min: 180, ideal: 270)

                TableColumn("용량", sortUsing: ColumnSort("FileSizeBytes", natural: true)) { item in
                    Text(item.string("FileSize"))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 70, ideal: 90)

                TableColumn("진행률", sortUsing: ColumnSort("Progress", natural: true)) { item in PSPProgressCell(item: item) }
                    .width(min: 100, ideal: 120)
            }
            .overlay {
                if vm.isVisible("HintVisibility") {
                    PSPHint(icon: "Info.png",
                            title: "파일 또는 폴더를 여기에 드래그&드롭하세요",
                            detail: "PBP를 원본 BIN+CUE로 복원합니다",
                            badges: ["PBP"])
                }
            }
            // LvFiles_Drop: 폴더가 아닌 .pbp 파일만 AddPaths에 넘긴다.
            .modifier(PSPFileListBehavior(engine: engine, owner: vm, selection: $selection, enabled: isIdle,
                                          dropPaths: { urls in
                                              urls.filter { !FilePanels.isDirectory($0.path) && $0.pathExtension.lowercased() == "pbp" }
                                                  .map(\.path)
                                          }))
        } options: {
            HStack(spacing: 6) {
                IconButton(title: "파일 추가", icon: "AddFile.png", enabled: isIdle) {
                    PSPFileActions.addFiles(engine, vm, filter: "PBP 파일|*.pbp|모든 파일|*.*", title: "파일 선택")
                }
                IconButton(title: "폴더 추가", icon: "AddFolder.png", enabled: isIdle) {
                    PSPFileActions.addFolder(engine, vm)
                }
                IconButton(title: "선택 삭제", icon: "Delete.png", enabled: isIdle) {
                    PSPFileActions.remove(engine, vm, selection)
                    selection.removeAll()
                }
                IconButton(title: "전체 삭제", icon: "Clear.png", enabled: isIdle) {
                    PSPFileActions.clear(engine, vm)
                    selection.removeAll()
                }

                Spacer()

                CommandIconButton(title: "시작", icon: "Run.png", vm: vm, command: "RunCommand", enabled: isIdle, prominent: true)
                CommandIconButton(title: "취소", icon: "Cancel.png", vm: vm, command: "CancelCommand", enabled: !isIdle)
            }
        }
    }
}

/// 로컬 타이틀 아래 언어 국기(ItemsSource=Languages, PbpLanguageToFlagConverter)
struct PSPLanguageFlags: View {
    @Environment(EngineClient.self) private var engine
    let item: RemoteObject

    var body: some View {
        let listId = item.ref("Languages")
        let languages = engine.store.items(listId).compactMap(\.string)

        HStack(spacing: 3) {
            ForEach(Array(languages.enumerated()), id: \.offset) { _, language in
                // 목록 항목(문자열)이라 속성 경로가 없다. 값으로 변환기를 부른다.
                RemoteImage(value: engine.converted("PbpLanguageToFlagConverter", value: .string(language)), size: 16)
            }
        }
        .task(id: listId) { await engine.observeList(listId) }
    }
}
