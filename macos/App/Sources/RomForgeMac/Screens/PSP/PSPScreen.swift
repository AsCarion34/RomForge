// upstream: RomForge/Controls/PSP/MainTab.xaml(.cs)
// ViewModel: PSPMainViewModel (MainViewModel.PSPMainVM)
import SwiftUI

/// PSP 탭: 하위 탭 PBP 패킹 / PBP 언팩 / 포맷 변환. 선택은 PSPMainViewModel.SubTabIndex(TwoWay)에 맞춘다.
/// 작업 중에는 하위 탭을 바꿀 수 없다(TabItem IsEnabled="{Binding IsIdle}").
struct PSPScreen: View {
    let vmId: Int

    private var tabs: [SubTab] {
        [
            SubTab(title: "PBP 패킹", icon: "Repack.png", vmProp: "PackingVM"),
            SubTab(title: "PBP 언팩", icon: "Unpack.png", vmProp: "UnPackingVM"),
            SubTab(title: "포맷 변환", icon: "Convert.png", vmProp: "ConverterVM"),
        ]
    }

    var body: some View {
        ChildVM(id: vmId) { vm in
            SubTabsView(owner: vm, tabs: tabs, selectionProp: "SubTabIndex", enabledProp: "IsIdle") { index, childId in
                ChildVM(id: childId) { child in
                    switch index {
                    case 0: PSPPackingTab(vm: child)
                    case 1: PSPUnpackingTab(vm: child)
                    default: PSPConverterTab(vm: child)
                    }
                }
            }
        }
    }
}
