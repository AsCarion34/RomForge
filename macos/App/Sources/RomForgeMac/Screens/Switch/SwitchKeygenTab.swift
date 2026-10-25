// upstream: RomForge/Controls/Switch/KeygenTab.xaml(.cs)
// ViewModel: RomForge.ViewModels.Switch.KeygenMainViewModel (SwitchMainViewModel.KeygenVM)
import SwiftUI

/// 버전 무시 탭: 파일 목록(FileManagerControl), 시작 / 취소, 진행 상황.
struct SwitchKeygenTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    var body: some View {
        let list = SwitchStore.fileManager(vm.id)
        let locked = vm["IsLocked"]?.bool ?? false

        ToolLayout(vm: vm, lists: ["LogEntries"]) {
            SwitchFileManager(list: list, enabled: vm["IsIdle"]?.bool ?? true)
        } options: {
            VStack(spacing: 8) {
                // DefaultText="시작", CancelText=Res.Button_Cancel, IsRunning = IsLocked
                RunCancelButton(title: "시작", icon: "Run.png", isRunning: locked) {
                    // BtnStartWork_Click
                    if locked {
                        engine.invoke(vm, "Cancel")
                    } else if let listId = list.listId {
                        engine.invoke(vm, "ExecuteStartWorkAsync", [EngineClient.ref(listId)])
                    }
                }

                ToolProgressBar(vm: vm)
            }
        }
    }
}
