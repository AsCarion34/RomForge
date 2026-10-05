// upstream: RomForge/Controls/Switch/MergeTab.xaml(.cs)
// ViewModel: RomForge.ViewModels.Switch.MergeMainViewModel (SwitchMainViewModel.MergeVM)
import AppKit
import SwiftUI

/// 병합 탭: 파일 목록(FileManagerControl), 출력 포맷, 출력 폴더, 병합 시작 / 분리 시작.
struct SwitchMergeTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    var body: some View {
        let list = SwitchStore.fileManager(vm.id)
        let idle = vm["IsIdle"]?.bool ?? true

        ToolLayout(vm: vm, lists: ["LogEntries"]) {
            // fileMgr.FileListChanged += () => SwitchGameFileListOrganizer.Reorganize(fileMgr.GameFiles)
            SwitchFileManager(list: list, enabled: idle) {
                if let listId = list.listId {
                    await engine.callStatic("RomForge.Controls.Switch.SwitchGameFileListOrganizer", "Reorganize", [EngineClient.ref(listId)])
                }
            }
        } options: {
            VStack(spacing: 8) {
                formatRow(idle: idle)
                outputRow(idle: idle)

                HStack(spacing: 5) {
                    // Res.Button_MergeStart / Res.Button_Cancel
                    RunCancelButton(title: "병합 시작", icon: "Merge.png",
                                     isRunning: vm["IsMergeRunning"]?.bool ?? false,
                                     enabled: vm["MergeEnabled"]?.bool ?? true) { start(list, merge: true) }
                    // Res.Button_SplitStart / Res.Button_Cancel
                    RunCancelButton(title: "분리 시작", icon: "Split.png",
                                     isRunning: vm["IsSplitRunning"]?.bool ?? false,
                                     enabled: vm["SplitEnabled"]?.bool ?? true) { start(list, merge: false) }
                }

                if vm["IsLocked"]?.bool == true {
                    SwitchProgressBlock(vm: vm)
                }
            }
        }
    }

    private func formatRow(idle: Bool) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("출력 포맷:").fontWeight(.semibold)
                EnumPicker(vm: vm, prop: "OutputFormat", labels: ["NSP": "NSP, NSZ", "XCI": "XCI, XCZ"], style: .radio)
                    .fixedSize()
                Text("※ 압축 설정에 따라 자동으로 선택 됩니다 ( 설정 화면에서 변경 가능 )")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .disabled(!idle)

            Spacer(minLength: 0)

            ToolIconButton(icon: "Settings.png", help: "압축 설정") {
                // BtnSettings_Click → ViewModel.NavigateSettings()
                engine.invoke(vm, "NavigateSettings")
            }
            ToolIconButton(icon: "Help.png", help: "도움말") {
                SwitchPanels.openURL("https://sinjunyoung.github.io/RomForge/switch-merge/")
            }
        }
    }

    private func outputRow(idle: Bool) -> some View {
        HStack(spacing: 10) {
            // Res.ToolTip_OpenWorkSpace
            ToolIconButton(icon: "WorkSpace.png", help: "출력 폴더 열기",
                             enabled: engine.canRun(vm, "OpenWorkSpaceCommand")) { engine.run(vm, "OpenWorkSpaceCommand") }
            // Res.Label_OutputPath
            Text("출력 폴더").fontWeight(.bold)
            TextField("", text: engine.string(vm, "OutputPath"))
                .textFieldStyle(.roundedBorder)
            // Res.ToolTip_BrowseOutput
            ToolIconButton(icon: "OpenFolder.png", help: "출력 폴더 선택") {
                // BtnBrowseOutput_Click: VistaFolderBrowserDialog(Res.Hint_SelectOutput)
                if let folder = SwitchPanels.openFolder(title: "출력 폴더를 선택하세요") {
                    engine.string(vm, "OutputPath").wrappedValue = folder
                }
            }
        }
        .disabled(!idle)
    }

    /// BtnMergeStart_Click / BtnSplitStart_Click
    private func start(_ list: SwitchGameFileList, merge: Bool) {
        Task {
            if vm[merge ? "IsMergeRunning" : "IsSplitRunning"]?.bool == true {
                await engine.call(vm.id, "Cancel")
                return
            }

            guard let listId = list.listId else { return }
            let files = await list.refreshedItems(engine)

            if files.isEmpty {
                await log("Main_Err_NoFiles")
                return
            }

            // FileManagerControl.KeyExists()
            if await SwitchBridge.keySet(engine) == nil {
                await log("Main_Err_NoKeys")
                return
            }

            if files.contains(where: { $0["IsKeyMissing"]?.bool == true }) {
                await SwitchBridge.recalcKeyMissing(engine, files)
            }

            await engine.call(vm.id, merge ? "MergeAsync" : "SplitAsync", [EngineClient.ref(listId)])
        }
    }

    /// ViewModel.Log(Res.X, LogLevel.Error)
    private func log(_ resourceKey: String) async {
        let message = await SwitchBridge.resource(engine, resourceKey)
        await engine.call(vm.id, "Log", [.string(message), .string("Error"), .string("")])
    }
}
