// upstream: RomForge/Controls/PSP/ConverterTab.xaml(.cs)
// ViewModel: ConverterViewModel (PSPMainViewModel.ConverterVM)
import SwiftUI

/// 포맷 변환: ISO / CSO / ZSO / CHD 상호 변환. 항목마다 출력 형식을 고른다.
struct PSPConverterTab: View {
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

                TableColumn("파일명", sortUsing: ColumnSort("FileName", natural: true)) { item in
                    Text(item.string("FileName"))
                        .lineLimit(1)
                        .help(item.string("FilePath"))
                }
                .width(min: 160, ideal: 300)

                TableColumn("입력", sortUsing: ColumnSort("Extension", natural: true)) { item in
                    ExtensionBadge(item: item).frame(maxWidth: .infinity, alignment: .center)
                }
                .width(min: 60, ideal: 75)

                // 머리글 Tag="TargetFormat"은 항목에 없는 속성이라 upstream에서도 정렬되지 않는다.
                TableColumn("출력") { item in PSPTargetFormatPicker(item: item).cellEnvironment(engine) }
                    .width(min: 70, ideal: 90)

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
                            detail: "하기 파일 포맷을 상호 변환합니다",
                            badges: ["ISO", "CSO", "ZSO", "CHD"])
                }
            }
            .modifier(PSPFileListBehavior(engine: engine, owner: vm, selection: $selection, enabled: isIdle))
        } options: {
            HStack(spacing: 6) {
                IconButton(title: "파일 추가", icon: "AddFile.png", enabled: isIdle) {
                    PSPFileActions.addFiles(engine, vm, filter: "PS 파일|*.iso;*.cso;*.zso;*.chd|모든 파일|*.*",
                                            title: "변환할 파일 선택")
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

/// 출력 형식 ComboBox(ItemsSource=AvailableFormats, SelectedItem=SelectedTargetFormat)
struct PSPTargetFormatPicker: View {
    @Environment(EngineClient.self) private var engine
    let item: RemoteObject

    var body: some View {
        let listId = item.ref("AvailableFormats")
        let formats = engine.store.items(listId).compactMap(\.string)

        Picker("", selection: engine.string(item, "SelectedTargetFormat")) {
            ForEach(formats, id: \.self) { format in
                Text(format).tag(format)
            }
        }
        .labelsHidden()
        .task(id: listId) { await engine.observeList(listId) }
    }
}
