// upstream: RomForge/Controls/WiiU/RepackTab.xaml(.cs), RomForge/Controls/WiiU/ConverterTab.xaml(.cs)
// ViewModel: WiiUMainViewModel 하위 탭 공용 보조 뷰(배지 · 타이틀 칸 · 출력 형식 콤보)
import SwiftUI

// MARK: - 보조 뷰

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
