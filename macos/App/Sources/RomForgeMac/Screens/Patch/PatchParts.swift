// upstream: RomForge/Controls/Patch/NormalTab.xaml(.cs), RomForge/Controls/Patch/ArcadeTab.xaml(.cs), RomForge/Controls/Patch/VitaTab.xaml(.cs), RomForge/Controls/Patch/Pc98Tab.xaml(.cs) (DropZone·안내·진행률 줄 공통 부분)
// ViewModel: NormalPatchMainViewModel, ArcadePatchMainViewModel, VitaPatchMainViewModel, Pc98PatchMainViewModel
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

    /// "/Assets/Images/Patch.png" 같은 upstream 리소스 경로에서 파일 이름만
    static func assetName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// code-behind의 OpenFileDialog / VistaFolderBrowserDialog 자리.
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
}

/// upstream DropZone 스타일 Border: 파일 드롭(Drop)과 클릭(MouseLeftButtonDown)을 받는 상자.
struct PatchDropZone<Content: View>: View {
    var enabled = true
    var tooltip: String? = nil
    let onDrop: ([String]) -> Void
    var onClick: (() -> Void)? = nil
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
                if enabled { onClick?() }
            }
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

/// 하위 탭 아래쪽 진행률 줄: [ProgressLabel] [ProgressPercent] [ProgressSpeed] [ProgressTime] [막대 140]
struct PatchProgressFooter: View {
    let label: String
    let percent: String
    var speed: String? = nil
    var time: String? = nil
    /// 0~100
    let value: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(percent).fontWeight(.semibold).monospacedDigit()
            if let speed {
                Text(speed).foregroundStyle(.secondary).monospacedDigit()
            }
            if let time {
                Text(time).monospacedDigit()
            }
            ProgressView(value: min(max(value / 100, 0), 1))
                .frame(width: 140)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .frame(height: 28)
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
