import Foundation

/// upstream code-behind가 ViewModel의 대리자 속성에 넣던 창 띄우는 메서드
/// (예: `NormalVM.RequestSourceSelectionAsync = ShowSourceSelectionDialogAsync`)의 자리.
/// 화면이 bindCallback으로 이름과 처리기를 걸어 두면, upstream이 그 대리자를 부를 때 엔진이 ui.callback {name, args}로 묻는다.
/// 인자는 값으로 펼쳐 온다(목록은 배열, 객체는 공개 속성). 처리기의 반환값은 대리자 반환 타입으로 바뀐다.
@MainActor
enum UiCallbacks {
    private static var handlers: [String: ([JSONValue]) -> JSONValue] = [:]

    static func handle(_ p: JSONValue) -> JSONValue {
        guard let name = p["name"]?.string, let handler = handlers[name] else { return .null }
        return handler(p["args"]?.array ?? [])
    }

    fileprivate static func register(_ name: String, _ handler: @escaping ([JSONValue]) -> JSONValue) {
        handlers[name] = handler
    }
}

@MainActor
extension EngineClient {
    /// obj.prop(Func·Action 대리자)에 앱 처리기를 건다. 이름은 앱 전체에서 하나여야 한다.
    func bindCallback(_ obj: Int?, _ prop: String, name: String, handler: @escaping ([JSONValue]) -> JSONValue) async {
        guard let obj else { return }
        UiCallbacks.register(name, handler)
        do {
            _ = try await request("bindCallback", ["obj": .int(obj), "prop": .string(prop), "name": .string(name)])
        } catch {
            lastError = error.localizedDescription
        }
    }
}
