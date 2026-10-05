// upstream: RomForge/Controls/Util/MainTab.xaml(.cs)
// ViewModel: UtilMainViewModel (MainViewModel.UtilMainVM)
import SwiftUI

/// 유틸 탭: Hash 계산 / 티스토리 다운로더 / SD 굽기 / certs.bin 추출 / Cue 생성.
/// 선택은 UtilMainViewModel.SubTabIndex(TwoWay)에 맞춘다.
struct UtilScreen: View {
    let vmId: Int

    private var tabs: [SubTab] {
        [
            SubTab(title: "Hash 계산", icon: "Hash.png", vmProp: "HashVM"),
            SubTab(title: "티스토리 다운로더", icon: "Tistory.png", vmProp: "TistoryVM"),
            SubTab(title: "SD 굽기", icon: "SD.png", vmProp: "ZipImageToolVM"),
            SubTab(title: "certs.bin 추출", icon: "Certs.png", vmProp: "CertsVM"),
            SubTab(title: "Cue 생성", icon: "CUE.png", vmProp: "CueVM"),
        ]
    }

    var body: some View {
        ChildVM(id: vmId) { vm in
            SubTabsView(owner: vm, tabs: tabs, selectionProp: "SubTabIndex") { index, childId in
                ChildVM(id: childId) { child in
                    switch index {
                    case 0: UtilHashTab(vm: child)
                    case 1: UtilTistoryTab(vm: child)
                    case 2: sdTab(main: vm, tool: child)
                    case 3: UtilCertsTab(vm: child)
                    default: UtilCueTab(vm: child)
                    }
                }
            }
        }
    }

    /// SD 굽기: IsNotAdmin이면 "관리자 권한이 필요합니다.", IsAdmin이면 ZipImageToolTab
    /// (macOS 엔진은 root 권한으로 실행 중일 때만 관리자로 본다)
    @ViewBuilder
    private func sdTab(main: RemoteObject, tool: RemoteObject) -> some View {
        if main["IsAdmin"]?.bool == true {
            UtilZipImageToolTab(vm: tool)
        } else {
            ToolLayout(vm: tool, lists: ["LogEntries"]) {
                Text("관리자 권한이 필요합니다.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
