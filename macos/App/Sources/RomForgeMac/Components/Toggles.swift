import SwiftUI

/// upstream SlideToggleStyle ToggleButton: 상자 왼쪽에 내용, 오른쪽에 슬라이드 스위치(스위치는 macOS 기본 스위치).
struct SlideToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(isOn: configuration.$isOn) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// upstream LeftSlideToggleStyle: 밀어서 켜는 스위치를 문구 왼쪽에 둔다(macOS 기본 .switch는 스위치가 문구 오른쪽에 온다).
/// upstream은 스위치와 문구가 한 버튼이라 문구를 눌러도 바뀐다.
struct LeftSlideToggleStyle: ToggleStyle {
    /// 스위치와 문구 사이 간격
    var spacing: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        SlideToggle(configuration: configuration, spacing: spacing)
    }

    private struct SlideToggle: View {
        let configuration: ToggleStyleConfiguration
        let spacing: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            HStack(spacing: spacing) {
                Toggle(isOn: configuration.$isOn) { configuration.label }
                    .toggleStyle(.switch)
                    .labelsHidden()
                configuration.label
                    .opacity(isEnabled ? 1 : 0.5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isEnabled { configuration.isOn.toggle() }
                    }
            }
            .fixedSize()
        }
    }
}
