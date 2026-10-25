// upstream: RomForge/Controls/Wii/MainTab.xaml(.cs)
// ViewModel: RomForge.ViewModels.Wii.WiiMainViewModel (MainViewModel.WiiMainVM)
import SwiftUI

/// Wii 탭: 하위 탭 [리팩]. upstream이 리팩 화면·로직을 하위 탭(RepackTab · RepackMainViewModel)으로 옮겼다 → WiiRepackTab.swift
struct WiiScreen: View {
    let vmId: Int

    private let tabs = [
        SubTab(title: "리팩", icon: "Package.png", vmProp: "RepackVM"),
    ]

    var body: some View {
        ChildVM(id: vmId) { vm in
            // TabControl SelectedIndex = SubTabIndex, TabItem.IsEnabled = IsIdle
            SubTabsView(owner: vm, tabs: tabs, selectionProp: "SubTabIndex", enabledProp: "IsIdle") { _, childId in
                ChildVM(id: childId) { child in
                    WiiRepackTab(vm: child)
                }
            }
        }
    }
}
