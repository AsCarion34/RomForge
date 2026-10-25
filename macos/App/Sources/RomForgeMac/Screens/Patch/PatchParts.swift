// upstream: RomForge/Controls/Patch/NormalTab.xaml(.cs), RomForge/Controls/Patch/ArcadeTab.xaml(.cs), RomForge/Controls/Patch/Pc98Tab.xaml(.cs)
// ViewModel: NormalPatchMainViewModel, ArcadePatchMainViewModel, Pc98PatchMainViewModel
// (하위 탭 공통 부분: DropZone · 클릭 메뉴 · 안내 · 포맷 배지 · 경고 창)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 패치 하위 탭들이 같이 쓰는 보조 기능(이 폴더 전용).
@MainActor
enum PatchUI {
    /// XAML의 {Binding IsIdle}. 패치 탭(MainTab·NormalTab·ArcadeTab·Pc98Tab)의 DataContext는 MainViewModel이라 루트 값을 쓴다.
    static func rootIsIdle(_ engine: EngineClient) -> Bool {
        engine.store.object(engine.rootId)?["IsIdle"]?.bool ?? true
    }

    static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// code-behind의 OpenFileDialog / OpenFolderDialog 자리.
    /// filter는 upstream WPF 필터 문자열을 그대로 받고 UiHostHandler와 같은 규칙으로 쓴다('*.*'가 있으면 형식을 제한하지 않음).
    static func choosePath(title: String, filter: String? = nil, folder: Bool = false) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseFiles = !folder
        panel.canChooseDirectories = folder
        panel.canCreateDirectories = folder
        panel.allowsMultipleSelection = false

