import SwiftUI

/// upstream ViewModel의 LogEntries(ObservableCollection&lt;LogEntry&gt;)를 보여 준다.
struct LogListView: View {
    @Environment(EngineClient.self) private var engine
    let listId: Int?

    private var entries: [RemoteObject] {
        engine.store.items(listId).compactMap { engine.store.object($0.refId) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List(entries) { entry in
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
            .onChange(of: entries.count) { _, _ in
                if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private func color(for level: String) -> Color {
        switch level {
        case "Highlight": .blue
        case "Ok": .green
        case "Error": .red
        default: .primary
        }
    }
}
