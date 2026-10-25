// upstream: RomForge/Controls/Switch/MergeTab.xaml(.cs)
// ViewModel: RomForge.ViewModels.Switch.MergeMainViewModel (SwitchMainViewModel.MergeVM)
import AppKit
import SwiftUI

/// 병합 탭: 파일 목록(FileManagerControl), 병합 방식 · 출력 포맷, 출력 폴더, 시작 / 취소, 진행 상황.
struct SwitchMergeTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    var body: some View {
        let list = SwitchStore.fileManager(vm.id)
        let idle = vm["IsIdle"]?.bool ?? true

        ToolLayout(vm: vm, lists: ["LogEntries"]) {
            SwitchFileManager(list: list, enabled: idle)
        } options: {
            VStack(spacing: 8) {
                optionRow(idle: idle)

                SwitchOutputFolderRow(vm: vm)
                    .disabled(!idle)

                // DefaultText="시작", CancelText=Res.Button_Cancel, IsRunning = IsLocked
                RunCancelButton(title: "시작", icon: "Run.png", isRunning: vm["IsLocked"]?.bool ?? false) { start(list) }

                ToolProgressBar(vm: vm)
            }
        }
    }

    private func optionRow(idle: Bool) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("병합 방식:").fontWeight(.semibold)
                SwitchRadioButton(title: "타이틀 ID 별 그룹핑 (기존 방식)", help: "타이틀 ID별로 항목을 그룹화하여 각각 별도의 파일로 병합합니다.",
                                  isOn: vm.string("MergeMode") == "ByTitleId") {
                    engine.isChoice(vm, "MergeMode", "ByTitleId").wrappedValue = true
                }
                .fixedSize()
                SwitchRadioButton(title: "전체", help: "전체 항목을 하나의 파일로 병합합니다.",
                                  isOn: vm.string("MergeMode") == "AllInOne") {
                    engine.isChoice(vm, "MergeMode", "AllInOne").wrappedValue = true
                }
                .fixedSize()

                Divider()
                    .frame(height: 18)

                Text("출력 포맷:").fontWeight(.semibold)
                EnumPicker(vm: vm, prop: "OutputFormat", style: .radio)
                    .fixedSize()
            }
            .disabled(!idle)

            Spacer(minLength: 0)

            ToolIconButton(icon: "Help.png", help: "도움말") {
                SwitchPanels.openURL("https://sinjunyoung.github.io/RomForge/switch-merge/")
            }
            .disabled(!idle)
        }
    }

    /// BtnMergeStart_Click
    private func start(_ list: SwitchGameFileList) {
        Task {
            if vm["IsLocked"]?.bool == true {
                await engine.call(vm.id, "Cancel")
                return
            }

            guard let listId = list.listId else { return }
            let files = await list.refreshedItems(engine)

            if files.isEmpty {
                await SwitchBridge.logError(engine, vm.id, resource: "Main_Err_NoFiles")
                return
            }

            // FileManagerControl.KeyExists()
            if await SwitchBridge.keySet(engine) == nil {
                await SwitchBridge.logError(engine, vm.id, resource: "Main_Err_NoKeys")
                return
            }

            // RecalcKeyMissingAsync: fileMgr.RecalcKeyMissingFiles(() => tcs.SetResult())
            if files.contains(where: { $0["IsKeyMissing"]?.bool == true }) {
                await SwitchFileManagerImport.recalcKeyMissing(engine, list: list)
            }

            await engine.call(vm.id, "MergeAsync", [EngineClient.ref(listId)])
        }
    }
}
