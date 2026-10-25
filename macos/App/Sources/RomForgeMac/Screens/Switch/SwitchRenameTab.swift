// upstream: RomForge/Controls/Switch/RenameTab.xaml(.cs)
// ViewModel: RomForge.ViewModels.Switch.RenameMainViewModel (SwitchMainViewModel.RenameVM), 항목 RomForge.Core.Models.Switch.RenameFileItem
import AppKit
import SwiftUI

/// 파일명 변경 탭: 파일 목록(현재 / 변경 이름 비교), 파일명 포맷, 파일 추가·삭제, 시작 / 취소.
/// 미리보기(NewName·Status·Summary)와 이름 바꾸기는 ViewModel이 한다.
struct SwitchRenameTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    @State private var selection = Set<Int>()
    @State private var sortOrder: [SwitchColumnSort] = []
    /// RenameMainViewModel.NamingPresets(정적 속성 → RenamePresets.All) 목록 번호
    @State private var presetsId: Int?

    private static let viewModel = "RomForge.ViewModels.Switch.RenameMainViewModel"

    /// txtFormat ToolTip
    private static let formatHelp = """
        {Name}: 한글 + 영어 제목 (병합 파일명과 동일)
        {KTitleName}: 한글 제목
        {TitleName}: 한글 → 영어 → 첫 번째 제목 순
        {TitleID}: 타이틀 ID
        {Tag}: 구성 (B+U+10D)
        {DisplayVersion}: 표시 버전 (1.0.0)
        {Version}: 버전 (65536)
        """

    private static let availableItems = "사용 가능한 항목: {Name}  {KTitleName}  {TitleName}  {TitleID}  {Tag}  {DisplayVersion}  {Version}  (확장자는 자동으로 유지됩니다)"

    var body: some View {
        let items = engine.items(vm, "Items")
        let locked = vm["IsLocked"]?.bool ?? false

        ToolLayout(vm: vm, lists: ["Items", "LogEntries"]) {
            // IsEnabled = !IsLocked
            table(items)
                .disabled(locked)
                .padding(.horizontal, 5)
        } options: {
            VStack(spacing: 8) {
                formatBox
                    .disabled(!(vm["IsIdle"]?.bool ?? true))
                buttons(locked: locked)
            }
        }
        .task(id: vm.id) {
            presetsId = await engine.callStatic(Self.viewModel, "get_NamingPresets")?.refId
            await engine.observeList(presetsId)
        }
    }

    // MARK: 목록

    private func table(_ items: [RemoteObject]) -> some View {
        Table(SwitchColumnSort.apply(sortOrder, to: items), selection: $selection, sortOrder: $sortOrder) {
            // 머리글: Categories.png(글자 없음), Tag="Status"
            TableColumn("", sortUsing: SwitchColumnSort(prop: "Status")) { item in
                Text(item.string("Status"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: item.string("StatusColor").nonEmpty ?? "#888888"))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .width(80)
            TableColumn("파일명 비교 (현재 / 변경)", sortUsing: SwitchColumnSort(prop: "OldName")) { item in
                SwitchRenameNameCell(item: item).cellEnvironment(engine)
            }
            .width(min: 300, ideal: 770)
        }
        .overlay {
            if vm.isVisible("HintVisibility") {
                SwitchDropHint(title: "파일 또는 폴더를 여기에 드래그하세요", detail: "선택한 포맷에 맞춰 파일명을 일괄 변경합니다")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            addPaths(urls.map(\.path), expand: true)
            return true
        }
        .onDeleteCommand { remove(selection) }
        .contextMenu(forSelectionType: Int.self) { ids in
            if !ids.isEmpty {
                Button("폴더 열기") {
                    if let id = SwitchBridge.ordered(ids, in: items).first, let item = engine.store.object(id) {
                        SwitchPanels.showContainingFolder(item.string("FilePath"))
                    }
                }
                Divider()
                Button("선택 삭제") { remove(ids) }
                Button("전체 삭제") { engine.invoke(vm, "ClearItems") }
            }
        }
    }

    // MARK: 파일명 포맷

    private var formatBox: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text("파일명 포맷:").fontWeight(.semibold)
                presetPicker
                    .frame(width: 380)
                formatField
            }
            HStack(spacing: 12) {
                Text(verbatim: Self.availableItems)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Text(verbatim: vm.string("Summary"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    /// ComboBox ItemsSource=NamingPresets, SelectedItem=SelectedNamingPreset(IsSeparator 항목은 구분선이라 고를 수 없다)
    private var presetPicker: some View {
        let presets = engine.store.items(presetsId).compactMap { engine.store.object($0.refId) }

        return Picker("", selection: engine.selectedItem(vm, "SelectedNamingPreset")) {
            ForEach(presets) { preset in
                if preset["IsSeparator"]?.bool == true {
                    Divider()
                } else {
                    Text(verbatim: preset.string("Name")).tag(Int?.some(preset.id))
                }
            }
        }
        .labelsHidden()
    }

    /// txtFormat: FormatText(IsReadOnly = IsFormatReadOnly — 커스텀 프리셋일 때만 직접 입력)
    @ViewBuilder
    private var formatField: some View {
        if vm["IsFormatReadOnly"]?.bool == true {
            SwitchReadOnlyField(text: vm.string("FormatText"))
                .help(Self.formatHelp)
        } else {
            TextField("", text: engine.string(vm, "FormatText"))
                .textFieldStyle(.roundedBorder)
                .help(Self.formatHelp)
        }
    }

    // MARK: 단추

    private func buttons(locked: Bool) -> some View {
        HStack(spacing: 6) {
            // IsEnabled = !IsLocked
            Group {
                Button { addFiles() } label: { IconLabel(title: "파일 추가", icon: "AddFile.png") }
                Button { addFolder() } label: { IconLabel(title: "폴더 추가", icon: "AddFolder.png") }
                Button { remove(selection) } label: { IconLabel(title: "선택 삭제", icon: "Delete.png") }
                Button { engine.invoke(vm, "ClearItems") } label: { IconLabel(title: "전체 삭제", icon: "Clear.png") }
            }
            .disabled(locked)

            Spacer()

            Button { engine.run(vm, "RunCommand") } label: { IconLabel(title: "시작", icon: "Run.png") }
                .buttonStyle(.borderedProminent)
                .disabled(locked || !engine.canRun(vm, "RunCommand"))
            Button { engine.run(vm, "CancelCommand") } label: { IconLabel(title: "취소", icon: "Cancel.png") }
                .disabled(!locked || !engine.canRun(vm, "CancelCommand"))
        }
    }

    // MARK: 동작

    /// LvFiles_Drop: AddPathsAsync(Common.Utils.ExpandPaths(paths)) / BtnAddFiles_Click: AddPathsAsync(FileNames)
    private func addPaths(_ paths: [String], expand: Bool) {
        guard !paths.isEmpty else { return }
        Task {
            let arg = expand ? await SwitchBridge.expandPaths(engine, paths) : .strings(paths)
            await engine.call(vm.id, "AddPathsAsync", [arg])
        }
    }

    private func addFiles() {
        // Filter = "Switch 파일 (*.nsp;*.xci;*.nsz;*.xcz)|…|모든 파일|*.*"
        addPaths(SwitchPanels.openFiles(title: "이름을 변경할 파일 선택", extensions: SwitchPanels.switchExtensions, multiple: true), expand: false)
    }

    private func addFolder() {
        if let folder = SwitchPanels.openFolder(title: "추가할 폴더를 선택하세요") {
            addPaths([folder], expand: true)
        }
    }

    /// LvFiles_KeyUp(Delete) / BtnRemove_Click: ViewModel.RemoveItems(selected)
    private func remove(_ ids: Set<Int>) {
        guard !ids.isEmpty else { return }
        engine.invoke(vm, "RemoveItems", [EngineClient.refs(ids)])
        selection.subtract(ids)
    }
}

/// 파일명 비교 열: 아이콘 + 현재 이름(OldName, 툴팁 FilePath) / 변경 이름(NewName)
private struct SwitchRenameNameCell: View {
    let item: RemoteObject

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(value: item["Icon"], size: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.string("OldName"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(item.string("FilePath"))
                Text(verbatim: item.string("NewName"))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(item.string("NewName"))
            }
        }
        .padding(.vertical, 2)
    }
}
