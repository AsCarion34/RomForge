import Foundation
import Observation

/// 엔진에 있는 객체(upstream ViewModel, 파일 항목 등)의 최신 상태 복사본.
@MainActor
@Observable
final class RemoteObject: Identifiable {
    let id: Int
    var type: String
    var props: [String: JSONValue]
    var settable: Set<String>
    /// enum 속성의 선택지, 공개 메서드("이름(인자수)"), 속성 타입 이름(엔진 describe 결과)
    var enums: [String: [String]] = [:]
    var methods: [String] = []
    var types: [String: String] = [:]

    init(id: Int, type: String, props: [String: JSONValue], settable: Set<String>) {
        self.id = id
        self.type = type
        self.props = props
        self.settable = settable
    }

    subscript(_ name: String) -> JSONValue? { props[name] }

    func string(_ name: String) -> String { props[name]?.string ?? "" }

    func ref(_ name: String) -> Int? { props[name]?.refId }
}

/// 엔진 알림(changed, collection, commands)을 받아 복사본을 갱신한다. SwiftUI는 이 값을 보고 다시 그린다.
@MainActor
@Observable
final class RemoteStore {
    private(set) var objects: [Int: RemoteObject] = [:]
    private(set) var lists: [Int: [JSONValue]] = [:]
    private(set) var commands: [Int: Bool] = [:]

    /// 사용자가 방금 바꾼 속성. 그 직후 엔진이 돌려보내는 이전 값이 입력 중인 글자를 덮지 않게 잠시 무시한다
    /// (빠른 입력·한글 조합 입력 보호).
    private var localEdits: [String: Date] = [:]
    private static let localEditWindow: TimeInterval = 0.6

    func markLocalEdit(_ id: Int, _ prop: String) {
        localEdits["\(id)|\(prop)"] = Date()
    }

    func object(_ id: Int?) -> RemoteObject? { id.flatMap { objects[$0] } }

    func items(_ id: Int?) -> [JSONValue] { id.flatMap { lists[$0] } ?? [] }

    func canExecute(_ id: Int?) -> Bool { id.flatMap { commands[$0] } ?? false }

    @discardableResult
    func applyDescribe(_ value: JSONValue) -> RemoteObject? {
        guard let id = value["obj"]?.int, case .object(let props)? = value["props"] else { return nil }
        let settable = Set(value["settable"]?.array?.compactMap(\.string) ?? [])
        trackCommands(in: props)

        let object = objects[id] ?? RemoteObject(id: id, type: value["type"]?.string ?? "", props: props, settable: settable)
        object.props = props
        object.settable = settable

        if case .object(let enums)? = value["enums"] {
            object.enums = enums.mapValues { $0.array?.compactMap(\.string) ?? [] }
        }
        object.methods = value["methods"]?.array?.compactMap(\.string) ?? object.methods
        if case .object(let types)? = value["types"] {
            object.types = types.compactMapValues(\.string)
        }

        objects[id] = object
        return object
    }

    func applyChanged(_ params: JSONValue) {
        guard let id = params["obj"]?.int, case .object(var changed)? = params["props"], let object = objects[id] else { return }
        trackCommands(in: changed)

        let now = Date()
        for key in changed.keys {
            if let edited = localEdits["\(id)|\(key)"] {
                if now.timeIntervalSince(edited) < Self.localEditWindow {
                    changed.removeValue(forKey: key)
                } else {
                    localEdits.removeValue(forKey: "\(id)|\(key)")
                }
            }
        }
        object.props.merge(changed) { _, new in new }
    }

    func applyCollection(_ params: JSONValue) {
        guard let id = params["obj"]?.int else { return }
        lists[id] = params["items"]?.array ?? []
    }

    func applyCommands(_ params: JSONValue) {
        for update in params["updates"]?.array ?? [] {
            if let id = update["cmd"]?.int, let can = update["canExecute"]?.bool {
                commands[id] = can
            }
        }
    }

    private func trackCommands(in props: [String: JSONValue]) {
        for value in props.values {
            if let id = value["$cmd"]?.int, let can = value["canExecute"]?.bool {
                commands[id] = can
            }
        }
    }
}
