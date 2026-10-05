import AppKit
import UniformTypeIdentifiers

/// upstream 코드가 WPF 대화상자·메시지 상자로 요청한 것을 macOS 기본 UI로 보여 주고 결과를 돌려준다.
/// 엔진 쪽은 macos/Engine/Bridge/UiHostBridge.cs.
@MainActor
enum UiHostHandler {
    static func handle(_ method: String, _ p: JSONValue) -> JSONValue {
        switch method {
        case "ui.messageBox": return messageBox(p)
        case "ui.openFile": return openFile(p)
        case "ui.saveFile": return saveFile(p)
        case "ui.openFolder": return openFolder(p)
        case "ui.password": return password(p)
        case "ui.clipboard": return clipboard(p)
        case "ui.callback": return UiCallbacks.handle(p)
        default: return .null
        }
    }

    private static func messageBox(_ p: JSONValue) -> JSONValue {
        let alert = NSAlert()
        alert.messageText = p["caption"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? "RomForge"
        alert.informativeText = p["text"]?.string ?? ""
        alert.alertStyle = switch p["icon"]?.string {
        case "Error", "Hand", "Stop": .critical
        case "Warning", "Exclamation": .warning
        default: .informational
        }

        let buttons: [(title: String, result: String)] = switch p["button"]?.string {
        case "OKCancel": [("확인", "OK"), ("취소", "Cancel")]
        case "YesNo": [("예", "Yes"), ("아니요", "No")]
        case "YesNoCancel": [("예", "Yes"), ("아니요", "No"), ("취소", "Cancel")]
        default: [("확인", "OK")]
        }

        buttons.forEach { alert.addButton(withTitle: $0.title) }
        let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return .string(buttons.indices.contains(index) ? buttons[index].result : buttons[0].result)
    }

    private static func openFile(_ p: JSONValue) -> JSONValue {
        let panel = NSOpenPanel()
        panel.title = p["title"]?.string ?? ""
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = p["multiselect"]?.bool ?? false
        applyFilter(p["filter"]?.string, to: panel)
        if let dir = p["initialDirectory"]?.string, !dir.isEmpty { panel.directoryURL = URL(fileURLWithPath: dir) }

        guard panel.runModal() == .OK else { return .null }
        return .strings(panel.urls.map(\.path))
    }

    private static func saveFile(_ p: JSONValue) -> JSONValue {
        let panel = NSSavePanel()
        panel.title = p["title"]?.string ?? ""
        panel.isExtensionHidden = false
        applyFilter(p["filter"]?.string, to: panel)
        if let name = p["fileName"]?.string, !name.isEmpty { panel.nameFieldStringValue = (name as NSString).lastPathComponent }
        if let dir = p["initialDirectory"]?.string, !dir.isEmpty { panel.directoryURL = URL(fileURLWithPath: dir) }

        guard panel.runModal() == .OK, let url = panel.url else { return .null }
        return .string(url.path)
    }

    private static func openFolder(_ p: JSONValue) -> JSONValue {
        let panel = NSOpenPanel()
        panel.title = p["title"]?.string ?? ""
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = p["multiselect"]?.bool ?? false
        if let dir = p["initialDirectory"]?.string, !dir.isEmpty { panel.directoryURL = URL(fileURLWithPath: dir) }

        guard panel.runModal() == .OK else { return .null }
        return .strings(panel.urls.map(\.path))
    }

    private static func password(_ p: JSONValue) -> JSONValue {
        let alert = NSAlert()
        let name = (p["archivePath"]?.string ?? "") as NSString
        alert.messageText = "비밀번호 입력"
        alert.informativeText = (p["wrongPassword"]?.bool ?? false)
            ? "비밀번호가 올바르지 않습니다. 다시 입력해 주세요.\n\(name.lastPathComponent)"
            : "압축 파일의 비밀번호를 입력하세요.\n\(name.lastPathComponent)"

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")
        alert.window.initialFirstResponder = field

        return alert.runModal() == .alertFirstButtonReturn ? .string(field.stringValue) : .null
    }

    private static func clipboard(_ p: JSONValue) -> JSONValue {
        NSPasteboard.general.clearContents()
        return .bool(NSPasteboard.general.setString(p["text"]?.string ?? "", forType: .string))
    }

    /// WPF 필터("설명|*.iso;*.cue|모든 파일|*.*")에서 확장자를 뽑아 허용 형식으로 쓴다.
    private static func applyFilter(_ filter: String?, to panel: NSSavePanel) {
        guard let filter, !filter.isEmpty else { return }
        let parts = filter.split(separator: "|", omittingEmptySubsequences: false)
        let patterns = stride(from: 1, to: parts.count, by: 2).flatMap { parts[$0].split(separator: ";") }
        let extensions = patterns.compactMap { pattern -> String? in
            let ext = pattern.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "*.", with: "")
            return ext.isEmpty || ext == "*" ? nil : ext
        }

        if patterns.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "*.*" }) || extensions.isEmpty { return }
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
    }
}
