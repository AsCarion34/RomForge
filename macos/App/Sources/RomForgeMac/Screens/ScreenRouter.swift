import SwiftUI

/// 탭 → 화면. 화면마다 첫 줄에 대응하는 upstream XAML을 적어 둔다(// upstream: …).
enum ScreenRouter {
    @MainActor @ViewBuilder
    static func view(for tab: AppTab, vmId: Int) -> some View {
        switch tab {
        case .patch:
            PatchScreen(vmId: vmId)
        case .compress:
            CompressView(vmId: vmId)
        case .convert:
            ConvertScreen(vmId: vmId)
        case .nswitch:
            SwitchScreen(vmId: vmId)
        case .wiiu:
            WiiUScreen(vmId: vmId)
        case .wii:
            WiiScreen(vmId: vmId)
        case .n3ds:
            ThreeDSScreen(vmId: vmId)
        case .psvita:
            PSVitaScreen(vmId: vmId)
        case .psp:
            PSPScreen(vmId: vmId)
        case .util:
            UtilScreen(vmId: vmId)
        case .settings:
            SettingsScreen(vmId: vmId)
        }
    }
}

/// 앱 전체에서 공유하는 화면 상태(탭 선택). 자동 점검(DebugAutomation)도 쓴다.
@MainActor
@Observable
final class AppState {
    var selectedTab: AppTab? = .compress
}
