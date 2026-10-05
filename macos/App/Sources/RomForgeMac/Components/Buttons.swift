import SwiftUI

/// upstream 버튼 내용(Image + TextBlock)
struct IconLabel: View {
    let title: String
    let icon: String
    var size: CGFloat = 18

    var body: some View {
        Label {
            Text(title)
        } icon: {
            UpstreamIcon(name: icon, size: size)
        }
    }
}

/// upstream 하단 버튼(아이콘 + 문구). code-behind Click 처리기는 action으로 받는다.
struct IconButton: View {
    let title: String
    let icon: String
    var enabled = true
    var prominent = false
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) { IconLabel(title: title, icon: icon) }
            .disabled(!enabled)

        if prominent { button.buttonStyle(.borderedProminent) } else { button }
    }
}

/// Command가 붙은 upstream 버튼. XAML의 IsEnabled 바인딩(enabled)과 CanExecute를 함께 따른다.
struct CommandIconButton: View {
    @Environment(EngineClient.self) private var engine
    let title: String
    let icon: String
    let vm: RemoteObject
    let command: String
    var enabled = true
    var prominent = false

    var body: some View {
        IconButton(title: title, icon: icon, enabled: enabled && engine.canRun(vm, command), prominent: prominent) {
            engine.run(vm, command)
        }
    }
}

/// NSW.WPF/UI/IconButton: 실행 중이면 취소 문구·아이콘으로 바뀌는 큰 버튼(IconConverter·TextToggleConverter 자리)
struct RunCancelButton: View {
    let title: String
    let icon: String
    var cancelTitle = "취소"
    var cancelIcon = "Cancel.png"
    let isRunning: Bool
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                UpstreamIcon(name: isRunning ? cancelIcon : icon, size: 22)
                Text(isRunning ? cancelTitle : title).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .disabled(!enabled)
    }
}

/// 아이콘만 있는 작은 버튼(GrayButton + Image + ToolTip)
struct ToolIconButton: View {
    let icon: String
    var help = ""
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) { UpstreamIcon(name: icon, size: 22) }
            .buttonStyle(.borderless)
            .help(help)
            .disabled(!enabled)
    }
}
