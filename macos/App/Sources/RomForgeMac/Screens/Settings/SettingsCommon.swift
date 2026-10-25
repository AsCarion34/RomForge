// upstream: RomForge/Controls/Settings/GeneralSettingsTab.xaml(.cs), RomForge/Controls/Settings/PatchSettingsTab.xaml(.cs), RomForge/Controls/Settings/CompressSettingsTab.xaml, RomForge/Controls/Settings/PSSettingsTab.xaml
// ViewModel: GeneralSettingsMainViewModel, PatchSettingsMainViewModel, CompressSettingsMainViewModel, PSSettingsMainViewModel
// 설정 하위 탭 공통 부품: 경로 입력란(드롭·찾아보기), RadioButton, 압축 레벨 안내, 형식 배지
import SwiftUI

/// 경로 입력란 + 찾아보기 버튼(upstream: 둥근 상자 안 TextBox(UpdateSourceTrigger=PropertyChanged) + 안내 TextBlock + AddFolder.png 버튼).
/// 값이 비었을 때 보이던 안내(XxxHintVisibility)는 입력란 안내 문구로 보인다.
/// 찾아보기 버튼은 테두리 있는 버튼이라 다른 탭의 FolderPathRow(테두리 없는 ToolIconButton)를 쓰지 않는다.
struct SettingsPathField: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject
    let prop: String
    let placeholder: String
    let browseCommand: String
    /// 입력란 Drop: 드롭한 경로들에서 넣을 값을 고른다(nil이면 받지 않는다).
    let dropValue: ([URL]) -> String?

    var body: some View {
        HStack(spacing: 5) {
            PathField(vm: vm, prop: prop, placeholder: placeholder)
                .dropDestination(for: URL.self) { urls, _ in
                    guard let value = dropValue(urls) else { return false }
                    engine.string(vm, prop).wrappedValue = value
                    return true
                }
            Button {
                engine.run(vm, browseCommand)
            } label: {
                UpstreamIcon(name: "AddFolder.png", size: 20)
            }
            .disabled(!engine.canRun(vm, browseCommand))
        }
    }

    /// PreviewDragOver가 모든 파일 드롭을 받는 입력란(효과음). Drop은 첫 파일 경로를 넣는다.
    static func firstFile(_ urls: [URL]) -> String? {
        urls.first?.path
    }
}

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

/// 압축 레벨 안내 줄: "압축 레벨  3: 최대 속도 | 9: 균형 | 18: 권장"
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
