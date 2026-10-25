import SwiftUI

/// 경로 TextBox(Text="{Binding prop, UpdateSourceTrigger=PropertyChanged}").
/// 값이 비었을 때 보이던 안내(…HintVisibility)는 입력란 안내 문구(placeholder)로 보인다. pathTooltip이면 경로를 툴팁으로도 보인다.
struct PathField: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject?
    var prop = "OutputPath"
    var placeholder = ""
    var pathTooltip = false

    var body: some View {
        TextField(placeholder, text: engine.string(vm, prop))
            .textFieldStyle(.roundedBorder)
            .help(pathTooltip ? vm?.string(prop) ?? "" : "")
    }
}

/// 출력(작업) 폴더 줄(upstream: TextBox(AllowDrop, TxtOutputPath_PreviewDragOver / TxtOutputPath_Drop) + AddFolder.png 버튼).
/// 입력란에 폴더를 끌어다 놓으면 prop에 넣고, 버튼은 browseCommand를 실행한다(CanExecute를 따른다).
struct FolderPathRow: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject
    var prop = "OutputPath"
    let placeholder: String
    var browseCommand = "BrowseOutputCommand"
    /// false면 드롭을 받지 않는다(TextBox가 IsEnabled=false일 때)
    var dropEnabled = true

    var body: some View {
        HStack(spacing: 5) {
            PathField(vm: vm, prop: prop, placeholder: placeholder)
                .folderDrop(engine, vm, prop, enabled: dropEnabled)
            ToolIconButton(icon: "AddFolder.png", enabled: engine.canRun(vm, browseCommand)) {
                engine.run(vm, browseCommand)
            }
        }
    }
}

/// TextBox Text="{Binding Prop, UpdateSourceTrigger=PropertyChanged}"(MaxLength 선택).
/// 입력할 때마다 ViewModel에 보내되, 엔진이 늦게 돌려주는 이전 값(내가 보낸 값의 메아리)으로 입력 중인 글자를 덮어쓰지 않는다.
/// 드롭·찾아보기처럼 ViewModel이 다른 값으로 바뀌면 바로 따른다.
struct LiveTextField: View {
    @Environment(EngineClient.self) private var engine
    let title: String
    let vm: RemoteObject
    let prop: String
    var maxLength: Int?

    @State private var text = ""
    @State private var sent: [String] = []

    var body: some View {
        TextField(title, text: $text)
            .onAppear(perform: reload)
            .onChange(of: vm.id) { _, _ in reload() }
            .onChange(of: text) { _, value in
                if let maxLength, value.utf16.count > maxLength {
                    var limited = value
                    while limited.utf16.count > maxLength { limited.removeLast() }
                    text = limited
                    return
                }
                // 아직 돌아오지 않은 마지막 값(없으면 ViewModel 값)과 같으면 보낼 것이 없다.
                guard value != (sent.last ?? vm.string(prop)) else { return }
                sent.append(value)
                let id = vm.id, prop = prop
                Task { await engine.set(id, prop, .string(value)) }
            }
            .onChange(of: vm.string(prop)) { _, value in
                if let index = sent.lastIndex(of: value) {
                    // 내가 보낸 값이 돌아왔다. 그보다 앞서 보낸 값은 더 기다리지 않는다.
                    sent.removeFirst(index + 1)
                    if sent.isEmpty, value != text { text = value }
                    return
                }
                // 드롭·찾아보기 등 ViewModel 쪽 변경
                sent.removeAll()
                if value != text { text = value }
            }
    }

    private func reload() {
        sent.removeAll()
        text = vm.string(prop)
    }
}

/// 읽기 전용 TextBox(IsReadOnly=True): 선택·복사만 된다.
struct ReadOnlyField: View {
    let text: String

    var body: some View {
        Text(text.isEmpty ? " " : text)
            .textSelection(.enabled)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.4)))
    }
}

extension View {
    /// 폴더 입력란의 AllowDrop + PreviewDragOver / Drop: 끌어다 놓은 첫 항목이 폴더일 때만 받아 perform에 넘긴다.
    /// enabled가 false면(TextBox가 IsEnabled=false일 때) 받지 않는다.
    func folderDrop(enabled: Bool = true, perform: @escaping (String) -> Void) -> some View {
        dropDestination(for: URL.self) { urls, _ in
            guard enabled, let folder = FilePanels.droppedFolder(urls) else { return false }
            perform(folder)
            return true
        }
    }

    /// 끌어다 놓은 폴더를 ViewModel 경로 속성(prop)에 넣는다.
    func folderDrop(_ engine: EngineClient, _ vm: RemoteObject?, _ prop: String, enabled: Bool = true) -> some View {
        folderDrop(enabled: enabled) { engine.string(vm, prop).wrappedValue = $0 }
    }
}
