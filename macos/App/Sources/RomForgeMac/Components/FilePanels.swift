import AppKit
import UniformTypeIdentifiers

/// code-behind의 파일·폴더 대화상자(OpenFileDialog · OpenFolderDialog · VistaFolderBrowserDialog)와 폴더 열기·URL 열기.
/// macOS 열기 창은 제목(Title·Description)을 보이지 않으므로 같은 문구를 안내 문구(message)로도 보인다.
@MainActor
enum FilePanels {
    /// OpenFileDialog{Title, Filter, Multiselect}. filter는 upstream WPF 필터 문자열 그대로 받고
    /// 엔진 대화상자(UiHostHandler)와 같은 규칙으로 쓴다('*.*'가 있으면 형식을 제한하지 않음). title이 없으면 제목 없이 연다.
    static func openFiles(title: String? = nil, filter: String? = nil, multiple: Bool = false) -> [String] {
        let panel = filePanel(title: title, multiple: multiple)
        UiHostHandler.applyFilter(filter, to: panel)
        return panel.runModal() == .OK ? panel.urls.map(\.path) : []
    }

    /// OpenFileDialog(필터는 WPF 대화상자의 기본(첫) 필터). extensions가 nil이면 모든 파일
    static func openFiles(title: String, extensions: [String]?, multiple: Bool = false) -> [String] {
        let panel = filePanel(title: title, multiple: multiple)
        if let extensions {
            panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        }
        return panel.runModal() == .OK ? panel.urls.map(\.path) : []
    }

    /// OpenFolderDialog / VistaFolderBrowserDialog(Description을 제목으로)
    static func openFolder(title: String) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private static func filePanel(title: String?, multiple: Bool) -> NSOpenPanel {
        let panel = NSOpenPanel()
        if let title {
            panel.title = title
            panel.message = title
        }
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = multiple
        return panel
    }

    // MARK: Finder · URL

    /// NSW.WPF.Services.ProcessExtensions.OpenFolder: 폴더가 있으면 Finder로 연다.
    static func showFolder(_ path: String?) {
        guard let path, !path.isEmpty, isDirectory(path) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Path.GetDirectoryName(file).OpenFolder(): 파일이 있는 폴더를 연다.
    static func showContainingFolder(_ file: String) {
        showFolder((file as NSString).deletingLastPathComponent)
    }

    /// Process.Start("https://…")
    static func openURL(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    // MARK: 경로 판정

    /// Directory.Exists(path)
    nonisolated static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// 폴더 입력란의 PreviewDragOver + Drop: 끌어다 놓은 첫 항목이 폴더일 때만 그 경로를 돌려준다
    /// (Drop은 파일이면 그 폴더를 쓰지만 PreviewDragOver가 폴더가 아닌 드롭을 DragDropEffects.None으로 막는다).
    nonisolated static func droppedFolder(_ urls: [URL]) -> String? {
        guard let path = urls.first?.path, isDirectory(path) else { return nil }
        return path
    }
}
