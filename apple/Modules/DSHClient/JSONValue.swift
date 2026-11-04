// SPDX-License-Identifier: AGPL-3.0-or-later
import CoreFoundation
import Foundation

/// JSON at variable-shape boundaries (tool arguments, asset manifests and diagnostics).
/// Domain RPCs expose their own records rather than asking views to interpret this value.
public enum JSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), integer(Int), number(Double), string(String)
    case array([JSONValue]), object([String: JSONValue])

    public init(_ value: Any?) {
        switch value {
        case let value as String: self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() { self = .bool(value.boolValue) }
            else if let integer = value as? Int { self = .integer(integer) }
            else { self = .number(value.doubleValue) }
        case let value as [String: Any]: self = .object(value.mapValues(JSONValue.init))
        case let value as [Any]: self = .array(value.map(JSONValue.init))
        default: self = .null
        }
    }

    public init(data: Data) throws { self = try JSONDecoder().decode(Self.self, from: data) }
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let v = try? value.decode(Bool.self) { self = .bool(v) }
        else if let v = try? value.decode(Int.self) { self = .integer(v) }
        else if let v = try? value.decode(Double.self) { self = .number(v) }
        else if let v = try? value.decode(String.self) { self = .string(v) }
        else if let v = try? value.decode([Self].self) { self = .array(v) }
        else { self = .object(try value.decode([String: Self].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let v): try value.encode(v)
        case .integer(let v): try value.encode(v)
        case .number(let v): try value.encode(v)
        case .string(let v): try value.encode(v)
        case .array(let v): try value.encode(v)
        case .object(let v): try value.encode(v)
        }
    }

    public func decoded<Value: Decodable>(_ type: Value.Type) -> Value? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Only protocol / SDK adapters and engine-schema forms cross back to Foundation.
    public var foundation: Any {
        switch self {
        case .null: NSNull()
        case .bool(let v): NSNumber(value: v)
        case .integer(let v): NSNumber(value: v)
        case .number(let v): NSNumber(value: v)
        case .string(let v): v
        case .array(let v): v.map(\.foundation)
        case .object(let v): v.mapValues(\.foundation)
        }
    }
    public var string: String? { foundation as? String }
    public var bool: Bool? { foundation as? Bool }
    public var int: Int? { foundation as? Int }
    public var double: Double? { foundation as? Double }
    public var object: [String: Self]? { if case .object(let v) = self { v } else { nil } }
    public var array: [Self]? { if case .array(let v) = self { v } else { nil } }
    public var strings: [String]? { foundation as? [String] }
    public var integers: [Int]? { foundation as? [Int] }
    public subscript(_ key: String) -> Self? { object?[key] }
}

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
                     ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .integer(value) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: Self...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, Self)...) { self = .object(Dictionary(uniqueKeysWithValues: elements)) }
}
