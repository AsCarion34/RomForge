// upstream: RomForge/Controls/WiiU/RepackTab.xaml(.cs), RomForge/Controls/WiiU/ConverterTab.xaml(.cs)
// ViewModel: WiiUMainViewModel 하위 탭 공용 보조 뷰(대화상자 · 출력 폴더 드롭 · 메뉴 항목 · 배지 · 타이틀 칸 · 출력 형식 콤보)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 대화상자·Finder

@MainActor
enum WiiUPanels {
    /// OpenFileDialog(필터는 WPF 대화상자의 기본(첫) 필터). extensions가 nil이면 모든 파일
    static func openFiles(title: String, extensions: [String]? = nil, multiple: Bool = false) -> [String] {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = multiple
        if let extensions {
            panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        }
        return panel.runModal() == .OK ? panel.urls.map(\.path) : []
    }

    /// OpenFolderDialog / VistaFolderBrowserDialog(설명을 제목으로)
    static func openFolder(title: String) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    /// NSW.WPF.Services.ProcessExtensions.OpenFolder: 폴더가 있으면 연다.
    static func showFolder(_ path: String?) {
        var isDirectory: ObjCBool = false
        guard let path, !path.isEmpty, FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    static func openURL(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    /// TxtOutputPath_PreviewDragOver: 첫 항목이 폴더일 때만 받는다(그 밖에는 DragDropEffects.None이라 Drop이 오지 않는다).
    /// TxtOutputPath_Drop: 그 폴더를 OutputPath로.
    static func droppedFolder(_ urls: [URL]) -> String? {
        guard let first = urls.first else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: first.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return first.path
    }
}

extension View {
    /// 출력(작업) 폴더 TextBox의 AllowDrop + TxtOutputPath_PreviewDragOver / TxtOutputPath_Drop.
    /// TextBox가 IsEnabled=false이면 드롭을 받지 않는다(enabled).
    func wiiUOutputFolderDrop(enabled: Bool, onFolder: @escaping (String) -> Void) -> some View {
        dropDestination(for: URL.self) { urls, _ in
            guard enabled, let folder = WiiUPanels.droppedFolder(urls) else { return false }
            onFolder(folder)
            return true
        }
    }
}

// MARK: - 보조 뷰

/// MenuItem(Header + MenuItem.Icon)
struct WiiUMenuLabel: View {
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

/// 배경색이 있는 배지(KindBackground, ExtensionBackground)
struct WiiUBadge: View {
    let text: String
    var background: Color?
    var foreground: Color?

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(foreground ?? .primary)
            .background(background ?? Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// 게임 아이콘 + 두 줄 글자(타이틀 열)
struct WiiUTitleCell: View {
    let item: RemoteObject
    let title: String
    let subtitle: String
    let tooltip: String

    var body: some View {
        HStack(spacing: 10) {
            RemoteImage(value: item["Icon"], size: 32)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.string(title))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .help(item.string(tooltip))
                Text(item.string(subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 항목의 출력 형식 콤보(AvailableFormats / SelectedTargetFormat)
struct WiiUFormatPicker: View {
    @Environment(EngineClient.self) private var engine
    let item: RemoteObject

    var body: some View {
        let listId = item.ref("AvailableFormats")
        let current = item.string("SelectedTargetFormat")
        let loaded = engine.store.items(listId).compactMap(\.string)
        let formats = loaded.isEmpty ? [current] : loaded

        Picker("", selection: engine.string(item, "SelectedTargetFormat")) {
            ForEach(formats, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .frame(width: 96)
        .task(id: listId) { await engine.observeList(listId) }
    }
}
