// upstream: RomForge/Controls/Switch/SplitFileListControl.xaml(.cs)
// ViewModel: RomForge.ViewModels.Switch.SplitMainViewModel(Rows), 항목 RomForge.ViewModels.Switch.SplitRowViewModel
import AppKit
import SwiftUI

/// 분리 탭의 파일 목록. 통합롬은 펼치기 단추로 본편/업데이트/DLC 행을 펼쳐 고른다(펼치기·선택·삭제는 ViewModel).
/// 펼친 하위 행은 ViewModel이 Rows에 끼워 넣으므로 목록은 Rows를 그대로 그린다.
struct SwitchSplitFileList: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    @State private var selection = Set<Int>()

    var body: some View {
        let rows = engine.items(vm, "Rows")

        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                selectAll
                table(rows)
            }
            sideButtons(rows)
        }
        .padding(10)
    }

    /// 첫 열 머리글 CheckBox(IsChecked="True", HeaderCheckBox_Click → SelectAll). SwiftUI 표 머리글에는 컨트롤을 둘 수 없어 표 위에 둔다.
    private var selectAll: some View {
        let state = SwitchStore.split(vm.id)

        return Toggle("전체 선택 / 해제", isOn: Binding(get: { state.allChecked }, set: { isOn in
            state.allChecked = isOn
            engine.invoke(vm, "SelectAll", [.bool(isOn)])
        }))
        .toggleStyle(.checkbox)
        .help("전체 선택 / 해제")
    }

    private func table(_ rows: [RemoteObject]) -> some View {
        Table(rows, selection: $selection) {
            // 머리글: 전체 선택 CheckBox(표 위로 옮김)
            TableColumn("") { row in SwitchSplitSelectCell(owner: vm, row: row).cellEnvironment(engine) }
                .width(64)
            // 머리글: Categories.png(글자 없음)
            TableColumn("") { row in
                SwitchBadge(text: row.string("TypeText"), background: row["TypeBackground"]?.color, foreground: row["TypeForeground"]?.color)
                    .frame(maxWidth: .infinity)
            }
            .width(70)
            // 하위 행(IsChild)은 아이콘을 접는다.
            TableColumn("타이틀") { row in
                SwitchTitleCell(item: row, title: "Name", subtitle: "TitleId", showsIcon: row["IsChild"]?.bool != true)
                    .cellEnvironment(engine)
            }
            .width(min: 200, ideal: 380)
            TableColumn("버전") { row in
                Text(row.string("Version")).fontWeight(.bold).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(120)
            // 머리글: Extension.png(글자 없음). 하위 행은 확장자 배지를 숨긴다.
            TableColumn("") { row in
                if row["IsChild"]?.bool != true {
                    SwitchBadge(text: row.string("Extension"), background: row["ExtensionBackground"]?.color, foreground: row["ExtensionForeground"]?.color)
                        .frame(maxWidth: .infinity)
                }
            }
            .width(50)
            // Res.Header_Size
            TableColumn("용량") { row in
                Text(row.string("SizeText")).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(75)
        }
        .overlay {
            // dropHint Visibility = HasFiles(InverseBooleanToVisibilityConverter)
            if vm["HasFiles"]?.bool != true {
                SwitchDropHint(title: "게임 파일 / 폴더를 여기에 드래그&드롭하세요",
                               detail: "통합롬은 + 버튼으로 펼쳐서 본편/업데이트/DLC를 골라 분리할 수 있습니다")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            addFiles(urls.map(\.path))
            return true
        }
        .onDeleteCommand { remove(selection) }
        .contextMenu(forSelectionType: Int.self) { ids in
            if !ids.isEmpty {
                Button("폴더 열기") {
                    if let id = SwitchBridge.ordered(ids, in: rows).first, let row = engine.store.object(id) {
                        SwitchPanels.showContainingFolder(row.string("FilePath"))
                    }
                }
                Divider()
                Button("선택 삭제") { remove(ids) }
                Button("전체 삭제") { clearAll() }
            }
        }
    }

    private func sideButtons(_ rows: [RemoteObject]) -> some View {
        VStack(spacing: 8) {
            // Res.ToolTip_AddFile
            ToolIconButton(icon: "AddFile.png", help: "파일 추가") {
                // Res.Dialog_SelectGameFile, Res.Filter_SwitchFiles(… *.nsp;*.xci;*.nsz;*.xcz)|Res.Filter_AllFiles|*.*
                addFiles(SwitchPanels.openFiles(title: "게임 파일 선택", extensions: SwitchPanels.switchExtensions, multiple: true))
            }
            ToolIconButton(icon: "AddFolder.png", help: "폴더 추가") {
                if let folder = SwitchPanels.openFolder(title: "게임 폴더 선택") { addFiles([folder]) }
            }
            // Res.ToolTip_RemoveSelected
            ToolIconButton(icon: "Delete.png", help: "선택 항목 제거") { remove(selection) }
            // Res.ToolTip_RemoveAll
            ToolIconButton(icon: "Clear.png", help: "전체 항목 제거") { clearAll() }
        }
    }

    // MARK: 동작

    /// LvFiles_Drop / BtnAddFile_Click / BtnAddFolder_Click: ViewModel.AddFilesAsync(Common.Utils.ExpandPaths(paths))
    private func addFiles(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        Task {
            let expanded = await SwitchBridge.expandPaths(engine, paths)
            await engine.call(vm.id, "AddFilesAsync", [expanded])
        }
    }

    /// LvFiles_KeyUp(Delete) / BtnRemoveFile_Click: ViewModel.RemoveRows(선택 행)
    private func remove(_ ids: Set<Int>) {
        guard !ids.isEmpty else { return }
        engine.invoke(vm, "RemoveRows", [EngineClient.refs(ids)])
        selection.subtract(ids)
    }

    /// BtnRemoveAllFiles_Click: ViewModel.ClearAll()
    private func clearAll() {
        engine.invoke(vm, "ClearAll")
        selection.removeAll()
    }
}

/// 첫 열: 펼치기 / 접기 단추(CanExpand, 펼치면 90° 돌린 화살표) + CheckBox(IsChecked, 하위 행 일부만 고르면 '일부 선택')
private struct SwitchSplitSelectCell: View {
    @Environment(EngineClient.self) private var engine
    let owner: RemoteObject
    let row: RemoteObject

    var body: some View {
        let expanded = row["IsExpanded"]?.bool == true

        HStack(spacing: 2) {
            ZStack {
                if row["CanExpand"]?.bool == true {
                    // BtnExpand_Click: ViewModel.ToggleExpand(row)
                    Button {
                        engine.invoke(owner, "ToggleExpand", [EngineClient.ref(row.id)])
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .foregroundStyle(expanded ? Color.accentColor : Color.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("펼치기 / 접기")
                }
            }
            .frame(width: 24, height: 22)

            SwitchCheckbox(value: row["IsChecked"]?.bool) { isOn in
                engine.bool(row, "IsChecked").wrappedValue = isOn
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
