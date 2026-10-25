import AppKit
import SwiftUI

/// upstream ViewModel의 LogEntries(ObservableCollection&lt;LogEntry&gt;)를 보여 준다.
/// 메뉴는 upstream MainWindow 로그 상자와 같다(선택한 줄이 있을 때만: 로그 비우기 · 로그 복사).
struct LogListView: View {
    @Environment(EngineClient.self) private var engine
    let listId: Int?
    /// 로그를 가진 ViewModel(로그 비우기 = ClearLog()). 없으면 메뉴에 넣지 않는다.
    var owner: Int? = nil

    @State private var selection = Set<Int>()

    private var entries: [RemoteObject] {
        engine.store.items(listId).compactMap { engine.store.object($0.refId) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List(entries, selection: $selection) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.string("FormattedTime"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Text(entry.string("Message"))
                        .foregroundStyle(color(for: entry.string("Level")))
                        .textSelection(.enabled)
                }
                .id(entry.id)
            }
            .listStyle(.plain)
            .contextMenu(forSelectionType: Int.self) { ids in
                if !ids.isEmpty {
                    if owner != nil {
                        Button {
                            selection.removeAll()
                            engine.invoke(engine.store.object(owner), "ClearLog")
                        } label: {
                            IconLabel(title: "로그 비우기", icon: "Clear.png")
                        }
                    }
                    Button {
                        copy(ids)
                    } label: {
                        IconLabel(title: "로그 복사", icon: "Copy.png")
                    }
                }
            }
            .onCopyCommand {
                selectedMessages(selection).isEmpty ? [] : [NSItemProvider(object: selectedMessages(selection) as NSString)]
            }
            .onChange(of: entries.count) { _, _ in
                if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    /// upstream CopyLog_Click: 선택한 줄의 Message를 줄바꿈으로 잇는다(목록 순서).
    private func selectedMessages(_ ids: Set<Int>) -> String {
        entries.filter { ids.contains($0.id) }.map { $0.string("Message") }.joined(separator: "\n")
    }

    private func copy(_ ids: Set<Int>) {
        let text = selectedMessages(ids)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func color(for level: String) -> Color {
        switch level {
        case "Highlight": .blue
        case "Ok": .green
        case "Warning": .orange
        case "Error": .red
        default: .primary
        }
    }
}
