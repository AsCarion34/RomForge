// upstream: RomForge/Controls/3DS/ConverterTab.xaml(.cs)
// ViewModel: ConverterMainViewModel (Main3DsVM.ConverterVM), FileItem
import AppKit
import SwiftUI

/// 3DS 포맷 변환: 파일 목록(출력 포맷 선택) + 파일 추가·삭제, 시작 / 취소.
struct ThreeDSConverterTab: View {
    @Environment(EngineClient.self) private var engine
    let vmId: Int?

    @State private var selection = Set<Int>()
    /// GridViewColumnHeader_Click(ListViewColumnSorter)
    @State private var sortOrder: [ColumnSort] = []

    var body: some View {
        ChildVM(id: vmId) { vm in
            let busy = vm["IsConverting"]?.bool ?? false

            VStack(spacing: 0) {
                list(vm, busy: busy)
                Divider()
                ThreeDSListFooter(vm: vm, busy: busy,
                                  addFiles: { addFilesDialog(vm) },
                                  addFolder: { addFolderDialog(vm) },
                                  removeSelected: {
                                      remove(vm, selection)
                                      selection.removeAll()
                                  },
                                  clearAll: {
                                      engine.invoke(vm, "ClearItems")
                                      selection.removeAll()
                                  })
            }
            .observeLists(engine, vm, ["FileItems"])
        }
    }

    private func list(_ vm: RemoteObject, busy: Bool) -> some View {
        let rows = ColumnSort.sorted(engine.items(vm, "FileItems"), by: sortOrder)

        return Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("", sortUsing: ColumnSort("No")) { item in
                Text(item.string("No")).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            .width(40)
            TableColumn("타이틀", sortUsing: ColumnSort("FileName")) { item in ThreeDSTitleCell(item: item).cellEnvironment(engine) }
                .width(min: 140, ideal: 160)
            TableColumn("종류", sortUsing: ColumnSort("TypeLabel")) { item in ThreeDSTypeBadge(item: item) }
                .width(90)
            TableColumn("입력", sortUsing: ColumnSort("Extension")) { item in ThreeDSExtensionBadge(item: item) }
                .width(75)
            TableColumn("출력", sortUsing: ColumnSort("Extension")) { item in ThreeDSOutputFormatCell(item: item).cellEnvironment(engine) }
                .width(80)
            TableColumn("", sortUsing: ColumnSort("RegionSortKey")) { item in ThreeDSRegionCell(item: item).cellEnvironment(engine) }
                .width(50)
            TableColumn("", sortUsing: ColumnSort("Crypto")) { item in ThreeDSLockCell(item: item).cellEnvironment(engine) }
                .width(40)
            TableColumn("용량", sortUsing: ColumnSort("FileSizeBytes")) { item in
                Text(item.string("FileSize")).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(80)
            TableColumn("진행률", sortUsing: ColumnSort("Progress")) { item in ThreeDSProgressCell(item: item) }
                .width(110)
        }
        .overlay {
            if vm.isVisible("HintVisibility") {
                ThreeDSHint(title: "파일 또는 폴더를 여기에 드래그&드롭하세요",
                            detail: "하기 파일 포맷을 상호 변환합니다",
                            badges: ["3DS", "CCI", "CIA", "ZCCI"])
            }
        }
        // ListView IsEnabled="{Binding IsConverting, Converter=InverseBool}"
        .modifier(ThreeDSListBehavior(
            selection: $selection,
            enabled: !busy,
            rows: rows,
            drop: { paths in engine.invoke(vm, "AddPaths", [.strings(paths)]) },   // LvFiles_Drop
            remove: { ids in remove(vm, ids) },
            clear: { engine.invoke(vm, "ClearItems") }
        ))
    }

    /// BtnRemove_Click / Delete 키: RemoveItems(선택 항목)
    private func remove(_ vm: RemoteObject, _ ids: Set<Int>) {
        guard !ids.isEmpty else { return }
        engine.invoke(vm, "RemoveItems", [EngineClient.refs(ids)])
    }

    /// BtnAddFiles_Click: OpenFileDialog(Title "변환할 파일 선택", Multiselect, Filter InstallMainViewModel.GetFileDialogFilter()) → AddPaths
    private func addFilesDialog(_ vm: RemoteObject) {
        Task {
            let filter = await engine.callStatic("RomForge.ViewModels._3DS.InstallMainViewModel", "GetFileDialogFilter")?.string
            let paths = ThreeDSDialogs.openFiles(title: "변환할 파일 선택", filter: filter, multiple: true)
            if !paths.isEmpty { engine.invoke(vm, "AddPaths", [.strings(paths)]) }
        }
    }

    /// BtnAddFolder_Click: 폴더 선택("추가할 폴더를 선택하세요") → AddPaths([폴더])
    private func addFolderDialog(_ vm: RemoteObject) {
        guard let folder = ThreeDSDialogs.openFolder(title: "추가할 폴더를 선택하세요") else { return }
        engine.invoke(vm, "AddPaths", [.strings([folder])])
    }
}

/// "출력" 열: ComboBox ItemsSource=AvailableFormats, SelectedItem=SelectedTargetFormat
private struct ThreeDSOutputFormatCell: View {
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
        .controlSize(.small)
        .task(id: listId) { await engine.observeList(listId) }
    }
}
