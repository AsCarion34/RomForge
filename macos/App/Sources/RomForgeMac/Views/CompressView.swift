// upstream: RomForge/Controls/CompressTab.xaml(.cs)
// ViewModel: CompressMainViewModel
import SwiftUI

/// 압축 탭: 파일 목록(번호·파일명·변환·용량·진행률) + 출력 폴더 변경 + 파일/폴더 추가 · 선택/전체 삭제 · 시작 · 취소.
/// 로직은 엔진의 upstream ViewModel이 수행한다. 이 파일은 배치와 code-behind 동작만 옮긴다.
/// upstream 탭에는 표준 진행 줄(progressArea)이 없다(항목별 진행률만 있다). 그래서 ToolProgressBar를 두지 않는다.
/// 생략한 code-behind: ScrollToItemRequested(압축 중인 항목으로 스크롤).
struct CompressView: View {
    @Environment(EngineClient.self) private var engine
    let vmId: Int

    @State private var selection = Set<Int>()
    /// GridViewColumnHeader_Click(ListViewColumnSorter): 머리글을 누르면 그 열(Tag) 기준으로 화면에서만 정렬
    @State private var sortOrder: [ColumnSort] = []

    var body: some View {
        ChildVM(id: vmId) { vm in
            let locked = vm["IsLocked"]?.bool ?? false
            let rows = ColumnSort.sorted(engine.items(vm, "FileItems"), by: sortOrder)

            ToolLayout(vm: vm) {
                fileTable(vm, rows: rows, locked: locked)
            } options: {
                VStack(spacing: 8) {
                    outputRow(vm, locked: locked)
                    buttonBar(vm, locked: locked)
                }
            }
            // 개발·CI용 자동 점검(환경 변수가 있을 때만 동작)
            .task(id: vm.id) { await DebugAutomation.runCompressScenario(engine: engine, vmId: vm.id) }
        }
    }

    /// 아래쪽 버튼 줄(모두 IsEnabled="{Binding CompressVM.IsLocked, Converter=InverseBool}", 취소만 IsLocked)
    private func buttonBar(_ vm: RemoteObject, locked: Bool) -> some View {
        HStack(spacing: 6) {
            IconButton(title: "파일 추가", icon: "AddFile.png", enabled: !locked) { addFiles(vm) }
            IconButton(title: "폴더 추가", icon: "AddFolder.png", enabled: !locked) { addFolder(vm) }
            IconButton(title: "선택 삭제", icon: "Delete.png", enabled: !locked) { remove(vm, selection) }
            IconButton(title: "전체 삭제", icon: "Clear.png", enabled: !locked) { clear(vm) }

            Spacer()

            CommandIconButton(title: "시작", icon: "Run.png", vm: vm, command: "RunCommand", enabled: !locked, prominent: true)
            CommandIconButton(title: "취소", icon: "Cancel.png", vm: vm, command: "CancelCommand", enabled: locked)
        }
    }

    // MARK: - 파일 목록

    private func fileTable(_ vm: RemoteObject, rows: [RemoteObject], locked: Bool) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            // upstream 머리글은 글자 없이 List.png 아이콘만 있다.
            TableColumn("", sortUsing: ColumnSort("No", natural: true)) { item in
                Text(item.string("No"))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
            }
            .width(70)

