import AppKit
import SwiftUI

// upstream: RomForge/Controls/CompressTab.xaml(.cs), ViewModel: CompressMainViewModel
// 로직은 엔진의 upstream ViewModel이 수행한다. 이 파일은 배치와 code-behind(드롭·삭제·폴더 열기)만 맡는다.
struct CompressView: View {
    @Environment(EngineClient.self) private var engine
    let vmId: Int
    @State private var selection = Set<Int>()

    var body: some View {
        ChildVM(id: vmId) { vm in
            ToolLayout(vm: vm) {
                Table(engine.items(vm, "FileItems"), selection: $selection) {
                    TableColumn("파일명") { item in Text(item.string("FileName")).help(item.string("FilePath")) }
                    TableColumn("형식") { item in ExtensionBadge(item: item) }.width(70)
                    TableColumn("크기") { item in Text(item.string("FileSize")).monospacedDigit() }.width(90)
                    TableColumn("상태") { item in Text(item.string("Status")) }.width(80)
                    TableColumn("진행률") { item in ProgressCell(item: item) }.width(min: 100, ideal: 140)
                }
                .overlay {
                    if engine.items(vm, "FileItems").isEmpty {
                        DropHint(title: "파일을 여기로 끌어다 놓으세요",
                                 detail: "ISO · CUE · GDI · CCD · CHD · NSP · XCI · NSZ · CCI · CIA · RVZ · WBFS 등")
                    }
                }
                .remoteFileList(engine, owner: vm, list: "FileItems", selection: $selection, enabled: vm["IsUnlocked"]?.bool ?? true)
            } options: {
                OutputPathRow(vm: vm)
            }
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = true
                        panel.canChooseDirectories = true
                        if panel.runModal() == .OK { engine.invoke(vm, "AddPaths", [.strings(panel.urls.map(\.path))]) }
                    } label: {
                        Label("파일 추가", systemImage: "plus")
                    }
                    CommandButton(title: "시작", systemImage: "play.fill", vm: vm, command: "RunCommand")
                    CommandButton(title: "취소", systemImage: "stop.fill", vm: vm, command: "CancelCommand")
                }
            }
            .task(id: vm.id) { await DebugAutomation.runCompressScenario(engine: engine, vmId: vm.id) }
        }
    }
}
