// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Display-safe settings returned by the engine. Secret values are never read.
public struct EngineNamespace: Identifiable {
    public let id: String
    public let revision: Int
    public let writable: Bool
    public let value: [String: Any]
    public let schema: [String: Any]
    public let secretPaths: [[String]]
    public init(_ map: [String: Any], writable: Bool = true) {
        id = map["ns"] as? String ?? ""
        revision = map["revision"] as? Int ?? 0
        self.writable = writable
        value = map["value"] as? [String: Any] ?? [:]
        schema = map["schema"] as? [String: Any] ?? [:]
        secretPaths = (map["secrets"] as? [[String: Any]] ?? []).filter { $0["set"] as? Bool == true }.compactMap { $0["path"] as? [String] }
    }
    public static func parse(_ response: Any?) -> [EngineNamespace] {
        let envelope = response as? [String: Any] ?? [:]
        return (envelope["namespaces"] as? [[String: Any]] ?? []).map { EngineNamespace($0, writable: envelope["writable"] as? Bool != false) }
    }
}

/// Schemastery references are resolved on demand with bounded wrapper traversal.
public struct EngineSchema {
    let document: [String: Any]
    public init(_ document: [String: Any]) { self.document = document }
    public var root: [String: Any] { resolve(document["uid"] ?? document) }
    public func resolve(_ reference: Any) -> [String: Any] {
        if let node = reference as? [String: Any] { return node }
        let key = String(describing: reference)
        return (document["refs"] as? [String: [String: Any]])?[key] ?? [:]
    }
    public func effective(_ raw: [String: Any]) -> [String: Any] {
        var node = raw, meta = raw["meta"] as? [String: Any] ?? [:]
        for _ in 0..<8 {
            if node["type"] as? String == "union" {
                let members = (node["list"] as? [Any] ?? []).map(resolve).filter { !(($0["type"] as? String == "const") && ($0["value"] == nil || $0["value"] is NSNull)) }
                guard members.count == 1, members[0]["type"] as? String != "const" else { break }
                node = members[0]
            } else {
                guard ["transform", "lazy"].contains(node["type"] as? String ?? ""), let inner = node["inner"] else { break }
                node = resolve(inner)
            }
            meta.merge(node["meta"] as? [String: Any] ?? [:]) { old, _ in old }
        }
        node["meta"] = meta
        return node
    }
    public func fields(_ raw: [String: Any], depth: Int = 0) -> [String: [String: Any]] {
        guard depth < 12 else { return [:] }
        let node = effective(raw)
        if node["type"] as? String == "intersect" {
            return (node["list"] as? [Any] ?? []).reduce(into: [:]) { result, ref in
                result.merge(fields(resolve(ref), depth: depth + 1)) { _, new in new }
            }
        }
        return (node["dict"] as? [String: Any] ?? [:]).mapValues { effective(resolve($0)) }
    }
    public func constants(_ raw: [String: Any]) -> [Any]? {
        let node = effective(raw), type = node["type"] as? String
        if type == "const" { return [node["value"] ?? NSNull()] }
        guard type == "union" else { return nil }
        let members = (node["list"] as? [Any] ?? []).map { effective(resolve($0)) }
        guard !members.isEmpty, members.allSatisfy({ $0["type"] as? String == "const" }) else { return nil }
        return members.map { $0["value"] ?? NSNull() }
    }
    public func defaultValue(_ raw: [String: Any], depth: Int = 0) -> Any {
        guard depth < 8 else { return NSNull() }
        let node = effective(raw)
        if let value = (node["meta"] as? [String: Any])?["default"] { return value }
        if let first = constants(node)?.first { return first }
        switch node["type"] as? String {
        case "object", "intersect": return fields(node).mapValues { defaultValue($0, depth: depth + 1) }
        case "dict": return [String: Any]()
        case "array": return [Any]()
        case "boolean": return false
        case "number": return 0
        default: return ""
        }
    }
    public static func localized(_ raw: Any?) -> String? {
        if let text = raw as? String { return text }
        guard let map = raw as? [String: String] else { return nil }
        let language = Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh" : "en"
        return map[language] ?? map.first { $0.key.lowercased().hasPrefix(language) }?.value ?? map["en"] ?? map[""] ?? map.values.first
    }
}