            TableColumn("파일명", sortUsing: ColumnSort("FileName", natural: true)) { item in
                Text(item.string("FileName"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(item.string("FilePath"))
            }
            .width(min: 120, ideal: 330)

            // 배지 글자는 ExtensionLabel("iso→chd"처럼 자동으로 고른 결과 형식까지), 정렬은 Tag="Extension"
            TableColumn("변환", sortUsing: ColumnSort("Extension", natural: true)) { item in
                ExtensionBadge(item: item, textProp: "ExtensionLabel")
                    .frame(maxWidth: .infinity)
            }
            .width(90)

            TableColumn("용량", sortUsing: ColumnSort("FileSizeBytes", natural: true)) { item in
                Text(item.string("FileSize"))
                    .monospacedDigit()
            }
            .width(90)

            TableColumn("진행률", sortUsing: ColumnSort("Progress", natural: true)) { item in
                HStack(spacing: 6) {
                    ProgressCell(item: item)
                    Text(String(item["Progress"]?.int ?? 0) + "%")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }
            .width(min: 100, ideal: 140)
        }
        .disabled(locked)
        .overlay {
            if vm.isVisible("HintVisibility") {
                CompressHint()
            }
        }
        // LvFiles_DragOver · LvFiles_Drop
        .dropDestination(for: URL.self) { urls, _ in
            guard !locked, !urls.isEmpty else { return false }
            engine.invoke(vm, "AddPaths", [.strings(urls.map(\.path))])
            return true
        }
        // LvFiles_KeyUp(Delete)
        .onDeleteCommand {
            if !locked { remove(vm, selection) }
        }
        // ListView.ContextMenu. LvFiles_ContextMenuOpening: 선택이 없으면 열지 않는다.
        .contextMenu(forSelectionType: Int.self) { ids in
            if !ids.isEmpty && !locked {
                Button {
                    openFolder(ids, rows: rows)
                } label: {
                    MenuLabel(title: "폴더 열기", icon: "AddFolder.png")
                }
                Divider()
                Button {
                    remove(vm, ids)
                } label: {
                    MenuLabel(title: "선택 삭제", icon: "Delete.png")
                }
                Button {
                    clear(vm)
                } label: {
                    MenuLabel(title: "전체 삭제", icon: "Clear.png")
                }
            }
        }
    }

    // MARK: - 출력 폴더

    /// [출력 폴더 변경 스위치] [OutputPath 입력(스위치가 켜졌을 때)] [찾아보기(스위치가 켜졌을 때)], 작업 중에는 전체 비활성
    private func outputRow(_ vm: RemoteObject, locked: Bool) -> some View {
        let custom = vm["UseCustomOutputPath"]?.bool ?? false

        return HStack(spacing: 8) {
            Toggle(isOn: engine.bool(vm, "UseCustomOutputPath")) {
                Text("출력 폴더 변경").bold()
            }
            .toggleStyle(LeftSlideToggleStyle())

            TextField("", text: engine.string(vm, "OutputPath"))
                .textFieldStyle(.roundedBorder)
                .disabled(!custom)
                // TxtOutputPath_PreviewDragOver · TxtOutputPath_Drop(입력란이 켜졌을 때만, 첫 항목이 폴더일 때만)
                .folderDrop(engine, vm, "OutputPath", enabled: custom && !locked)

            ToolIconButton(icon: "AddFolder.png", enabled: custom && engine.canRun(vm, "BrowseOutputCommand")) {
                engine.run(vm, "BrowseOutputCommand")
            }
        }
        .disabled(locked)
    }

    // MARK: - code-behind 동작

    /// BtnAddFiles_Click. upstream 필터(CompressMainViewModel.GetFileDialogFilter())는 "지원 파일|…|모든 파일|*.*"라
    /// UiHostHandler와 같이 형식을 제한하지 않는다(지원하지 않는 확장자는 AddPaths가 거른다).
    private func addFiles(_ vm: RemoteObject) {
        let paths = FilePanels.openFiles(multiple: true)
        if !paths.isEmpty {
            engine.invoke(vm, "AddPaths", [.strings(paths)])
        }
    }

    /// BtnAddFolder_Click: VistaFolderBrowserDialog("추가할 폴더를 선택하세요")
    private func addFolder(_ vm: RemoteObject) {
        if let folder = FilePanels.openFolder(title: "추가할 폴더를 선택하세요") {
            engine.invoke(vm, "AddPaths", [.strings([folder])])
        }
    }

    /// BtnRemove_Click · Delete 키 → RemoveItems(선택 항목)
    private func remove(_ vm: RemoteObject, _ ids: Set<Int>) {
        engine.invoke(vm, "RemoveItems", [EngineClient.refs(ids)])
        selection.subtract(ids)
    }

    /// BtnClear_Click → ClearItems()
    private func clear(_ vm: RemoteObject) {
        engine.invoke(vm, "ClearItems")
        selection.removeAll()
    }

    /// MenuItem_OpenFolder_Click: 첫 선택 항목이 있는 폴더를 연다(OpenFolder: 폴더가 있을 때만).
    private func openFolder(_ ids: Set<Int>, rows: [RemoteObject]) {
        guard let path = rows.first(where: { ids.contains($0.id) })?.string("FilePath") else { return }
        FilePanels.showContainingFolder(path)
    }
}

// MARK: - 빈 목록 안내(HintVisibility)

/// 안내 표의 한 줄: [아이콘] [이름] [: 원본 ➔ 결과 | …]. XAML의 Run 순서와 종류를 그대로 옮긴다.
private struct CompressHintLine: Identifiable {
    enum Run {
        case plain(String)   // #CCCCCC
        case strong(String)  // #FFFFFF Bold
        case separator       // "  |  " #555555
        case compress        // " ➔ " #FF9800
        case decompress      // " ➔ " #00BCD4
    }

