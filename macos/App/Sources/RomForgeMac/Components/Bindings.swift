import SwiftUI

/// upstream ViewModel 속성과 SwiftUI 컨트롤을 잇는 바인딩.
/// 값을 바꾸면 화면에 바로 반영하고(낙관적 갱신) 엔진에 set 요청을 보낸다. 엔진의 changed 알림이 최종값이다.
@MainActor
extension EngineClient {
    func bool(_ obj: RemoteObject?, _ prop: String) -> Binding<Bool> {
        Binding(get: { obj?[prop]?.bool ?? false },
                set: { [weak self] in self?.update(obj, prop, .bool($0)) })
    }

    /// bool 속성을 반대로 보여 준다(XAML의 InverseBool 변환기 자리).
    func inverseBool(_ obj: RemoteObject?, _ prop: String) -> Binding<Bool> {
        Binding(get: { !(obj?[prop]?.bool ?? false) },
                set: { [weak self] in self?.update(obj, prop, .bool(!$0)) })
    }

    func string(_ obj: RemoteObject?, _ prop: String) -> Binding<String> {
        Binding(get: { obj?[prop]?.string ?? "" },
                set: { [weak self] in self?.update(obj, prop, .string($0)) })
    }

    func double(_ obj: RemoteObject?, _ prop: String) -> Binding<Double> {
        Binding(get: { obj?[prop]?.double ?? 0 },
                set: { [weak self] in self?.update(obj, prop, .number($0)) })
    }

    func int(_ obj: RemoteObject?, _ prop: String) -> Binding<Int> {
        Binding(get: { obj?[prop]?.int ?? 0 },
                set: { [weak self] in self?.update(obj, prop, .int($0)) })
    }

    /// enum 속성(이름 문자열). 선택지는 obj.enums[prop].
    func choice(_ obj: RemoteObject?, _ prop: String) -> Binding<String> {
        Binding(get: { obj?[prop]?.string ?? "" },
                set: { [weak self] in self?.update(obj, prop, .string($0)) })
    }

    /// enum 속성이 특정 값인지(XAML의 EnumToBooleanConverter + RadioButton 자리).
    func isChoice(_ obj: RemoteObject?, _ prop: String, _ value: String) -> Binding<Bool> {
        Binding(get: { obj?[prop]?.string == value },
                set: { [weak self] isOn in if isOn { self?.update(obj, prop, .string(value)) } })
    }

    /// 목록 항목 객체를 고르는 속성(SelectedItem 자리). 값은 항목 객체 번호.
    func selectedItem(_ obj: RemoteObject?, _ prop: String) -> Binding<Int?> {
        Binding(get: { obj?[prop]?.refId },
                set: { [weak self] id in
                    self?.update(obj, prop, id.map { .object(["$obj": .int($0)]) } ?? .null)
                })
    }

    private func update(_ obj: RemoteObject?, _ prop: String, _ value: JSONValue) {
        guard let obj else { return }
        obj.props[prop] = value
        store.markLocalEdit(obj.id, prop)
        Task { await set(obj.id, prop, value) }
    }

    // MARK: 커맨드

    func canRun(_ obj: RemoteObject?, _ commandProp: String) -> Bool {
        store.canExecute(obj?.ref(commandProp))
    }

    func run(_ obj: RemoteObject?, _ commandProp: String, _ arg: JSONValue? = nil) {
        guard let cmd = obj?.ref(commandProp) else { return }
        Task { await execute(cmd, arg: arg) }
    }

    /// 공개 메서드 호출(code-behind가 부르던 AddPaths, RemoveItems 등).
    func invoke(_ obj: RemoteObject?, _ method: String, _ args: [JSONValue] = []) {
        guard let obj else { return }
        Task { await call(obj.id, method, args) }
    }

    /// 객체 번호 목록을 메서드 인자로 넘길 때 쓴다.
    static func refs(_ ids: some Sequence<Int>) -> JSONValue {
        .array(ids.map { .object(["$obj": .int($0)]) })
    }

    /// 객체 번호 하나를 인자로 넘길 때 쓴다(컬렉션이면 그 번호를 그대로).
    static func ref(_ id: Int) -> JSONValue { .object(["$obj": .int(id)]) }

    /// upstream 정적 메서드 호출(code-behind가 쓰는 도우미 클래스). type은 짧은 이름이나 전체 이름.
    @discardableResult
    func callStatic(_ type: String, _ method: String, _ args: [JSONValue] = [], options: CallOptions = .none) async -> JSONValue? {
        do {
            return try await callStaticThrowing(type, method, args, options: options)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// upstream 객체 생성(code-behind가 new 하던 도우미). 만든 객체 번호를 돌려준다.
    func create(_ type: String, _ args: [JSONValue] = []) async -> Int? {
        do {
            return try await request("create", ["type": .string(type), "args": .array(args)]).refId
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}

extension RemoteObject {
    /// enum 속성의 선택지
    func options(_ prop: String) -> [String] { enums[prop] ?? [] }

    func has(_ method: String) -> Bool { methods.contains { $0.hasPrefix(method + "(") } }

    /// Visibility 속성이 Visible인지
    func isVisible(_ prop: String) -> Bool { props[prop]?.string == "Visible" }
}
