// upstream: RomForge/Controls/WiiU/MainTab.xaml(.cs)
// ViewModel: RomForge.ViewModels.WiiU.WiiUMainViewModel (MainViewModel.WiiUMainVM)
import SwiftUI

/// WiiU 탭: 리팩 · 포맷 변환
struct WiiUScreen: View {
    let vmId: Int

    private let tabs = [
        SubTab(title: "리팩", icon: "Package.png", vmProp: "RepackVM"),
        SubTab(title: "포맷 변환", icon: "Convert.png", vmProp: "ConverterVM"),
    ]

    var body: some View {
        ChildVM(id: vmId) { vm in
            // TabControl SelectedIndex = SubTabIndex, TabItem.IsEnabled = IsIdle
            SubTabsView(owner: vm, tabs: tabs, selectionProp: "SubTabIndex", enabledProp: "IsIdle") { index, childId in
                ChildVM(id: childId) { child in
                    if index == 0 {
                        WiiURepackTab(vm: child)
                    } else {
                        WiiUConverterTab(vm: child)
                    }
                }
            }
        }
    }
}
