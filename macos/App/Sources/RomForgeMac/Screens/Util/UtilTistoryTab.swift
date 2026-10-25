// upstream: RomForge/Controls/Util/TistoryTab.xaml(.cs)
// ViewModel: TistoryMainViewModel (UtilMainViewModel.TistoryVM)
import SwiftUI

/// 티스토리 다운로더: URL 입력·분석 / 다운로드 위치 / 첨부파일 목록 / 버튼
struct UtilTistoryTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject
    @State private var selection = Set<Int>()
    /// 목록 머리글의 "전체 선택 / 해제" 체크박스(IsChecked="True"로 시작, ViewModel에 바인딩되지 않음)
    @State private var allChecked = true
    @State private var sortOrder: [UtilColumnSort] = []

    /// IsEnabled="{Binding IsLocked, Converter=InverseBool}"
    private var isUnlocked: Bool { !(vm["IsLocked"]?.bool ?? false) }

    var body: some View {
        ToolLayout(vm: vm) {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Divider()
                fileList
            }
        } options: {
            HStack(spacing: 6) {
                // LeftSlideToggleStyle ToggleButton(왼쪽 스위치 + 굵은 문구)
                Toggle(isOn: engine.bool(vm, "AutoExtractAfterDownload")) {
                    Text("압축 자동 해제 (완료 후 원본 삭제)").fontWeight(.bold)
                }
                .toggleStyle(UtilLeftSwitchToggleStyle())
                .help("다운로드한 파일이 압축파일(zip/7z/rar)이면 자동으로 압축을 풀고 원본 압축파일을 삭제합니다")
                .disabled(!isUnlocked)
                .padding(.trailing, 14)

                IconButton(title: "선택 삭제", icon: "Delete.png", enabled: isUnlocked) {
                    UtilFileActions.remove(engine, vm, selection)
                    selection.removeAll()
                }
                IconButton(title: "전체 삭제", icon: "Clear.png", enabled: isUnlocked) {
                    UtilFileActions.clear(engine, vm)
                    selection.removeAll()
                }

                Spacer()

                CommandIconButton(title: "다운로드", icon: "Run.png", vm: vm, command: "RunCommand", enabled: isUnlocked, prominent: true)
                CommandIconButton(title: "취소", icon: "Cancel.png", vm: vm, command: "CancelCommand", enabled: !isUnlocked)
            }
        }
    }

    private var header: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                Text("티스토리 URL").fontWeight(.bold).foregroundStyle(.secondary)
                    .gridCellAnchor(.topLeading)
                TextEditor(text: engine.string(vm, "PageUrls"))
                    .frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
                    .disabled(!isUnlocked)
                    .help("티스토리 게시글 URL을 한 줄에 하나씩 입력하세요 (여러 개 입력 가능, Ctrl+Enter로 분석 실행)")
                // TxtUrl_PreviewKeyDown: Ctrl+Enter → AnalyzeCommand
                Button {
                    engine.run(vm, "AnalyzeCommand")
                } label: {
                    IconLabel(title: "분석", icon: "Search.png", size: 20)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .control)
                .disabled(!engine.canRun(vm, "AnalyzeCommand"))
            }

            GridRow {
                Text("다운로드 위치").fontWeight(.bold).foregroundStyle(.secondary)
                // Text="{Binding SaveDirectory, UpdateSourceTrigger=PropertyChanged}" + 폴더 드롭(TxtSaveDirectory_PreviewDragOver / Drop)
                TextField("", text: engine.string(vm, "SaveDirectory"))
                    .textFieldStyle(.roundedBorder)
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let folder = UtilFileActions.droppedFolder(urls) else { return false }
                        engine.invoke(vm, "ChangeSaveDirectory", [.string(folder)])
                        return true
                    }
                    .help("폴더를 이곳에 드래그하여 다운로드 위치를 변경할 수 있습니다.")
                IconButton(title: " 변경", icon: "AddFolder.png", enabled: isUnlocked) {
                    // BtnChangeFolder_Click
                    if let folder = UtilFileActions.openFolder(title: "다운로드 파일을 저장할 폴더를 선택하세요",
                                                               initialDirectory: vm.string("SaveDirectory")) {
                        engine.invoke(vm, "ChangeSaveDirectory", [.string(folder)])
                    }
                }
            }
        }
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            Table(UtilColumnSort.sorted(engine.items(vm, "FileItems"), by: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                TableColumn("No.", sortUsing: UtilColumnSort(prop: "No")) { item in
                    Text(item.string("No"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .width(min: 36, ideal: 60)

                TableColumn("파일명", sortUsing: UtilColumnSort(prop: "FileName")) { item in
                    Text(item.string("FileName"))
                        .lineLimit(1)
                        .help(item.string("Url"))
                }
                .width(min: 160, ideal: 380)

                TableColumn("용량", sortUsing: UtilColumnSort(prop: "FileSizeBytes")) { item in
                    Text(item.string("FileSize")).monospacedDigit()
                }
                .width(min: 70, ideal: 90)

                TableColumn("진행률", sortUsing: UtilColumnSort(prop: "Progress")) { item in UtilProgressCell(item: item) }
                    .width(min: 100, ideal: 140)

                TableColumn("상태", sortUsing: UtilColumnSort(prop: "Status")) { item in
                    Text(item.string("Status")).frame(maxWidth: .infinity, alignment: .center)
                }
                .width(min: 60, ideal: 90)

                // 머리글은 "전체 선택 / 해제" 체크박스뿐이다(표 아래 체크박스로 옮김).
                TableColumn("") { item in
                    Toggle("", isOn: engine.bool(item, "IsSelected"))
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .width(min: 44, ideal: 64)
            }
            .overlay {
                if vm.isVisible("HintVisibility") {
                    UtilHint(icon: "Search.png",
                             title: "티스토리 URL을 입력하고 분석 버튼을 눌러주세요",
                             detail: "첨부파일 링크를 찾아 목록에 추가합니다")
                }
            }
            // AllowDrop 없음. 폴더 열기: SavedPath가 있으면 그 폴더, 없으면 SaveDirectory
            .modifier(UtilFileListBehavior(engine: engine, vm: vm, selection: $selection, enabled: isUnlocked,
                                           acceptsDrop: false,
                                           folderOf: { item in
                                               item["SavedPath"]?.string.flatMap(UtilFileActions.directoryName)
                                                   ?? vm.string("SaveDirectory")
                                           }))

            // 표 머리글에 체크박스를 둘 수 없어 표 아래에 둔다(HeaderCheckBox_Click).
            HStack {
                Spacer()
                Toggle("전체 선택 / 해제", isOn: Binding(get: { allChecked }, set: { checkAll($0) }))
                    .help("전체 선택 / 해제")
                    .disabled(!isUnlocked)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    /// HeaderCheckBox_Click: 머리글 체크 상태를 모든 항목의 IsSelected에 넣는다.
    private func checkAll(_ isOn: Bool) {
        allChecked = isOn
        for item in engine.items(vm, "FileItems") {
            engine.bool(item, "IsSelected").wrappedValue = isOn
        }
    }
}

/// upstream LeftSlideToggleStyle: 왼쪽에 슬라이드 스위치, 오른쪽에 내용(스위치는 macOS 기본 스위치)
private struct UtilLeftSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
                .labelsHidden()
            configuration.label
        }
    }
}
