// upstream: RomForge/Controls/3DS/DecryptorTab.xaml(.cs)
// ViewModel: DecryptorMainViewModel (Main3DsVM.DecryptorVM), DecryptorFileItem
import AppKit
import SwiftUI

/// 3DS 복호화: 파일 목록 + 파일 추가·삭제, 시작 / 취소.
struct ThreeDSDecryptorTab: View {
    @Environment(EngineClient.self) private var engine
    let vmId: Int?

    @State private var selection = Set<Int>()
    /// GridViewColumnHeader_Click(ListViewColumnSorter)
    @State private var sortOrder: [ThreeDSColumnSort] = []

    var body: some View {
        ChildVM(id: vmId) { vm in
            let busy = vm["IsDecrypting"]?.bool ?? false

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
        let rows = engine.items(vm, "FileItems").sorted(using: sortOrder)

        return Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("", sortUsing: ThreeDSColumnSort("No")) { item in
                Text(item.string("No")).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            .width(40)
            TableColumn("타이틀", sortUsing: ThreeDSColumnSort("FileName")) { item in ThreeDSTitleCell(item: item).cellEnvironment(engine) }
                .width(min: 160, ideal: 220)
            TableColumn("종류", sortUsing: ThreeDSColumnSort("TypeLabel")) { item in ThreeDSTypeBadge(item: item) }
                .width(90)
            TableColumn("형식", sortUsing: ThreeDSColumnSort("Extension")) { item in ThreeDSExtensionBadge(item: item) }
                .width(75)
            TableColumn("", sortUsing: ThreeDSColumnSort("Crypto")) { item in ThreeDSLockCell(item: item).cellEnvironment(engine) }
                .width(40)
            TableColumn("용량", sortUsing: ThreeDSColumnSort("FileSizeBytes")) { item in
                Text(item.string("FileSize")).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(80)
            TableColumn("진행률", sortUsing: ThreeDSColumnSort("Progress")) { item in ThreeDSProgressCell(item: item) }
                .width(110)
        }
        .overlay {
            if vm.isVisible("HintVisibility") {
                ThreeDSHint(title: "파일 또는 폴더를 여기에 드래그&드롭하세요",
                            detail: "파일을 복호화합니다",
                            badges: ["3DS", "CCI", "CIA"])
            }
        }
        // ListView IsEnabled="{Binding IsDecrypting, Converter=InverseBool}"
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

    /// BtnAddFiles_Click: OpenFileDialog(Title "복호화할 파일 선택", Multiselect, Filter "3DS ROM 파일|*.3ds;*.cci;*.cia") → AddPaths
    private func addFilesDialog(_ vm: RemoteObject) {
        let paths = ThreeDSDialogs.openFiles(title: "복호화할 파일 선택", filter: "3DS ROM 파일|*.3ds;*.cci;*.cia", multiple: true)
        if !paths.isEmpty { engine.invoke(vm, "AddPaths", [.strings(paths)]) }
    }

    /// BtnAddFolder_Click: 폴더 선택("추가할 폴더를 선택하세요") → AddPaths([폴더])
    private func addFolderDialog(_ vm: RemoteObject) {
        guard let folder = ThreeDSDialogs.openFolder(title: "추가할 폴더를 선택하세요") else { return }
        engine.invoke(vm, "AddPaths", [.strings([folder])])
    }
}
