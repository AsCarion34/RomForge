// upstream: RomForge/Controls/Settings/CompressSettingsTab.xaml, PSSettingsTab.xaml, PatchSettingsTab.xaml 공통 표시 부품(RadioButton, 압축 레벨 안내, 형식 배지)
// ViewModel: CompressSettingsMainViewModel, PSSettingsMainViewModel, PatchSettingsMainViewModel
import SwiftUI

/// upstream RadioButton(IsChecked가 bool 속성 하나에 바인딩된 것). 누르면 그 속성을 true로 만든다.
/// 같은 묶음의 다른 속성을 false로 바꾸는 일은 upstream ViewModel이 한다.
struct SettingsRadioStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsRadioButton(configuration: configuration)
    }
}

private struct SettingsRadioButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ToggleStyleConfiguration

    var body: some View {
        Button {
            configuration.isOn = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: configuration.isOn ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(configuration.isOn ? Color.accentColor : Color.secondary)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

/// 압축 레벨 안내 줄: "압축 레벨  무압축(NSP) | 3: 최대 속도 | 9: 균형 | 18: 권장"
struct SettingsLevelLegend: View {
    let marks: [String]

    var body: some View {
        HStack(spacing: 0) {
            Text("압축 레벨").foregroundStyle(.secondary).padding(.trailing, 20)
            ForEach(Array(marks.enumerated()), id: \.offset) { index, mark in
                if index > 0 {
                    Text("|").foregroundStyle(.tertiary).padding(.horizontal, 20)
                }
                Text(mark)
            }
        }
        .font(.caption)
    }
}

/// 형식 배지("BIN / IMG / ISO" ➔ "CHD")
struct SettingsFormatMapping: View {
    let from: String
    let to: String

    var body: some View {
        HStack(spacing: 4) {
            badge(from)
            Text("➔").font(.caption.weight(.bold)).foregroundStyle(.orange)
            badge(to)
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
    }
}
