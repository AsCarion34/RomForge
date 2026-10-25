// upstream: RomForge/Controls/Settings/PatchSettingsTab.xaml(.cs)
// ViewModel: PatchSettingsMainViewModel (SettingsMainViewModel.Patch)
import SwiftUI

/// 패치 설정(하위 탭 "일반"): 패치 후 자동 압축 / 출력 폴더 변경
struct SettingsPatchTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    var body: some View {
        InnerTabs(titles: ["일반"], selection: .constant(0)) { _ in
            general
                .padding(12)
        }
        .padding(8)
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: engine.bool(vm, "AutoCompress")) {
                HStack(spacing: 12) {
                    Text("패치 후 자동 압축").fontWeight(.bold)
                    HStack(spacing: 16) {
                        SettingsFormatMapping(from: "BIN / IMG / ISO", to: "CHD")
                        SettingsFormatMapping(from: "3DS / CCI / CIA", to: "ZCCI")
                        SettingsFormatMapping(from: "GCM / Wii / WBFS", to: "RVZ")
                        SettingsFormatMapping(from: "이외 기타", to: "ZIP")
                    }
                }
            }

            // SlideToggleStyle ToggleButton
            Toggle(isOn: engine.bool(vm, "UseCustomOutputPath")) {
                HStack(spacing: 10) {
                    UpstreamIcon(name: "AddFolder.png", size: 18)
                    Text("출력 폴더 변경").fontWeight(.bold)
                    Text("해제 시 원본 ROM 폴더 안의 output 폴더에 저장").font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(SlideToggleStyle())
            .padding(.top, 5)

            if vm.isVisible("OutputPathVisibility") {
                // 폴더를 드롭하면 OutputPath로(TxtOutputPath_PreviewDragOver: 첫 경로가 폴더일 때만 / TxtOutputPath_Drop)
                SettingsPathField(vm: vm, prop: "OutputPath", placeholder: "출력 폴더를 선택하세요",
                                  browseCommand: "BrowseOutputCommand", dropValue: FilePanels.droppedFolder)
                    .padding(.top, 2)
            }
        }
    }
}
