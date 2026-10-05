// upstream: RomForge/Controls/Settings/MainTab.xaml(.cs)
// ViewModel: SettingsMainViewModel (MainViewModel.Settings)
import SwiftUI

/// 설정 탭: 일반 / 패치 / 압축 / PS. 선택은 SettingsMainViewModel.SubTabIndex(TwoWay)에 맞춘다
/// (MainViewModel이 PS 패킹·Switch 압축의 "설정" 버튼으로 이 값을 바꾼다).
struct SettingsScreen: View {
    let vmId: Int

    private var tabs: [SubTab] {
        [
            SubTab(title: "일반", icon: "Settings.png", vmProp: "General"),
            SubTab(title: "패치", icon: "Patch.png", vmProp: "Patch"),
            SubTab(title: "압축", icon: "Compress.png", vmProp: "Compress"),
            SubTab(title: "PS", icon: "PS1.png", vmProp: "PS1"),
        ]
    }

    var body: some View {
        ChildVM(id: vmId) { vm in
            SubTabsView(owner: vm, tabs: tabs, selectionProp: "SubTabIndex") { index, childId in
                ChildVM(id: childId) { child in
                    switch index {
                    case 0: SettingsGeneralTab(vm: child)
                    case 1: SettingsPatchTab(vm: child)
                    case 2: SettingsCompressTab(vm: child)
                    default: SettingsPSTab(vm: child)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }
}
