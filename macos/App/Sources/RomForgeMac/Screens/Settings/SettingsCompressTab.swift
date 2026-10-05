// upstream: RomForge/Controls/Settings/CompressSettingsTab.xaml(.cs)
// ViewModel: CompressSettingsMainViewModel (SettingsMainViewModel.Compress)
import SwiftUI

/// 압축 설정: CHDMAN(chd) / Switch(nsz,xcz) / Azahar(zcci) / Dolphin(rvz).
/// 하위 탭 선택은 SelectedTabIndex(MainViewModel이 Switch "설정" 버튼으로 1로 바꾼다)에 맞춘다.
struct SettingsCompressTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: engine.int(vm, "SelectedTabIndex")) {
                Label { Text("CHDMAN(chd)") } icon: { UpstreamIcon(name: "Mame.png", size: 16) }.tag(0)
                Label { Text("Switch(nsz,xcz)") } icon: { UpstreamIcon(name: "Switch.png", size: 16) }.tag(1)
                Label { Text("Azahar(zcci)") } icon: { UpstreamIcon(name: "Azahar.png", size: 16) }.tag(2)
                Label { Text("Dolphin(rvz)") } icon: { UpstreamIcon(name: "Dolphin.png", size: 16) }.tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            switch vm["SelectedTabIndex"]?.int ?? 0 {
            case 1: page { switchOptions }
            case 2: page { azahar }
            case 3: page { dolphin }
            default: page { chdman }
            }
        }
        .observeLists(engine, vm, ["ChdmanCompressionOptions"])
    }

    private func page(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            content()
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: CHDMAN

    /// ComboBox ItemsSource=ChdmanCompressionOptions, SelectedItem=ChdmanCompression, DisplayMemberPath=Display
    private var chdman: some View {
        OptionCard(title: "압축 알고리즘 (ISO: PSP, PS2)", icon: "Neural.png") {
            Picker("", selection: engine.selectedItem(vm, "ChdmanCompression")) {
                ForEach(engine.items(vm, "ChdmanCompressionOptions")) { option in
                    Text(option.string("Display")).tag(Optional(option.id))
                }
            }
            .labelsHidden()
        }
    }

    // MARK: Switch

    private var switchOptions: some View {
        Group {
            OptionCard {
                SettingsLevelLegend(marks: ["무압축(NSP)", "3: 최대 속도", "9: 균형", "18: 권장"])
                HStack(spacing: 5) {
                    UpstreamIcon(name: "Level.png", size: 24)
                    LevelSlider(vm: vm, prop: "SwitchCompressLevel", range: 2...18,
                                textConverter: "CompressLevelTextConverter", colorConverter: "LevelToColorConverter")
                }
            }

            OptionCard {
                HStack(spacing: 8) {
                    UpstreamIcon(name: "BlockMode.png", size: 20)
                    Text("압축 모드").font(.caption).foregroundStyle(.secondary)
                    Divider().frame(height: 16).padding(.horizontal, 4)
                    Toggle("블록", isOn: engine.bool(vm, "SwitchUseBlockMode"))
                        .padding(.trailing, 16)
                    Toggle("블록리스", isOn: engine.bool(vm, "SwitchUseBlocklessMode"))
                }
                .toggleStyle(SettingsRadioStyle())
            }

            Toggle("압축 무결성 검증 : 압축 후 원본과 해시 비교 검증", isOn: engine.bool(vm, "SwitchIsValidationEnabled"))
                .padding(.top, 5)
        }
    }

    // MARK: Azahar / Dolphin

    private var azahar: some View {
        levelCard(prop: "AzaharCompressLevel")
    }

    private var dolphin: some View {
        levelCard(prop: "WiiGCCompressLevel")
    }

    /// 3~18 레벨 슬라이더(값은 그대로, 색은 LevelToColorConverter)
    private func levelCard(prop: String) -> some View {
        OptionCard {
            SettingsLevelLegend(marks: ["3: 최대 속도", "9: 균형", "18: 권장"])
            HStack(spacing: 10) {
                UpstreamIcon(name: "Level.png", size: 24)
                LevelSlider(vm: vm, prop: prop, range: 3...18, colorConverter: "LevelToColorConverter")
            }
        }
    }
}