        if let filter {
            let parts = filter.split(separator: "|", omittingEmptySubsequences: false)
            let patterns = stride(from: 1, to: parts.count, by: 2)
                .flatMap { parts[$0].split(separator: ";") }
                .map { $0.trimmingCharacters(in: .whitespaces) }

            if !patterns.contains("*.*") {
                let types = patterns.compactMap { $0.hasPrefix("*.") ? UTType(filenameExtension: String($0.dropFirst(2))) : nil }
                if !types.isEmpty { panel.allowedContentTypes = types }
            }
        }

        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    /// MessageBox.Show(text, "오류", OK, Warning). 드롭 처리 도중에 모달 창을 열지 않도록 다음 차례에 띄운다.
    static func warn(_ text: String, caption: String = "오류") {
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = caption
            alert.informativeText = text
            alert.alertStyle = .warning
            alert.addButton(withTitle: "확인")
            alert.runModal()
        }
    }

    // MARK: 패치 경로(ArcadeTab · Pc98Tab 공통)

    /// SelectFile_Click의 OpenFileDialog.Filter
    static let patchFileFilter = "패치 파일 (*.ips;*.zip)|*.ips;*.zip|IPS 파일 (*.ips)|*.ips|ZIP 압축 파일 (*.zip)|*.zip|모든 파일 (*.*)|*.*"

    /// 패치 DropZone의 Border.ContextMenu: [폴더 선택... (SelectFolder_Click) | 파일 선택 (*.ips, *.zip)... (SelectFile_Click)]
    static func patchPathMenu(_ assign: @escaping (String) -> Void) -> [PatchMenuItem] {
        [
            PatchMenuItem(title: "폴더 선택...", icon: "AddFolder.png") {
                if let path = choosePath(title: "패치 폴더 선택", folder: true) { assign(path) }
            },
            PatchMenuItem(title: "파일 선택 (*.ips, *.zip)...", icon: "ZipFolder.png") {
                if let path = choosePath(title: "패치 파일 선택", filter: patchFileFilter) { assign(path) }
            },
        ]
    }

    /// ArcadePatchDrop_Drop · PatchDrop_Drop: 첫 항목이 폴더 · .ips · .zip이면 넣고, 아니면 경고한다.
    static func dropPatchPath(_ paths: [String], _ assign: (String) -> Void) {
        guard let path = paths.first else { return }
        let ext = (path as NSString).pathExtension.lowercased()

        if isDirectory(path) || ext == "ips" || ext == "zip" {
            assign(path)
        } else {
            warn("폴더 또는 IPS/ZIP 파일만 등록할 수 있습니다.")
        }
    }

    // MARK: 클릭 메뉴

    /// MouseLeftButtonDown에서 ContextMenu.IsOpen = true 하던 자리: 마우스 위치에 같은 메뉴를 띄운다.
    static func popUpMenu(_ items: [PatchMenuItem]) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for item in items {
            let handler = PatchMenuHandler(item.action)
            let menuItem = NSMenuItem(title: item.title, action: #selector(PatchMenuHandler.runAction), keyEquivalent: "")
            menuItem.target = handler
            menuItem.representedObject = handler // target은 약한 참조라 메뉴 항목이 붙잡아 둔다

            if let image = UpstreamAssets.nsImage(item.icon)?.copy() as? NSImage {
                image.size = NSSize(width: 16, height: 16)
                menuItem.image = image
            }
            menu.addItem(menuItem)
        }

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// ContextMenu의 MenuItem 하나(Header · Icon · Click)
struct PatchMenuItem: Identifiable {
    let title: String
    let icon: String
    let action: () -> Void
    var id: String { title }
}

private final class PatchMenuHandler: NSObject {
    let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func runAction() { action() }
}

/// upstream DropZone 스타일 Border: 파일 드롭(Drop)과 클릭(MouseLeftButtonDown)을 받는 상자.
/// menu가 있으면 Border.ContextMenu처럼 오른쪽 클릭으로 열리고, 왼쪽 클릭에도 같은 메뉴를 띄운다(code-behind가 IsOpen = true).
struct PatchDropZone<Content: View>: View {
    var enabled = true
    var tooltip: String? = nil
    let onDrop: ([String]) -> Void
    var onClick: (() -> Void)? = nil
    var menu: [PatchMenuItem] = []
    @ViewBuilder var content: Content

    @State private var targeted = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8)

        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shape.fill(targeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06)))
            .overlay(shape.strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.35),
                                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(shape)
            .onTapGesture {
                guard enabled else { return }
                if menu.isEmpty { onClick?() } else { PatchUI.popUpMenu(menu) }
            }
            .modifier(PatchContextMenu(items: enabled ? menu : []))
            .dropDestination(for: URL.self) { urls, _ in
                guard enabled, !urls.isEmpty else { return false }
                onDrop(urls.map(\.path))
                return true
            } isTargeted: { targeted = $0 && enabled }
            .help(tooltip ?? "")
            .opacity(enabled ? 1 : 0.55)
    }
}

/// Border.ContextMenu(오른쪽 클릭). 항목이 없거나(메뉴 없는 상자) IsEnabled=False면 메뉴를 붙이지 않는다.
private struct PatchContextMenu: ViewModifier {
    let items: [PatchMenuItem]

    @ViewBuilder
    func body(content: Content) -> some View {
        if items.isEmpty {
            content
        } else {
            content.contextMenu {
                ForEach(items) { item in
                    Button(action: item.action) {
                        Label { Text(item.title) } icon: { UpstreamAssets.menuImage(item.icon) }
                    }
                }
            }
        }
    }
}

/// DropZone 안의 [아이콘 + 문구](가운데)와 오른쪽 위 작은 제목(예: "원본")
struct PatchZoneLabel: View {
    let icon: String
    var iconSize: CGFloat = 28
    let text: String
    var caption: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            UpstreamIcon(name: icon, size: iconSize)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .padding(.trailing, 6)
            }
        }
    }
}

/// 빈 목록 위 안내(upstream HintVisibility 상자). 클릭·드롭은 아래 목록으로 통과시킨다(IsHitTestVisible=False).
struct PatchHintOverlay: View {
    let icon: String
    let title: String
    var details: [String] = []

    var body: some View {
        VStack(spacing: 6) {
            UpstreamIcon(name: icon, size: 28)
            Text(title).font(.headline)
            ForEach(details, id: \.self) { detail in
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// 지원 포맷 안내의 작은 배지(ZIP, IPS 등)
struct PatchFormatBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
    }
}
