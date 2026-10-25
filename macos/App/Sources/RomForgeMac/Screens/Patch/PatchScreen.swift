// upstream: RomForge/Controls/Patch/MainTab.xaml(.cs)
// ViewModel: PatchMainViewModel
import SwiftUI

/// 패치 탭: 하위 탭 [일반 | 아케이드 | PC98] + 아래쪽 [초기화 · 해시 계산 | 시작 · 취소].
/// (upstream이 PS Vita 하위 탭을 PS Vita 메인 탭의 리팩으로 옮겼다 → Screens/PSVita/PSVitaRepackTab.swift)
/// upstream의 RunCommand·CancelCommand·ClearCommand·CalculateHashCommand는 SubTabIndex로 고른 하위 ViewModel(SelectedTool)에
/// 적용되므로 하위 탭 선택을 SubTabIndex에 그대로 맞춘다.
struct PatchScreen: View {
    @Environment(EngineClient.self) private var engine
    let vmId: Int

    /// upstream TabItem 순서와 머리글 아이콘. 머리글은 공용 SubTabsView처럼 분할 컨트롤에 글자만 그린다.
    private static let tabs = [
        SubTab(title: "일반", icon: "Patch.png", vmProp: "NormalVM"),
        SubTab(title: "아케이드", icon: "Arcade.png", vmProp: "ArcadeVM"),
        SubTab(title: "PC98", icon: "PC98.png", vmProp: "Pc98VM"),
    ]

    var body: some View {
        ChildVM(id: vmId) { vm in
            let locked = vm["IsLocked"]?.bool ?? false

            ToolLayout(vm: vm, lists: ["LogEntries"]) {
                VStack(spacing: 0) {
                    tabPicker(vm)
                    Divider()
                    tabContent(vm)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } options: {
                // IsEnabled="{Binding PatchVM.IsLocked, Converter=InverseBool}" + Command
                HStack(spacing: 6) {
                    CommandIconButton(title: "초기화", icon: "Clear.png", vm: vm, command: "ClearCommand", enabled: !locked)
                    CommandIconButton(title: "해시 계산", icon: "Hash.png", vm: vm, command: "CalculateHashCommand", enabled: !locked)

                    Spacer()

                    CommandIconButton(title: "시작", icon: "Run.png", vm: vm, command: "RunCommand", enabled: !locked, prominent: true)
                    CommandIconButton(title: "취소", icon: "Cancel.png", vm: vm, command: "CancelCommand", enabled: locked)
                }
            }
        }
    }

    /// upstream TabControl SelectedIndex="{Binding PatchVM.SubTabIndex}", TabItem IsEnabled="{Binding IsIdle}"(MainViewModel).
    /// 공용 SubTabsView는 탭만 비활성화할 수 없어(작업 중 탭을 바꾸면 취소가 다른 하위 ViewModel로 간다) 여기서 직접 그린다.
    private func tabPicker(_ vm: RemoteObject) -> some View {
        Picker("", selection: engine.int(vm, "SubTabIndex")) {
            ForEach(Array(Self.tabs.enumerated()), id: \.offset) { index, tab in
                Text(tab.title).tag(index)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(!PatchUI.rootIsIdle(engine))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func tabContent(_ vm: RemoteObject) -> some View {
        let index = vm["SubTabIndex"]?.int ?? 0
        let childId = Self.tabs.indices.contains(index) ? vm.ref(Self.tabs[index].vmProp) : nil

        Group {
            switch index {
            case 1: PatchArcadeTab(vmId: childId)
            case 2: PatchPc98Tab(vmId: childId)
            default: PatchNormalTab(vmId: childId)
            }
        }
        .id(index)
    }
}
