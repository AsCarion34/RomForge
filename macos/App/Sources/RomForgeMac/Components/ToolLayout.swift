import SwiftUI

/// 도구 화면 공통 틀: [본문] / [옵션] / [로그]. upstream 탭 대부분이 이 배치다.
struct ToolLayout<Main: View, Options: View>: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject?
    /// 화면이 열릴 때 구독할 컬렉션 속성(목록·로그)
    var lists: [String] = ["FileItems", "LogEntries"]
    var logs: String? = "LogEntries"
    @ViewBuilder var main: Main
    @ViewBuilder var options: Options

    var body: some View {
        VStack(spacing: 0) {
            main
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            let optionsView = options
            if !(optionsView is EmptyView) {
                Divider()
                optionsView
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }

            if let logs, vm?.ref(logs) != nil {
                Divider()
                LogListView(listId: vm?.ref(logs), owner: vm?.has("ClearLog") == true ? vm?.id : nil)
                    .frame(minHeight: 100, idealHeight: 150, maxHeight: 240)
            }
        }
        .observeLists(engine, vm, lists)
    }
}

extension ToolLayout where Options == EmptyView {
    init(vm: RemoteObject?, lists: [String] = ["FileItems", "LogEntries"], logs: String? = "LogEntries", @ViewBuilder main: () -> Main) {
        self.vm = vm
        self.lists = lists
        self.logs = logs
        self.main = main()
        self.options = EmptyView()
    }
}

extension View {
    /// 화면이 열릴 때 ViewModel의 컬렉션 속성들을 구독한다(항목 속성까지 받아 둔다).
    func observeLists(_ engine: EngineClient, _ vm: RemoteObject?, _ lists: [String]) -> some View {
        task(id: vm?.id) {
            for list in lists {
                await engine.observeList(vm?.ref(list))
            }
        }
    }
}
