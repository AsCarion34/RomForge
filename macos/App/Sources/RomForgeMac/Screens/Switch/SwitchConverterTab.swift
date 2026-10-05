// upstream: RomForge/Controls/Switch/ConverterTab.xaml(.cs)
// ViewModel: RomForge.ViewModels.Switch.ConverterMainViewModel (SwitchMainViewModel.ConverterVM), 항목 RomForge.Core.Models.Switch.ConverterFileItem
import AppKit
import SwiftUI

/// 포맷 변환 탭: NSP · NSZ · XCI · XCZ 상호 변환 목록과 실행 버튼.
struct SwitchConverterTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    @State private var selection = Set<Int>()
    @State private var sortOrder: [SwitchColumnSort] = []

    var body: some View {
        let items = engine.items(vm, "FileItems")
        let locked = vm["IsLocked"]?.bool ?? false

        ToolLayout(vm: vm, lists: ["FileItems", "LogEntries"]) {
            table(items)
                .disabled(locked)
                .padding(.horizontal, 5)
        } options: {
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
    }

    private func table(_ items: [RemoteObject]) -> some View {
        Table(SwitchColumnSort.apply(sortOrder, to: items), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("", sortUsing: SwitchColumnSort(prop: "No")) { item in
                Text(item.string("No")).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            .width(40)
            TableColumn("타이틀", sortUsing: SwitchColumnSort(prop: "TitleName")) { item in SwitchTitleCell(item: item).cellEnvironment(engine) }
                .width(min: 180, ideal: 280)
            TableColumn("종류", sortUsing: SwitchColumnSort(prop: "FileType")) { item in
                SwitchBadge(text: item.string("FileType"), background: item["TypeBackground"]?.color, foreground: item["TypeForeground"]?.color)
            }
            .width(90)
            TableColumn("입력", sortUsing: SwitchColumnSort(prop: "Extension")) { item in
                SwitchBadge(text: item.string("Extension"), background: item["ExtensionBackground"]?.color, foreground: item["ExtensionForeground"]?.color)
            }
            .width(75)
            TableColumn("출력") { item in SwitchFormatPicker(item: item).cellEnvironment(engine) }
                .width(95)
            TableColumn("버전", sortUsing: SwitchColumnSort(prop: "Version")) { item in
                Text(item.string("Version")).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            .width(80)
            TableColumn("용량", sortUsing: SwitchColumnSort(prop: "FileSize")) { item in
                Text(item.string("FileSize")).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(90)
            TableColumn("상태", sortUsing: SwitchColumnSort(prop: "Status")) { item in SwitchStatusCell(item: item) }
                .width(min: 100, ideal: 120)
        }
        .overlay {
            if vm.isVisible("HintVisibility") {
                SwitchDropHint(title: "파일 또는 폴더를 여기에 드래그하세요", detail: "하기 파일 포맷을 상호 변환합니다", icon: "drag.png")
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
        addPaths(SwitchPanels.openFiles(title: "변환할 파일 선택", extensions: SwitchPanels.switchExtensions, multiple: true), expand: false)
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

/// 상태 열: 진행 막대 + "N%" + 상태 글자(StatusColor)
struct SwitchStatusCell: View {
    let item: RemoteObject

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                ProgressCell(item: item)
                Text("\(item["Progress"]?.int ?? 0)%")
                    .font(.caption2.weight(.bold).monospacedDigit())
            }
            Text(item.string("Status"))
                .font(.caption2)
                .foregroundStyle(Color(hex: item.string("StatusColor").nonEmpty ?? "#888888"))
        }
    }
}
