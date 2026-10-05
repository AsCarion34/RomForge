// upstream: RomForge/Controls/Settings/PSSettingsTab.xaml(.cs)
// ViewModel: PSSettingsMainViewModel (SettingsMainViewModel.PS1)
import SwiftUI

/// PS 설정(하위 탭 "PBP 패킹"): 압축 레벨 / 출력 옵션
struct SettingsPSTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    var body: some View {
        InnerTabs(titles: ["PBP 패킹"], selection: .constant(0)) { _ in
            VStack(alignment: .leading, spacing: 5) {
                compressLevel
                outputOptions
            }
            .padding(8)
        }
        .padding(8)
    }

    private var compressLevel: some View {
        OptionCard {
            SettingsLevelLegend(marks: ["0: 무압축", "5: 균형", "9: 최대"])
            HStack(spacing: 5) {
                UpstreamIcon(name: "Level.png", size: 24)
                LevelSlider(vm: vm, prop: "CompressLevel", range: 0...9, colorConverter: "LevelToColorConverter")
            }
        }
    }

    /// 출력 옵션: (●) 일반 ( 타이틀명.pbp ) | (●) 소문자 (●) 대문자 / (●) 실기 ( 타이틀ID / EBOOT.PBP )
    private var outputOptions: some View {
        let fileNameMode = vm["UseFileNameMode"]?.bool ?? false

        return OptionCard {
            HStack(spacing: 8) {
                UpstreamIcon(name: "AddFile.png", size: 20)
                Text("출력 옵션").font(.caption).foregroundStyle(.secondary)
                Divider().frame(height: 40).padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Toggle(isOn: engine.bool(vm, "UseFileNameMode")) {
                            HStack(spacing: 0) {
                                Text("일반 ( 타이틀명.")
                                Text(vm.string("ExtensionText").nonEmpty ?? "pbp").fontWeight(.bold)
                                Text(" )")
                            }
                        }

                        Divider().frame(height: 14).padding(.horizontal, 4)

                        HStack(spacing: 10) {
                            Toggle(isOn: engine.inverseBool(vm, "UseUpperCase")) {
                                HStack(spacing: 5) {
                                    UpstreamIcon(name: "LowerA.png", size: 16)
                                    Text("소문자")
                                }
                            }
                            Toggle(isOn: engine.bool(vm, "UseUpperCase")) {
                                HStack(spacing: 5) {
                                    UpstreamIcon(name: "UpperA.png", size: 16)
                                    Text("대문자")
                                }
                            }
                        }
                        .disabled(!fileNameMode)
                    }

                    Toggle("실기 ( 타이틀ID / EBOOT.PBP )", isOn: engine.bool(vm, "UseGameIdMode"))
                }
                .toggleStyle(SettingsRadioStyle())
                .font(.callout)
            }
        }
    }
}
