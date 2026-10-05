// upstream: RomForge/Controls/PS/ConverterTab.xaml(.cs)
// ViewModel: PSPConverterViewModel (PS1MainViewModel.ConverterVM)
import SwiftUI

/// 포맷 변환: ISO / CSO / ZSO / CHD 상호 변환. 항목마다 출력 형식을 고른다.
struct PSConverterTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject
    @State private var selection = Set<Int>()
    @State private var sortOrder: [PSColumnSort] = []

    /// IsEnabled="{Binding IsConverting, Converter=InverseBool}"
    private var isIdle: Bool { !(vm["IsConverting"]?.bool ?? false) }

    var body: some View {
        ToolLayout(vm: vm) {
            Table(PSColumnSort.sorted(engine.items(vm, "FileItems"), by: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                TableColumn("No.", sortUsing: PSColumnSort(prop: "No")) { item in
                    Text(item.string("No"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .width(min: 40, ideal: 50)

                TableColumn("파일명", sortUsing: PSColumnSort(prop: "FileName")) { item in
                    Text(item.string("FileName"))
                        .lineLimit(1)
                        .help(item.string("FilePath"))
                }
                .width(min: 160, ideal: 300)

                TableColumn("입력", sortUsing: PSColumnSort(prop: "Extension")) { item in
                    ExtensionBadge(item: item).frame(maxWidth: .infinity, alignment: .center)
                }
                .width(min: 60, ideal: 75)

                TableColumn("출력") { item in PSTargetFormatPicker(item: item).cellEnvironment(engine) }
                    .width(min: 70, ideal: 90)

                TableColumn("용량", sortUsing: PSColumnSort(prop: "FileSizeBytes")) { item in
                    Text(item.string("FileSize"))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 70, ideal: 90)

                TableColumn("진행률", sortUsing: PSColumnSort(prop: "Progress")) { item in PSProgressCell(item: item) }
                    .width(min: 100, ideal: 120)
            }
            .overlay {
                if vm.isVisible("HintVisibility") {
                    PSHint(title: "파일 또는 폴더를 여기에 드래그&드롭하세요",
                           detail: "하기 파일 포맷을 상호 변환합니다",
                           badges: ["ISO", "CSO", "ZSO", "CHD"])
                }
            }
            .modifier(PSFileListBehavior(engine: engine, vm: vm, selection: $selection, enabled: isIdle))
        } options: {
            HStack(spacing: 6) {
                IconButton(title: "파일 추가", icon: "AddFile.png", enabled: isIdle) {
                    PSFileActions.addFiles(engine, vm, filter: "PS 파일|*.iso;*.cso;*.zso;*.chd|모든 파일|*.*",
                                           title: "변환할 파일 선택")
                }
                IconButton(title: "폴더 추가", icon: "AddFolder.png", enabled: isIdle) {
                    PSFileActions.addFolder(engine, vm)
                }
                IconButton(title: "선택 삭제", icon: "Delete.png", enabled: isIdle) {
                    PSFileActions.remove(engine, vm, selection)
                    selection.removeAll()
                }
                IconButton(title: "전체 삭제", icon: "Clear.png", enabled: isIdle) {
                    PSFileActions.clear(engine, vm)
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
struct PSTargetFormatPicker: View {
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
