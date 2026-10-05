import SwiftUI

/// 하위 탭 하나: 제목, upstream 아이콘, 부모 ViewModel에서 하위 ViewModel을 가리키는 속성
struct SubTab: Identifiable {
    let title: String
    var icon: String? = nil
    let vmProp: String
    var id: String { vmProp }
}

/// upstream TabControl(하위 탭) 자리. 선택을 부모 ViewModel의 selectionProp(기본 SelectedTabIndex)에 맞춘다.
/// upstream 로직(예: RunCommand가 선택된 하위 탭에 적용)이 선택 상태에 의존하기 때문이다.
struct SubTabsView<Content: View>: View {
    @Environment(EngineClient.self) private var engine
    let owner: RemoteObject?
    let tabs: [SubTab]
    var selectionProp: String? = "SelectedTabIndex"
    /// 이 속성이 false면 하위 탭을 바꿀 수 없다(upstream TabItem IsEnabled="{Binding IsIdle}" 자리)
    var enabledProp: String? = nil
    @ViewBuilder let content: (_ index: Int, _ childId: Int?) -> Content

    @State private var selected = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selected) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    Text(tab.title).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(enabledProp.map { !(owner?[$0]?.bool ?? true) } ?? false)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            let childId = tabs.indices.contains(selected) ? owner?.ref(tabs[selected].vmProp) : nil
            content(selected, childId)
                .id(selected)
                .task(id: childId) { if let childId { await engine.describe(childId) } }
        }
        .onAppear {
            if let selectionProp, let index = owner?[selectionProp]?.int, tabs.indices.contains(index) {
                selected = index
            }
        }
        .onChange(of: selected) { _, index in
            guard let owner, let selectionProp, owner.props[selectionProp] != nil,
                  owner[selectionProp]?.int != index else { return }
            engine.int(owner, selectionProp).wrappedValue = index
        }
        // upstream ViewModel이 하위 탭을 바꾸는 경우(예: 다른 탭의 "설정" 버튼)를 따라간다.
        .onChange(of: selectionProp.flatMap { owner?[$0]?.int }) { _, index in
            if let index, tabs.indices.contains(index), index != selected { selected = index }
        }
    }
}

/// 하위 ViewModel을 describe한 뒤 내용을 그린다.
struct ChildVM<Content: View>: View {
    @Environment(EngineClient.self) private var engine
    let id: Int?
    @ViewBuilder let content: (RemoteObject) -> Content

    var body: some View {
        if let id, let vm = engine.store.object(id) {
            content(vm)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: id) { if let id { await engine.describe(id) } }
        }
    }
}

/// 하위 탭 화면 안쪽의 TabControl 자리(예: SD 굽기의 [굽기 | 저장]).
/// SwiftUI TabView는 macOS에서 탭 머리가 빈 칸으로 그려질 때가 있어 다른 하위 탭과 같은 분할 컨트롤을 쓴다.
struct InnerTabs<Content: View>: View {
    let titles: [String]
    @Binding var selection: Int
    @ViewBuilder let content: (_ index: Int) -> Content

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selection) {
                ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                    Text(title).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.bottom, 6)

            content(selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
