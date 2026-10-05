// upstream: RomForge/Controls/PS/MainTab.xaml(.cs)
// ViewModel: PS1MainViewModel (MainViewModel.PSMainVM)
import SwiftUI

/// PS 탭: 하위 탭 PBP 패킹 / PBP 언팩 / 포맷 변환. 선택은 PS1MainViewModel.SubTabIndex(TwoWay)에 맞춘다.
struct PSScreen: View {
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
            SubTabsView(owner: vm, tabs: tabs, selectionProp: "SubTabIndex") { index, childId in
                ChildVM(id: childId) { child in
                    switch index {
                    case 0: PSPackingTab(vm: child)
                    case 1: PSUnpackingTab(vm: child)
                    default: PSConverterTab(vm: child)
                    }
                }
            }
        }
    }
}
