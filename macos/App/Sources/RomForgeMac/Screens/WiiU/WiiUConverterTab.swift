// upstream: RomForge/Controls/WiiU/ConverterTab.xaml(.cs)
// ViewModel: RomForge.ViewModels.WiiU.ConverterMainViewModel (WiiUMainViewModel.ConverterVM), 항목 RomForge.Core.Models.WiiU.FileItem
import SwiftUI

/// WiiU 포맷 변환 탭: WUP · Loadiine · WUD/WUX · WUA 상호 변환.
struct WiiUConverterTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    @State private var selection = Set<Int>()

    var body: some View {
        let items = engine.items(vm, "FileItems")
        let converting = vm["IsConverting"]?.bool ?? false

        ToolLayout(vm: vm, lists: ["FileItems", "LogEntries"]) {
            table(items)
                // code-behind: Drop → AddPaths(paths), Delete·선택 삭제 → RemoveItems, 전체 삭제 → ClearItems, 폴더 열기
                .remoteFileList(engine, owner: vm, list: "FileItems", selection: $selection,
                                dropMethod: "AddPaths", removeMethod: "RemoveItems", clearMethod: "ClearItems", enabled: !converting)
                .disabled(converting)
                .padding(.horizontal, 5)
        } options: {
            VStack(spacing: 8) {
                // TextBox(OutputPath, AllowDrop) + 찾아보기(BrowseOutputCommand), IsEnabled = !IsConverting
                FolderPathRow(vm: vm, placeholder: "출력 폴더를 드래그하거나 선택하세요", dropEnabled: !converting)
                    .disabled(converting)

                HStack(spacing: 6) {
                    // IsEnabled = !IsConverting
                    Group {
                        Button { addFiles() } label: { IconLabel(title: "파일 추가", icon: "AddFile.png") }
                        Button { addFolder() } label: { IconLabel(title: "폴더 추가", icon: "AddFolder.png") }
                        Button { remove(selection) } label: { IconLabel(title: "선택 삭제", icon: "Delete.png") }
                        Button { engine.invoke(vm, "ClearItems") } label: { IconLabel(title: "전체 삭제", icon: "Clear.png") }
                    }
                    .disabled(converting)

                    Spacer()

                    Button { engine.run(vm, "RunCommand") } label: { IconLabel(title: "시작", icon: "Run.png") }
                        .buttonStyle(.borderedProminent)
                        .disabled(converting || !engine.canRun(vm, "RunCommand"))
                    Button { engine.run(vm, "CancelCommand") } label: { IconLabel(title: "취소", icon: "Cancel.png") }
                        .disabled(!converting || !engine.canRun(vm, "CancelCommand"))
                }
            }
        }
    }

    private func table(_ items: [RemoteObject]) -> some View {
        Table(items, selection: $selection) {
            TableColumn("") { item in
                Text(item.string("No")).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            .width(40)
            TableColumn("타이틀") { item in
                WiiUTitleCell(item: item, title: "ShortDescription", subtitle: "TitleIdVersionDisplay", tooltip: "FilePath")
                    .cellEnvironment(engine)
            }
            .width(min: 180, ideal: 260)
            TableColumn("입력") { item in
                WiiUBadge(text: item.string("Extension"), background: item["ExtensionBackground"]?.color, foreground: Color(hex: "#111111"))
            }
            .width(75)
            TableColumn("출력") { item in WiiUFormatPicker(item: item).cellEnvironment(engine) }
                .width(105)
            TableColumn("용량") { item in
                Text(item.string("FileSize")).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(90)
            TableColumn("진행률") { item in
                ZStack {
                    ProgressCell(item: item)
                    Text("\(item["Progress"]?.int ?? 0)%")
                        .font(.caption2.weight(.bold).monospacedDigit())
                }
            }
            .width(min: 100, ideal: 120)
        }
        .overlay {
            if vm.isVisible("HintVisibility") {
                hint
            }
        }
    }

    private var hint: some View {
        VStack(spacing: 6) {
            UpstreamIcon(name: "Info.png", size: 28)
            Text("WUP/Loadiine 폴더, wud/wux/wua 파일을 여기에 드래그&드롭하세요").font(.headline)
            Text("하기 기준으로 상호 변환합니다").fontWeight(.bold).foregroundStyle(.orange)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                hintRow("WUP", "(폴더)", "Loadiine 폴더, WUA")
                hintRow("Loadiine", "(폴더)", "WUP 폴더, WUA")
                hintRow("WUD/WUX", "(디스크 이미지)", "WUA, WUP 폴더, Loadiine 폴더")
                hintRow("WUA", "(Cemu 아카이브)", "WUP 폴더, Loadiine 폴더")
            }
            .font(.caption)
            .padding(.top, 10)
        }
        .multilineTextAlignment(.center)
        .padding()
        .allowsHitTesting(false)
    }

    private func hintRow(_ format: String, _ kind: String, _ targets: String) -> some View {
        GridRow {
            UpstreamIcon(name: "WiiU.png", size: 16)
            Text(format).fontWeight(.bold)
            HStack(spacing: 4) {
                Text(kind).foregroundStyle(.secondary)
                Text("➔").fontWeight(.bold).foregroundStyle(.teal)
                Text(targets).fontWeight(.bold)
            }
        }
    }

    // MARK: 동작

    private func addPaths(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        Task { await engine.call(vm.id, "AddPaths", [.strings(paths)]) }
    }

    /// BtnAddFiles_Click: Filter = "WiiU 파일 (*.wud;*.wux;*.wua)|…|모든 파일 (*.*)|*.*"
    private func addFiles() {
        addPaths(FilePanels.openFiles(title: "변환할 파일 선택", extensions: ["wud", "wux", "wua"], multiple: true))
    }

    /// BtnAddFolder_Click
    private func addFolder() {
        if let folder = FilePanels.openFolder(title: "추가할 폴더를 선택하세요 (WUP 또는 Loadiine 폴더)") {
            addPaths([folder])
        }
    }

    /// LvFiles_KeyUp(Delete) / BtnRemove_Click: ViewModel.RemoveItems(selected)
    private func remove(_ ids: Set<Int>) {
        guard !ids.isEmpty else { return }
        engine.invoke(vm, "RemoveItems", [EngineClient.refs(ids)])
        selection.subtract(ids)
    }
}
