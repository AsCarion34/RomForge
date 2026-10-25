// upstream: RomForge/Controls/Patch/NormalTab.xaml(.cs), RomForge/Controls/Patch/ArcadeTab.xaml(.cs), RomForge/Controls/Patch/Pc98Tab.xaml(.cs)
// ViewModel: NormalPatchMainViewModel, ArcadePatchMainViewModel, Pc98PatchMainViewModel
// (하위 탭 공통 부분: DropZone · 클릭 메뉴 · 안내 · 포맷 배지 · 경고 창)
import AppKit
import SwiftUI

/// 패치 하위 탭들이 같이 쓰는 보조 기능(이 폴더 전용).
@MainActor
enum PatchUI {
    /// XAML의 {Binding IsIdle}. 패치 탭(MainTab·NormalTab·ArcadeTab·Pc98Tab)의 DataContext는 MainViewModel이라 루트 값을 쓴다.
    static func rootIsIdle(_ engine: EngineClient) -> Bool {
        engine.store.object(engine.rootId)?["IsIdle"]?.bool ?? true
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
    static func patchPathMenu(_ assign: @escaping (String) -> Void) -> [ContextMenuItem] {
        [
            ContextMenuItem(title: "폴더 선택...", icon: "AddFolder.png") {
                if let path = FilePanels.openFolder(title: "패치 폴더 선택") { assign(path) }
            },
            ContextMenuItem(title: "파일 선택 (*.ips, *.zip)...", icon: "ZipFolder.png") {
                if let path = FilePanels.openFiles(title: "패치 파일 선택", filter: patchFileFilter).first { assign(path) }
            },
        ]
    }

    /// ArcadePatchDrop_Drop · PatchDrop_Drop: 첫 항목이 폴더 · .ips · .zip이면 넣고, 아니면 경고한다.
    static func dropPatchPath(_ paths: [String], _ assign: (String) -> Void) {
        guard let path = paths.first else { return }
        let ext = (path as NSString).pathExtension.lowercased()

        if FilePanels.isDirectory(path) || ext == "ips" || ext == "zip" {
            assign(path)
        } else {
            warn("폴더 또는 IPS/ZIP 파일만 등록할 수 있습니다.")
        }
    }
}

/// upstream DropZone 스타일 Border: 파일 드롭(Drop)과 클릭(MouseLeftButtonDown)을 받는 상자.
/// menu가 있으면 Border.ContextMenu처럼 오른쪽 클릭으로 열리고, 왼쪽 클릭에도 같은 메뉴를 띄운다(code-behind가 IsOpen = true).
struct PatchDropZone<Content: View>: View {
    var enabled = true
    var tooltip: String? = nil
    let onDrop: ([String]) -> Void
    var onClick: (() -> Void)? = nil
    var menu: [ContextMenuItem] = []
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
                if menu.isEmpty { onClick?() } else { PopUpMenu.show(menu) }
            }
            .contextMenuItems(enabled ? menu : [])
            .dropDestination(for: URL.self) { urls, _ in
                guard enabled, !urls.isEmpty else { return false }
                onDrop(urls.map(\.path))
                return true
            } isTargeted: { targeted = $0 && enabled }
            .help(tooltip ?? "")
            .opacity(enabled ? 1 : 0.55)
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
