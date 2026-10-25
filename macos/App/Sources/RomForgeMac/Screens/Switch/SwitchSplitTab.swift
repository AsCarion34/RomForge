// upstream: RomForge/Controls/Switch/SplitTab.xaml(.cs)
// ViewModel: RomForge.ViewModels.Switch.SplitMainViewModel (SwitchMainViewModel.SplitVM)
import AppKit
import SwiftUI

/// 분리 탭: 파일 목록(SplitFileListControl), 출력 포맷, 출력 폴더, 시작 / 취소, 진행 상황.
struct SwitchSplitTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    var body: some View {
        let idle = vm["IsIdle"]?.bool ?? true

        ToolLayout(vm: vm, lists: ["Rows", "LogEntries"]) {
            SwitchSplitFileList(vm: vm)
                .disabled(!idle)
        } options: {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Text("출력 포맷:").fontWeight(.semibold)
                        EnumPicker(vm: vm, prop: "OutputFormat", style: .radio)
                            .fixedSize()
                    }
                    .disabled(!idle)

                    Spacer(minLength: 0)

                    ToolIconButton(icon: "Help.png", help: "도움말") {
                        FilePanels.openURL("https://sinjunyoung.github.io/RomForge/switch-merge/")
                    }
                    .disabled(!idle)
                }

                SwitchOutputFolderRow(vm: vm)
                    .disabled(!idle)

                // DefaultText="시작", CancelText=Res.Button_Cancel, IsRunning = IsLocked
                RunCancelButton(title: "시작", icon: "Run.png", isRunning: vm["IsLocked"]?.bool ?? false) { start() }

                ToolProgressBar(vm: vm)
            }
        }
    }

    /// BtnSplitStart_Click
    private func start() {
        Task {
            if vm["IsLocked"]?.bool == true {
                await engine.call(vm.id, "Cancel")
                return
            }

            if await engine.call(vm.id, "get_HasFiles")?.bool != true {
                await SwitchBridge.logError(engine, vm.id, resource: "Main_Err_NoFiles")
                return
            }

            // KeySetProvider.Instance.KeySet == null
            if await SwitchBridge.keySet(engine) == nil {
                await SwitchBridge.logError(engine, vm.id, resource: "Main_Err_NoKeys")
                return
            }

            await engine.call(vm.id, "SplitAsync")
        }
    }
}
