// upstream: RomForge/Controls/3DS/MainTab.xaml(.cs)
// ViewModel: _3DSMainViewModel (MainViewModel.Main3DsVM)
import SwiftUI

/// 3DS 탭: 하위 탭(리팩 / 설치 / 포맷 변환 / 복호화) + 로그.
/// 로그는 upstream MainWindow처럼 Main3DsVM.LogEntries(선택된 하위 탭의 로그를 모아 둔 것)를 보여 준다.
struct ThreeDSScreen: View {
    @Environment(EngineClient.self) private var engine
    let vmId: Int

    /// TabControl SelectedIndex="{Binding SubTabIndex}", TabItem 순서·아이콘·문구는 upstream과 같다.
    private static let tabs = [
        SubTab(title: "리팩", icon: "Package.png", vmProp: "RepackVM"),
        SubTab(title: "설치", icon: "Gift.png", vmProp: "InstallerVM"),
        SubTab(title: "포맷 변환", icon: "Convert.png", vmProp: "ConverterVM"),
        SubTab(title: "복호화", icon: "Lock.png", vmProp: "DecryptorVM"),
    ]

    var body: some View {
        ChildVM(id: vmId) { vm in
            ToolLayout(vm: vm, lists: ["LogEntries"]) {
                ThreeDSTabs(owner: vm, tabs: Self.tabs, selectionProp: "SubTabIndex", enabled: vm["IsIdle"]?.bool ?? true) { index, childId in
                    switch index {
                    case 0: ThreeDSRepackTab(vmId: childId)
                    case 1: ThreeDSInstallMainTab(vmId: childId)
                    case 2: ThreeDSConverterTab(vmId: childId)
                    default: ThreeDSDecryptorTab(vmId: childId)
                    }
                }
            }
        }
    }
}
