import SwiftUI

/// 전용 macOS 화면이 아직 없는 ViewModel을 위한 자동 생성 화면.
/// upstream ViewModel의 속성을 보고 만든다(bool → 토글, 문자열·숫자 → 입력, enum → 선택, ICommand → 버튼,
/// 객체 컬렉션 → 표, LogEntries → 로그). upstream에 새 탭·옵션이 생겨도 일단 이 화면으로 쓸 수 있다.
struct GenericVMForm: View {
    @Environment(EngineClient.self) private var engine
    let vmId: Int

    private static let hidden: Set<String> = [
        "IsLocked", "IsUnlocked", "IsIdle", "Tools", "LogEntries", "ActiveLogEntries",
        "TaskbarProgressValue", "TaskbarProgressState", "SelectedViewModel", "AppVersion", "LogBoxHeight",
    ]

    var body: some View {
        ChildVM(id: vmId) { vm in
            ToolLayout(vm: vm, lists: collectionProps(vm) + ["LogEntries"]) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        let commands = commandProps(vm)
                        if !commands.isEmpty {
                            HStack {
                                ForEach(commands, id: \.self) { name in
                                    CommandButton(title: Self.title(name), vm: vm, command: name)
                                }
                            }
                        }

                        ForEach(collectionProps(vm), id: \.self) { name in
                            GenericCollection(owner: vm, list: name)
                                .frame(minHeight: 160, maxHeight: 320)
                        }

                        let editable = editableProps(vm)
                        if !editable.isEmpty {
                            OptionCard(title: "옵션") {
                                ForEach(editable, id: \.self) { name in
                                    editor(vm, name)
                                }
                            }
                        }

                        ForEach(childViewModels(vm), id: \.self) { name in
                            if let child = vm.ref(name) {
                                DisclosureGroup(Self.title(name)) {
                                    GenericVMForm(vmId: child).frame(minHeight: 300)
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    @ViewBuilder
    private func editor(_ vm: RemoteObject, _ name: String) -> some View {
        let type = vm.types[name] ?? ""
        switch type {
        case "Boolean":
            Toggle(Self.title(name), isOn: engine.bool(vm, name))
        case "enum":
            HStack {
                Text(Self.title(name)).frame(width: 180, alignment: .leading)
                EnumPicker(vm: vm, prop: name, style: .menu)
            }
        case "Int32", "Int64", "Double", "Single", "Byte", "UInt32":
            HStack {
                Text(Self.title(name)).frame(width: 180, alignment: .leading)
                TextField("", value: engine.double(vm, name), format: .number).frame(maxWidth: 120)
            }
        default:
            HStack {
                Text(Self.title(name)).frame(width: 180, alignment: .leading)
                TextField("", text: engine.string(vm, name))
            }
        }
    }

    private func editableProps(_ vm: RemoteObject) -> [String] {
        vm.settable.filter { name in
            guard !Self.hidden.contains(name), let type = vm.types[name] else { return false }
            if type == "enum" { return !(vm.options(name).contains("Collapsed")) }
            return ["Boolean", "String", "Int32", "Int64", "Double", "Single", "Byte", "UInt32"].contains(type)
        }
        .sorted()
    }

    private func commandProps(_ vm: RemoteObject) -> [String] {
        vm.props.filter { $0.value["$cmd"] != nil }.map(\.key).sorted()
    }

    private func collectionProps(_ vm: RemoteObject) -> [String] {
        vm.props.filter { $0.value["$list"] != nil && !Self.hidden.contains($0.key) && vm.types[$0.key]?.hasPrefix("ObservableCollection") == true }
            .map(\.key).sorted()
    }

    private func childViewModels(_ vm: RemoteObject) -> [String] {
        vm.props.filter { $0.value["$obj"] != nil && ($0.value["type"]?.string ?? "").hasSuffix("ViewModel") && !Self.hidden.contains($0.key) }
            .map(\.key).sorted()
    }

    /// "UseCustomOutputPath" → "Use Custom Output Path"
    static func title(_ name: String) -> String {
        let base = name.hasSuffix("Command") ? String(name.dropLast(7)) : name
        return base.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
    }
}

/// 객체 컬렉션을 표로(첫 항목의 속성에서 열을 고른다)
private struct GenericCollection: View {
    @Environment(EngineClient.self) private var engine
    let owner: RemoteObject
    let list: String
    @State private var selection = Set<Int>()

    private static let preferred = ["FileName", "Title", "Name", "TitleId", "Extension", "FileSize", "Size", "Version", "Status", "Progress"]

    var body: some View {
        let items = engine.items(owner, list)
        let columns = columns(items.first)

        VStack(alignment: .leading, spacing: 4) {
            Text(GenericVMForm.title(list)).font(.caption).foregroundStyle(.secondary)
            Table(items, selection: $selection) {
                TableColumn(columns.indices.contains(0) ? columns[0] : "항목") { item in
                    Text(columns.indices.contains(0) ? item.string(columns[0]) : item.type)
                }
                TableColumn(columns.indices.contains(1) ? columns[1] : "") { item in
                    Text(columns.indices.contains(1) ? item.string(columns[1]) : "")
                }
                TableColumn(columns.indices.contains(2) ? columns[2] : "") { item in
                    Text(columns.indices.contains(2) ? item.string(columns[2]) : "")
                }
                TableColumn("진행률") { item in
                    if item["Progress"] != nil { ProgressCell(item: item) }
                }
            }
            .remoteFileList(engine, owner: owner, list: list, selection: $selection,
                            dropMethod: owner.has("AddPaths") ? "AddPaths" : (owner.has("AddFiles") ? "AddFiles" : nil))
        }
    }

    private func columns(_ sample: RemoteObject?) -> [String] {
        guard let sample else { return ["FileName", "Status"] }
        let primitive = sample.props.filter { $0.value["$obj"] == nil && $0.value["$list"] == nil && $0.value["$cmd"] == nil && $0.value["$image"] == nil && $0.value["$color"] == nil }.map(\.key)
        let ordered = Self.preferred.filter(primitive.contains) + primitive.sorted().filter { !Self.preferred.contains($0) }
        return Array(ordered.prefix(3))
    }
}
