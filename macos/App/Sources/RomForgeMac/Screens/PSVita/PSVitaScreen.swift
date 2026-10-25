// upstream: RomForge/Controls/PSVita/MainTab.xaml(.cs)
// ViewModel: RomForge.ViewModels.PSVita.PSVitaMainViewModel (MainViewModel.PSVitaMainVM)
import SwiftUI

/// PS Vita 탭: 하위 탭 리팩 / 포맷 변환.
/// TabControl SelectedIndex="{Binding SubTabIndex, Mode=TwoWay}"(upstream이 선택된 하위 탭의 로그를 모은다), TabItem IsEnabled="{Binding IsIdle}".
struct PSVitaScreen: View {
    let vmId: Int

    private let tabs = [
        SubTab(title: "리팩", icon: "Package.png", vmProp: "RepackVM"),
        SubTab(title: "포맷 변환", icon: "Convert.png", vmProp: "ConverterVM"),
    ]

    var body: some View {
        ChildVM(id: vmId) { vm in
            SubTabsView(owner: vm, tabs: tabs, selectionProp: "SubTabIndex", enabledProp: "IsIdle") { index, childId in
                ChildVM(id: childId) { child in
                    if index == 0 {
                        PSVitaRepackTab(vm: child)
                    } else {
                        PSVitaConverterTab(vm: child)
                    }
                }
            }
        }
    }
}
