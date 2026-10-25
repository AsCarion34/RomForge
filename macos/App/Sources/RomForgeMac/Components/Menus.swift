import AppKit
import SwiftUI

/// upstream ContextMenu의 MenuItem 하나(Header · Icon · Click)
struct ContextMenuItem: Identifiable {
    let title: String
    let icon: String
    let action: @MainActor () -> Void
    var id: String { title }
}

/// MenuItem 내용(Header + MenuItem.Icon). 메뉴는 AppKit이 그려 SwiftUI 크기 지정을 무시하므로 크기를 정한 아이콘 사본을 쓴다.
struct MenuLabel: View {
    let title: String
    let icon: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            UpstreamAssets.menuImage(icon, size: 16)
        }
    }
}

extension View {
    /// Border.ContextMenu(오른쪽 클릭). 항목이 없으면(메뉴 없는 상자, IsEnabled=False) 메뉴를 붙이지 않는다.
    @ViewBuilder
    func contextMenuItems(_ items: [ContextMenuItem]) -> some View {
        if items.isEmpty {
            self
        } else {
            contextMenu {
                ForEach(items) { item in
                    Button(action: item.action) { MenuLabel(title: item.title, icon: item.icon) }
                }
            }
        }
    }
}

/// 왼쪽 클릭으로 ContextMenu 열기(code-behind의 ContextMenu.IsOpen = true) 자리.
/// SwiftUI contextMenu는 코드로 열 수 없으므로 같은 항목의 NSMenu를 마우스 위치에 띄운다.
@MainActor
enum PopUpMenu {
    static func show(_ items: [ContextMenuItem], iconSize: CGFloat = 16) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for item in items {
            let target = Target(item.action)
            let menuItem = NSMenuItem(title: item.title, action: #selector(Target.click), keyEquivalent: "")
            menuItem.target = target
            menuItem.representedObject = target   // NSMenuItem.target은 약한 참조라 항목이 붙잡아 둔다.
            menuItem.image = icon(item.icon, size: iconSize)
            menu.addItem(menuItem)
        }

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// 메뉴 아이콘. 원본 PNG(수백 px)를 그대로 넣으면 메뉴가 커지므로 크기를 정한 사본을 쓴다.
    private static func icon(_ name: String, size: CGFloat) -> NSImage? {
        guard let copy = UpstreamAssets.nsImage(name)?.copy() as? NSImage else { return nil }
        copy.size = NSSize(width: size, height: size)
        return copy
    }

    @MainActor
    private final class Target: NSObject {
        let action: @MainActor () -> Void

        init(_ action: @escaping @MainActor () -> Void) {
            self.action = action
        }

        /// MenuItem Click. 대화상자를 여는 항목이 많아 메뉴가 닫힌 뒤 실행한다.
        @objc func click() {
            let action = action
            Task { @MainActor in action() }
        }
    }
}
