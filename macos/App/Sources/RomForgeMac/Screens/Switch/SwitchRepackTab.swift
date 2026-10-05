// upstream: RomForge/Controls/Switch/RepackTab.xaml(.cs)
// ViewModel: RomForge.ViewModels.Switch.RepackMainViewModel (SwitchMainViewModel.RepackVM)
import AppKit
import SwiftUI

/// 리팩 탭: [파일 | 설정] 하위 탭, 작업 폴더, 언팩 / 리팩 / 언팩 + 리팩 (Full), 진행 상황.
/// code-behind의 SyncAll·SyncContext·Btn*_Click을 같은 순서로 옮겼다. 빌드는 ViewModel.StartAsync가 한다.
struct SwitchRepackTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    var body: some View {
        let state = SwitchStore.repack(vm.id)
        let idle = vm["IsIdle"]?.bool ?? true

        ToolLayout(vm: vm, lists: ["LogEntries"]) {
            VStack(spacing: 0) {
                Picker("", selection: Binding(get: { state.innerTab }, set: { state.innerTab = $0 })) {
                    Text("파일").tag(0)
                    Text("설정").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.top, 8)
                .disabled(!idle)

                if state.innerTab == 0 {
                    SwitchTitleList(list: state.files, enabled: idle) { syncAll(state) }
                } else {
                    SwitchLanguagePanel(state: state.language)
                        .disabled(!idle)
                }
            }
        } options: {
            controls(state, idle: idle)
        }
        .task(id: vm.id) {
            // RepackTab_Loaded: FileListChanged 구독 + SyncAll
            await state.files.prepare(engine, importer: true)
            syncAll(state)
        }
    }

    private func controls(_ state: SwitchRepackState, idle: Bool) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                TextField("작업 폴더를 선택하세요", text: engine.string(vm, "OutputPath"))
                    .textFieldStyle(.roundedBorder)
                ToolIconButton(icon: "AddFolder.png") { engine.run(vm, "BrowseOutputCommand") }
            }
            .disabled(!idle)

            // 열 너비 * : * : 2*
            HStack(spacing: 5) {
                HStack(spacing: 5) {
                    RunCancelButton(title: "언팩", icon: "Unpack.png",
                                     isRunning: vm["IsUnpackRunning"]?.bool ?? false,
                                     enabled: vm["UnpackEnabled"]?.bool ?? true) { start(state, "UnpackOnly") }
                    RunCancelButton(title: "리팩", icon: "Repack.png",
                                     isRunning: vm["IsRebuildRunning"]?.bool ?? false,
                                     enabled: vm["RebuildEnabled"]?.bool ?? true) { start(state, "RebuildOnly") }
                }
                RunCancelButton(title: "언팩 + 리팩 (Full)", icon: "Run.png",
                                 isRunning: vm["IsFullRunning"]?.bool ?? false,
                                 enabled: vm["StartEnabled"]?.bool ?? true) { start(state, "FullProcess") }
            }

            if vm["IsLocked"]?.bool == true {
                SwitchProgressBlock(vm: vm, details: false)
            }
        }
    }

    private var unpackedDir: String {
        (vm.string("OutputPath") as NSString).appendingPathComponent("unpacked")
    }

    /// SyncAll: 300ms 뒤 언어 탭을 다시 읽고 Context를 갱신한다(앞선 요청은 취소).
    private func syncAll(_ state: SwitchRepackState) {
        state.syncTask?.cancel()
        state.syncTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }

            let files = await state.files.refreshedItems(engine)
            await state.language.update(engine, files: files, unpackedDir: unpackedDir)
            await syncContext(state)
        }
    }

    /// SyncContext: ViewModel.Context = new BuildContext(GameFiles, CurrentMetadata, ForcedLanguage, TargetIdOffset, OverrideTitleId)
    @discardableResult
    private func syncContext(_ state: SwitchRepackState) async -> Bool {
        guard let listId = state.files.listId else { return false }
        let language = state.language

        let args: [JSONValue] = [
            EngineClient.ref(listId),
            language.metadataId.map { EngineClient.ref($0) } ?? .null,
            .string(language.forcedLanguage),
            language.targetIdOffset,
            language.overrideTitleIdArgument,
        ]

        guard let context = await engine.create("RomForge.ViewModels.Switch.RepackMainViewModel+BuildContext", args) else { return false }
        await engine.set(vm.id, "Context", EngineClient.ref(context))
        return true
    }

    /// BtnUnpack_Click / BtnRebuild_Click / BtnStart_Click
    private func start(_ state: SwitchRepackState, _ mode: String) {
        Task {
            if vm["IsLocked"]?.bool == true {
                await engine.call(vm.id, "Cancel")
                return
            }

            var files = await state.files.refreshedItems(engine)

            // RecalcIfNeededAsync(언팩·Full만)
            if mode != "RebuildOnly", files.contains(where: { $0["IsKeyMissing"]?.bool == true }) {
                await SwitchBridge.recalcKeyMissing(engine, files)
                files = await state.files.refreshedItems(engine)
                await state.language.update(engine, files: files, unpackedDir: nil)
            }

            if mode == "FullProcess" {
                await state.language.syncMetadataFromUI(engine)
            }

            guard await syncContext(state) else { return }
            await engine.call(vm.id, "StartAsync", [.string(mode)])
        }
    }
}
