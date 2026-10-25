// upstream: RomForge/Controls/Switch/MainTab.xaml(.cs)
// ViewModel: RomForge.ViewModels.Switch.SwitchMainViewModel (MainViewModel.SwitchMainVM)
import SwiftUI

/// Switch 탭: 리팩 · 병합 · 분리 · 포맷 변환 · 새턴 NSP 변환 · 버전 무시 · 파일명 변경. prod.keys가 없으면 안내로 덮는다.
struct SwitchScreen: View {
    @Environment(EngineClient.self) private var engine
    let vmId: Int

    /// SwitchMainViewModel.KeysAvailable / KeysMissingMessage(정적 속성이라 정적 getter로 읽는다)
    @State private var keysAvailable: Bool?
    @State private var keysMissingMessage = ""

    private static let viewModel = "RomForge.ViewModels.Switch.SwitchMainViewModel"

    private let tabs = [
        SubTab(title: "리팩", icon: "Package.png", vmProp: "RepackVM"),
        SubTab(title: "병합", icon: "Merge.png", vmProp: "MergeVM"),
        SubTab(title: "분리", icon: "Split.png", vmProp: "SplitVM"),
        SubTab(title: "포맷 변환", icon: "Convert.png", vmProp: "ConverterVM"),
        SubTab(title: "새턴 NSP 변환", icon: "Saturn.png", vmProp: "ConvertSaturnVM"),
        SubTab(title: "버전 무시", icon: "Keygen.png", vmProp: "KeygenVM"),
        SubTab(title: "파일명 변경", icon: "Rename.png", vmProp: "RenameVM"),
    ]

    var body: some View {
        ChildVM(id: vmId) { vm in
            ZStack {
                // TabControl SelectedIndex = SubTabIndex, TabItem.IsEnabled = CanUseTools
                SubTabsView(owner: vm, tabs: tabs, selectionProp: "SubTabIndex", enabledProp: "CanUseTools") { index, childId in
                    ChildVM(id: childId) { child in
                        switch index {
                        case 0: SwitchRepackTab(vm: child)
                        case 1: SwitchMergeTab(vm: child)
                        case 2: SwitchSplitTab(vm: child)
                        case 3: SwitchConverterTab(vm: child)
                        case 4: SwitchSaturnTab(vm: child)
                        case 5: SwitchKeygenTab(vm: child)
                        default: SwitchRenameTab(vm: child)
                        }
                    }
                }

                if keysAvailable == false {
                    keysMissing
                }
            }
            // RefreshKeysStatus()가 CanUseTools 변경을 알린다.
            .task(id: vm["CanUseTools"]) {
                keysAvailable = await engine.callStatic(Self.viewModel, "get_KeysAvailable")?.bool
                keysMissingMessage = await engine.callStatic(Self.viewModel, "get_KeysMissingMessage")?.string ?? ""
            }
        }
    }

    /// KeysAvailable == false 일 때 탭 전체를 덮는 안내
    private var keysMissing: some View {
        ZStack {
            Rectangle()
                .fill(.background.opacity(0.92))
                .contentShape(Rectangle())

            VStack(spacing: 8) {
                UpstreamIcon(name: "Switch.png", size: 48)
                    .padding(.bottom, 8)
                Text("prod.keys 파일이 없습니다")
                    .font(.title2.bold())
                Text(keysMissingMessage)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 480)
        }
    }
}
