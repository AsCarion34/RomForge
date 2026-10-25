// upstream: RomForge/Views/MainWindow.xaml(.cs)
// ViewModel: MainViewModel
import AppKit
import SwiftUI

/// upstream MainWindow.xaml의 탭 구성과 같게 둔다(제목·아이콘·ViewModel 속성 이름).
/// 순서가 MainViewModel.SelectedTabIndex와 같아야 한다(upstream TabControl 순서).
enum AppTab: Int, CaseIterable, Identifiable {
    case patch, compress, convert, nswitch, wiiu, wii, n3ds, psvita, psp, util, settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .patch: "패치"
        case .compress: "압축"
        case .convert: "변환"
        case .nswitch: "Switch"
        case .wiiu: "WiiU"
        case .wii: "Wii"
        case .n3ds: "3DS"
        case .psvita: "PS Vita"
        case .psp: "PSP"
        case .util: "유틸"
        case .settings: "설정"
        }
    }

    var icon: String {
        switch self {
        case .patch: "Patch.png"
        case .compress: "Compress.png"
        case .convert: "Convert.png"
        case .nswitch: "Switch.png"
        case .wiiu: "WiiU.png"
        case .wii: "Wii.png"
        case .n3ds: "3DS.png"
        case .psvita: "Vita.png"
        case .psp: "PSP.png"
        case .util: "Utility.png"
        case .settings: "Settings.png"
        }
    }

    /// MainViewModel의 속성 이름
    var viewModelProperty: String {
        switch self {
        case .patch: "PatchVM"
        case .compress: "CompressVM"
        case .convert: "UnifiedConvertVM"
        case .nswitch: "SwitchMainVM"
        case .wiiu: "WiiUMainVM"
        case .wii: "WiiMainVM"
        case .n3ds: "Main3DsVM"
        case .psvita: "PSVitaMainVM"
        case .psp: "PSPMainVM"
        case .util: "UtilMainVM"
        case .settings: "Settings"
        }
    }
}

struct ContentView: View {
    @Environment(EngineClient.self) private var engine
    @Environment(AppState.self) private var appState

    private var root: RemoteObject? { engine.store.object(engine.rootId) }

    /// 설정 > 일반의 "항상 위"(upstream: MainWindow code-behind가 Topmost에 반영)
    private var topmost: Bool {
        let settings = engine.store.object(root?.ref("Settings"))
        return engine.store.object(settings?.ref("General"))?["Topmost"]?.bool ?? false
    }

    private struct Taskbar: Equatable {
        var state: String
        var value: Double
    }

    private var taskbar: Taskbar {
        Taskbar(state: root?["TaskbarProgressState"]?.string ?? "None", value: root?["TaskbarProgressValue"]?.double ?? 0)
    }

    var body: some View {
        @Bindable var appState = appState

        if engine.isReady {
            NavigationSplitView {
                List(AppTab.allCases, selection: $appState.selectedTab) { tab in
                    Label {
                        Text(tab.title)
                    } icon: {
                        UpstreamAssets.image(tab.icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 18, height: 18)
                    }
                    .tag(tab)
                    // upstream: TabItem IsEnabled="{Binding IsIdle}" — 작업 중에는 다른 탭으로 못 간다.
                    .disabled(!(root?["IsIdle"]?.bool ?? true) && tab != appState.selectedTab)
                }
                .navigationSplitViewColumnWidth(min: 150, ideal: 170)
            } detail: {
                detail
            }
            .task(id: engine.rootId) {
                if let rootId = engine.rootId, let root = await engine.describe(rootId) {
                    // "항상 위" 설정을 따라가려고 설정 > 일반 ViewModel도 구독한다.
                    if let settings = root.ref("Settings"), let general = await engine.describe(settings)?.ref("General") {
                        await engine.describe(general)
                    }
                }
                await DebugAutomation.runTour(appState: appState, engine: engine)
            }
            .onChange(of: appState.selectedTab) { _, tab in
                // upstream MainViewModel도 선택된 탭을 알아야 한다(로그 전환, Switch 키 상태 갱신 등).
                guard let tab, let root, root["SelectedTabIndex"]?.int != tab.rawValue else { return }
                engine.int(root, "SelectedTabIndex").wrappedValue = tab.rawValue
            }
            // upstream ViewModel이 탭을 바꾸는 경우(예: "설정" 버튼 → 설정 탭)를 따라간다.
            .onChange(of: root?["SelectedTabIndex"]?.int) { _, index in
                if let index, let tab = AppTab(rawValue: index), tab != appState.selectedTab {
                    appState.selectedTab = tab
                }
            }
            .onChange(of: topmost, initial: true) { _, isTopmost in
                for window in NSApp.windows where window.isVisible {
                    window.level = isTopmost ? .floating : .normal
                }
            }
            // upstream: Window.TaskbarItemInfo(ProgressValue·ProgressState) → Dock 아이콘 진행 막대
            .onChange(of: taskbar, initial: true) { _, value in
                DockProgress.update(state: value.state, value: value.value)
            }
            .overlay(alignment: .bottom) { errorBanner }
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("엔진 시작 중…")
                if let error = engine.lastError {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detail: some View {
        let root = engine.store.object(engine.rootId)

        if let tab = appState.selectedTab, let vmId = root?.ref(tab.viewModelProperty) {
            ScreenRouter.view(for: tab, vmId: vmId)
                .navigationTitle(tab.title)
                .id(tab)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = engine.lastError {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(error).lineLimit(2).textSelection(.enabled)
                Spacer()
                Button("닫기") { engine.lastError = nil }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding()
        }
    }
}
