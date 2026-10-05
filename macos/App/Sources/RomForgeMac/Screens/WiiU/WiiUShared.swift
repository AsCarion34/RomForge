// upstream: NSW.WPF/UI/IconButton.xaml(.cs), RomForge/Controls/WiiU/*.xaml 공통 배치(진행 줄 · 빈 목록 안내)
// ViewModel: WiiUMainViewModel 하위 탭 공용 보조 뷰
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
}

// MARK: - 보조 뷰

/// 진행 줄: ProgressLabel · ProgressPercent · ProgressSpeed · ProgressTime · 막대(ProgressPct)
struct WiiUProgressRow: View {
    let vm: RemoteObject

    var body: some View {
        HStack(spacing: 10) {
            Text(vm.string("ProgressLabel"))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Text(vm.string("ProgressPercent")).foregroundStyle(.green).fontWeight(.semibold)
            Text(vm.string("ProgressSpeed")).foregroundStyle(.secondary)
            Text(vm.string("ProgressTime")).foregroundStyle(.green)
            ProgressView(value: min(max((vm["ProgressPct"]?.double ?? 0) / 100, 0), 1))
                .frame(width: 140)
        }
        .font(.caption.monospacedDigit())
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