    let icon: String
    let name: String
    let runs: [Run]
    var id: String { name }

    var text: Text {
        runs.reduce(Text(verbatim: "")) { result, run in
            switch run {
            case .plain(let s): result + Text(verbatim: s).foregroundStyle(.secondary)
            case .strong(let s): result + Text(verbatim: s).bold()
            case .separator: result + Text(verbatim: "  |  ").foregroundStyle(.tertiary)
            case .compress: result + Text(verbatim: " ➔ ").bold().foregroundStyle(.orange)
            case .decompress: result + Text(verbatim: " ➔ ").bold().foregroundStyle(.cyan)
            }
        }
    }
}

private struct CompressHint: View {
    private static let lines: [CompressHintLine] = [
        CompressHintLine(icon: "Mame.png", name: "CHDMAN", runs: [
            .plain(": ISO(표준), CUE+BIN, GDI+BIN+RAW, CCD+IMG+SUB"), .compress, .strong("CHD"), .separator,
            .strong("CHD"), .decompress, .plain("ISO, CUE+BIN, GDI+BIN+RAW"),
        ]),
        CompressHintLine(icon: "Switch.png", name: "Switch", runs: [
            .plain(": NSP, XCI"), .compress, .strong("NSZ, XCZ"), .separator,
            .strong("NSZ, XCZ"), .decompress, .plain("NSP, XCI"),
        ]),
        CompressHintLine(icon: "Azahar.png", name: "Azahar", runs: [
            .plain(": 3DS(CCI와 같은 포맷), CCI, CIA"), .compress, .strong("ZCCI"), .separator,
            .strong("ZCCI"), .decompress, .plain("CCI"),
        ]),
        CompressHintLine(icon: "Dolphin.png", name: "Dolphin", runs: [
            .plain(": ISO(GC/Wii), GCM, WBFS, WIA, GCZ"), .compress, .strong("RVZ"), .separator,
            .strong("RVZ"), .decompress, .plain("ISO(GC/Wii)"),
        ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            UpstreamIcon(name: "Info.png", size: 28)
                .padding(.bottom, 8)
            Text("파일 또는 폴더를 여기에 드래그&드롭하세요")
                .font(.headline)
            Text("하기 기준에 따라 포맷이 자동 선택되고 압축 또는 해제됩니다")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 4) {
                ForEach(Self.lines) { line in
                    GridRow {
                        UpstreamIcon(name: line.icon, size: 16)
                            .padding(.trailing, 6)
                        Text(line.name)
                            .bold()
                            .padding(.trailing, 8)
                        line.text
                    }
                }
            }
            .font(.caption)
            .padding(.top, 15)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
