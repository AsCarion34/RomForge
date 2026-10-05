// upstream: RomForge/Controls/Util/CueTab.xaml(.cs)
// ViewModel: CueMainViewModel (UtilMainViewModel.CueVM)
import SwiftUI

/// Cue 생성: BIN 목록 → 단일 트랙 CUE 생성
struct UtilCueTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject
    @State private var selection = Set<Int>()

    /// IsEnabled="{Binding IsLocked, Converter=InverseBool}"
    private var isUnlocked: Bool { !(vm["IsLocked"]?.bool ?? false) }

    var body: some View {
        ToolLayout(vm: vm) {
            Table(engine.items(vm, "FileItems"), selection: $selection) {
                TableColumn("No.") { item in
                    Text(item.string("No"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .width(min: 40, ideal: 70)

                TableColumn("파일명") { item in
                    Text(item.string("FileName"))
                        .lineLimit(1)
                        .help(item.string("FilePath"))
                }
                .width(min: 200, ideal: 470)

                TableColumn("진행률") { item in UtilProgressCell(item: item) }
                    .width(min: 100, ideal: 140)
            }
            .overlay {
                if vm.isVisible("HintVisibility") {
                    UtilHint(title: "파일 또는 폴더를 여기에 드래그&드롭하세요",
                             detail: "단일 트랙 CUE 파일을 생성합니다, 멀티 트랙 X",
                             badges: ["BIN"])
                }
            }
            .modifier(UtilFileListBehavior(engine: engine, vm: vm, selection: $selection, enabled: isUnlocked))
        } options: {
            HStack(spacing: 6) {
                IconButton(title: "파일 추가", icon: "AddFile.png", enabled: isUnlocked) {
                    UtilFileActions.addFiles(engine, vm, filterType: "CueMainViewModel")
                }
                IconButton(title: "폴더 추가", icon: "AddFolder.png", enabled: isUnlocked) {
                    UtilFileActions.addFolder(engine, vm)
                }
                IconButton(title: "선택 삭제", icon: "Delete.png", enabled: isUnlocked) {
                    UtilFileActions.remove(engine, vm, selection)
                    selection.removeAll()
                }
                IconButton(title: "전체 삭제", icon: "Clear.png", enabled: isUnlocked) {
                    UtilFileActions.clear(engine, vm)
                    selection.removeAll()
                }

                Spacer()

                CommandIconButton(title: "시작", icon: "Run.png", vm: vm, command: "RunCommand", enabled: isUnlocked, prominent: true)
                CommandIconButton(title: "취소", icon: "Cancel.png", vm: vm, command: "CancelCommand", enabled: !isUnlocked)
            }
        }
    }
}
