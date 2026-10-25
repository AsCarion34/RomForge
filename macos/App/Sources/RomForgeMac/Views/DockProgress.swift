// upstream: RomForge/Views/MainWindow.xaml(.cs)의 TaskbarItemInfo, RomForge.Core/UI/Helpers/Win32API.cs의 FlashTaskbarIcon
// ViewModel: MainViewModel(TaskbarProgressState, TaskbarProgressValue)
import AppKit

/// Windows 작업 표시줄 진행도를 Dock 아이콘 진행 막대로 보여 준다.
/// upstream은 오류(Error)가 되면 작업 표시줄 아이콘을 깜빡인다. macOS에서는 앱이 뒤에 있을 때 Dock 아이콘을 튀긴다.
@MainActor
enum DockProgress {
    private static var progressView: DockProgressView?
    private static var lastState = "None"

    static func update(state: String, value: Double) {
        let tile = NSApp.dockTile

        if state == "None" {
            tile.contentView = nil
            progressView = nil
        } else {
            let view = progressView ?? DockProgressView(frame: NSRect(origin: .zero, size: tile.size))
            view.state = state
            view.value = min(max(value, 0), 1)
            progressView = view
            tile.contentView = view
        }

        tile.display()

        if state == "Error", lastState != "Error", !NSApp.isActive {
            NSApp.requestUserAttention(.criticalRequest)
        }
        lastState = state
    }
}

private final class DockProgressView: NSView {
    var state = "Normal"
    var value = 0.0

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage?.draw(in: bounds)

        let bar = NSRect(x: bounds.width * 0.1, y: bounds.height * 0.08, width: bounds.width * 0.8, height: bounds.height * 0.11)
        let track = NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2)
        NSColor.black.withAlphaComponent(0.55).setFill()
        track.fill()

        // Indeterminate는 진행 값이 없으므로 막대를 가득 채워 작업 중임만 보인다.
        let fraction = state == "Indeterminate" ? 1 : value
        guard fraction > 0 else { return }

        var fill = bar.insetBy(dx: 2, dy: 2)
        fill.size.width *= fraction
        let color: NSColor = switch state {
        case "Error": .systemRed
        case "Paused": .systemYellow
        default: .systemGreen
        }
        color.setFill()
        NSBezierPath(roundedRect: fill, xRadius: fill.height / 2, yRadius: fill.height / 2).fill()
    }
}
