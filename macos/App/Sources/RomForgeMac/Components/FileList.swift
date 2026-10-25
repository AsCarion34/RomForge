import AppKit
import SwiftUI

/// 파일 목록(upstream ListView + code-behind의 드롭·삭제·폴더 열기)을 SwiftUI Table에 붙이는 동작.
///   Table(...) { ... }
///       .remoteFileList(engine, owner: vm, list: "FileItems", selection: $selection)
/// - 드롭: owner의 dropMethod(기본 AddPaths)로 경로 배열을 넘긴다.
/// - Delete 키·"선택 삭제": owner의 removeMethod(기본 RemoveItems)에 선택 항목을 넘긴다.
///   메서드가 없으면 컬렉션의 Remove를 항목마다 부른다(upstream code-behind와 같은 결과).
/// - "전체 삭제": owner의 clearMethod(기본 ClearItems), 없으면 컬렉션의 Clear.
/// - "폴더 열기": 항목의 pathProp(기본 FilePath) 위치를 Finder에서 연다.
/// 메뉴 문구는 upstream ListView ContextMenu와 같다.
struct RemoteFileListModifier: ViewModifier {
    let engine: EngineClient
    let owner: RemoteObject?
    let list: String
    @Binding var selection: Set<Int>
    var dropMethod: String? = "AddPaths"
    var removeMethod: String? = "RemoveItems"
    var clearMethod: String? = "ClearItems"
    var pathProp: String = "FilePath"
    var enabled: Bool = true

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                guard enabled, let dropMethod, let owner else { return false }
                engine.invoke(owner, dropMethod, [.strings(urls.map(\.path))])
                return true
            }
            .onDeleteCommand { removeSelected() }
            .contextMenu(forSelectionType: Int.self) { ids in
                if !ids.isEmpty {
                    Button("폴더 열기") { reveal(ids) }
                    Divider()
                    Button("선택 삭제", role: .destructive) {
                        selection = ids
                        removeSelected()
                    }
                    .disabled(!enabled)
                    Button("전체 삭제", role: .destructive) { clearAll() }
                        .disabled(!enabled)
                }
            }
    }

    private func removeSelected() {
        guard enabled, !selection.isEmpty, let owner else { return }
        let ids = Array(selection)

        if let removeMethod, owner.has(removeMethod) {
            engine.invoke(owner, removeMethod, [EngineClient.refs(ids)])
        } else if let listId = owner.ref(list) {
            for id in ids {
                Task { await engine.call(listId, "Remove", [.object(["$obj": .int(id)])]) }
            }
        }
        selection.removeAll()
    }

    private func clearAll() {
        guard enabled, let owner else { return }

        if let clearMethod, owner.has(clearMethod) {
            engine.invoke(owner, clearMethod)
        } else if let listId = owner.ref(list) {
            Task { await engine.call(listId, "Clear") }
        }
        selection.removeAll()
    }

    private func reveal(_ ids: Set<Int>) {
        let urls = ids.compactMap { engine.store.object($0)?.string(pathProp) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
}

extension View {
    func remoteFileList(_ engine: EngineClient, owner: RemoteObject?, list: String, selection: Binding<Set<Int>>,
                        dropMethod: String? = "AddPaths", removeMethod: String? = "RemoveItems",
                        clearMethod: String? = "ClearItems",
                        pathProp: String = "FilePath", enabled: Bool = true) -> some View {
        modifier(RemoteFileListModifier(engine: engine, owner: owner, list: list, selection: selection,
                                        dropMethod: dropMethod, removeMethod: removeMethod, clearMethod: clearMethod,
                                        pathProp: pathProp, enabled: enabled))
    }
}

/// 목록 항목 객체들(이미 describe된 것만)
@MainActor
extension EngineClient {
    func items(_ owner: RemoteObject?, _ list: String) -> [RemoteObject] {
        store.items(owner?.ref(list)).compactMap { store.object($0.refId) }
    }
}

// MARK: - 정렬

/// ListViewColumnSorter(GridViewColumnHeader_Click) 자리: 머리글 Tag 속성 값으로 화면 목록만 정렬한다(ViewModel 순서는 그대로).
///   @State private var sortOrder: [ColumnSort] = []
///   Table(ColumnSort.sorted(items, by: sortOrder), selection: $selection, sortOrder: $sortOrder) {
///       TableColumn("용량", sortUsing: ColumnSort("FileSizeBytes")) { ... }
/// 숫자는 크기로, 나머지는 글자로 비교한다. 글자는 upstream CollectionView처럼 지역 설정의 사전 순서(localizedCompare)이고,
/// natural이면 Finder처럼 글자 속 숫자를 크기로 본다(localizedStandardCompare: "2" < "10").
struct ColumnSort: SortComparator {
    let prop: String
    var natural = false
    var order: SortOrder = .forward

    init(_ prop: String, natural: Bool = false) {
        self.prop = prop
        self.natural = natural
    }

    func compare(_ lhs: RemoteObject, _ rhs: RemoteObject) -> ComparisonResult {
        // 표 정렬은 화면(메인 스레드)에서만 한다.
        let result = MainActor.assumeIsolated { compareValues(lhs[prop], rhs[prop]) }

        guard order == .reverse else { return result }
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    private func compareValues(_ a: JSONValue?, _ b: JSONValue?) -> ComparisonResult {
        if let x = a?.double, let y = b?.double {
            return x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
        }
        let textA = a?.string ?? "", textB = b?.string ?? ""
        return natural ? textA.localizedStandardCompare(textB) : textA.localizedCompare(textB)
    }

    /// 정렬 기준이 없으면 ViewModel 순서 그대로 둔다.
    static func sorted(_ items: [RemoteObject], by order: [ColumnSort]) -> [RemoteObject] {
        order.isEmpty ? items : items.sorted(using: order)
    }
}

// MARK: - 셀

/// 확장자 배지(upstream ExtensionColorMap 색). 글자는 upstream처럼 ViewModel 값 그대로 쓴다.
struct ExtensionBadge: View {
    let item: RemoteObject
    var textProp = "Extension"
    var colorProp = "ExtensionBackground"

    var body: some View {
        let hex = item[colorProp]?["$color"]?.string
        Text(item.string(textProp))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color(hex: hex).opacity(0.85), in: Capsule())
            .foregroundStyle(Color.isLight(hex: hex) ? .black : .white)
    }
}

/// 0~100 진행률 막대
struct ProgressCell: View {
    let item: RemoteObject
    var prop = "Progress"

    var body: some View {
        ProgressView(value: min(max((item[prop]?.double ?? 0) / 100, 0), 1))
    }
}

/// 빈 목록 안내(upstream HintVisibility 문구 자리)
struct DropHint: View {
    let title: String
    var detail: String? = nil
    var systemImage = "tray.and.arrow.down"

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: detail.map { Text($0) })
    }
}
