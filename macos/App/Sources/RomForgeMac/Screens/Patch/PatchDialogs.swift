// upstream: RomForge/Controls/Patch/NormalTab.xaml.cs (ShowSourceSelectionDialogAsync, ShowGdRomLayoutDialogAsync, FormatSize)
// ViewModel: NormalPatchMainViewModel.RequestSourceSelectionAsync, SourceHashViewModel.RequestGdRomLayoutAsync
import AppKit
import SwiftUI

/// 패치 > 일반 탭의 code-behind 창 두 개. NormalTab Loaded에서 ViewModel의 Func 속성에 거는 것과 같게 bindCallback으로 건다.
@MainActor
enum PatchDialogs {
    static let selectSourceName = "patch.selectSource"
    static let gdRomLayoutName = "patch.gdRomLayout"

    /// Loaded: NormalVM.RequestSourceSelectionAsync = ShowSourceSelectionDialogAsync,
    ///         NormalVM.SourceHash.RequestGdRomLayoutAsync = ShowGdRomLayoutDialogAsync
    static func bind(_ engine: EngineClient, normalVM: Int, sourceHash: Int?) async {
        await engine.bindCallback(normalVM, "RequestSourceSelectionAsync", name: selectSourceName) { args in
            selectSource(args.first?.array ?? [])
        }
        await engine.bindCallback(sourceHash, "RequestGdRomLayoutAsync", name: gdRomLayoutName) { _ in
            gdRomLayout()
        }
    }

    /// ShowSourceSelectionDialogAsync: 압축 안 원본 후보(ArchiveCandidate: EntryKey, Size) 중 하나를 고른다.
    /// 첫 항목이 선택된 채로 열리고, 취소하면 null(upstream은 작업을 취소한다).
    static func selectSource(_ candidates: [JSONValue]) -> JSONValue {
        let items = candidates.compactMap { candidate -> SourceCandidate? in
            guard let key = candidate["EntryKey"]?.string else { return nil }
            return SourceCandidate(key: key, label: "\((key as NSString).lastPathComponent)  (\(formatSize(candidate["Size"]?.double ?? 0)))")
        }
        guard !items.isEmpty else { return .null }

        let selection = SourceSelection(first: items[0].key)
        let alert = NSAlert()
        alert.messageText = "원본 롬 파일 선택"
        alert.informativeText = "압축 안에 패치 대상 후보가 여러 개입니다. 패치할 원본 파일을 선택하세요:"
        let list = NSHostingView(rootView: SourceCandidateList(items: items, selection: selection))
        list.frame = NSRect(x: 0, y: 0, width: 420, height: min(260, CGFloat(items.count) * 28 + 12))
        alert.accessoryView = list
        alert.addButton(withTitle: "선택")
        alert.addButton(withTitle: "취소")

        guard alert.runModal() == .alertFirstButtonReturn, let key = selection.key else { return .null }
        return .string(key)
    }

    /// ShowGdRomLayoutDialogAsync: 드림캐스트(GD-ROM) CHD 해시 기준. 값은 GdRomHashLayout 이름.
    static func gdRomLayout() -> JSONValue {
        let alert = NSAlert()
        alert.messageText = "드림캐스트(GD-ROM) CHD입니다. 해시를 계산할 기준을 선택하세요."
        alert.informativeText = """
            CHD에는 원본이 cue/bin이었는지 gdi였는지 기록되지 않습니다.

            • GDI 기준: 패치가 실제로 사용하는 파일 (TOSEC 배치)
            • CUE 기준: Redump cue/bin 원본과 비교할 때 (pregap을 원래 위치로 복원)
            """
        alert.addButton(withTitle: "GDI 기준")
        alert.addButton(withTitle: "CUE 기준")
        return .string(alert.runModal() == .alertSecondButtonReturn ? "Cue" : "Gdi")
    }

    /// NormalTab.xaml.cs FormatSize: 1024 단위, 소수 한 자리까지("0.#")
    static func formatSize(_ bytes: Double) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var size = bytes
        var index = 0
        while size >= 1024 && index < units.count - 1 {
            size /= 1024
            index += 1
        }
        let rounded = (size * 10).rounded() / 10
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return "\(text) \(units[index])"
    }
}

private struct SourceCandidate: Identifiable {
    let key: String
    let label: String
    var id: String { key }
}

@MainActor
@Observable
private final class SourceSelection {
    var key: String?
    init(first: String) { key = first }
}

/// upstream ListBox(항목: "파일 이름  (크기)")
private struct SourceCandidateList: View {
    let items: [SourceCandidate]
    @Bindable var selection: SourceSelection

    var body: some View {
        List(items, selection: $selection.key) { item in
            Text(item.label)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(item.key)
        }
        .listStyle(.bordered)
    }
}
