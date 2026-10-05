import Foundation

/// 엔진과 주고받는 JSON 값. 엔진 쪽 인코딩 규칙은 macos/Engine/Bridge/ValueCodec.cs 참고.
enum JSONValue: Codable, Equatable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var string: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.rounded() == n ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    var double: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    var int: Int? { double.map { Int($0) } }

    var bool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var array: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// {"$obj":1}, {"$list":2}, {"$cmd":3}, {"$image":4} 같은 참조의 번호.
    var refId: Int? {
        for key in ["$obj", "$list", "$cmd", "$image"] {
            if let id = self[key]?.int { return id }
        }
        return nil
    }

    static func int(_ value: Int) -> JSONValue { .number(Double(value)) }

    static func strings(_ values: [String]) -> JSONValue { .array(values.map { .string($0) }) }
}
