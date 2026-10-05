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

            Toggle(isOn: engine.bool(vm, "UseCustomOutputPath")) {
                HStack(spacing: 12) {
                    Text("출력 폴더 변경").fontWeight(.bold)
                    Text("해제 시 원본 ROM 폴더 안의 output 폴더에 저장").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 5)

            if vm.isVisible("OutputPathVisibility") {
                HStack(spacing: 5) {
                    // 빈 값일 때의 안내(OutputHintVisibility)는 입력란 안내 문구로 보인다.
                    TextField("출력 폴더를 선택하세요", text: engine.string(vm, "OutputPath"))
                        .textFieldStyle(.roundedBorder)
                    Button {
                        engine.run(vm, "BrowseOutputCommand")
                    } label: {
                        UpstreamIcon(name: "AddFolder.png", size: 20)
                    }
                    .disabled(!engine.canRun(vm, "BrowseOutputCommand"))
                }
                .padding(.top, 2)
            }
        }
    }
}
