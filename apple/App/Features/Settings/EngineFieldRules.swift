// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/engine_settings/{schema_fields,schema_collapsed_groups,schema_documentation,numeric_edit_math,namespace_copy}.dart.
import DSHClient
import CoreFoundation
import Foundation

/// A Schemastery field retains its host-defined document and typed metadata.
struct EngineFieldRules {
    let schema: EngineSchema
    let node: [String: Any]
    var type: String { node["type"] as? String ?? "" }
    var meta: [String: Any] { node["meta"] as? [String: Any] ?? [:] }
    var role: String? { meta["role"] as? String }
    var choices: [Any]? { schema.constants(node) }
    var bits: [String: Int] { node["bits"] as? [String: Int] ?? [:] }
    var title: String? { EngineSchema.localized(meta["title"]) }
    var description: String? { EngineSchema.localized(meta["description"]) }
    var minimum: Double? { (meta["min"] as? NSNumber)?.doubleValue }
    var maximum: Double? { (meta["max"] as? NSNumber)?.doubleValue }
    var step: Double? { (meta["step"] as? NSNumber)?.doubleValue }
    var locked: Bool { meta["disabled"] as? Bool == true || meta["locked"] as? Bool == true }
    var hidden: Bool { meta["hidden"] as? Bool == true || role == "credential-ref" || type == "const" }
    var secret: Bool { role == "secret" }
    var group: Bool { ["object", "intersect"].contains(type) }
    var collection: Bool { ["array", "dict", "tuple"].contains(type) }
    var collapsed: Bool { meta["collapse"] as? Bool == true }
    var inner: [String: Any] { schema.effective(schema.resolve(node["inner"] ?? [:])) }

    func containsSecret(depth: Int = 0) -> Bool {
        if depth >= 16 { return true }
        if secret { return true }
        var children = Array((node["dict"] as? [String: Any] ?? [:]).values)
        children += node["list"] as? [Any] ?? []
        if let inner = node["inner"] { children.append(inner) }
        return children.contains {
            EngineFieldRules(schema: schema, node: schema.effective(schema.resolve($0))).containsSecret(depth: depth + 1)
        }
    }

    func valid(_ value: Any, depth: Int = 0) -> Bool {
        guard depth < 16 else { return false }
        if value is NSNull, meta["nullable"] as? Bool == true { return true }
        if let choices { return choices.contains { engineValueEqual($0, value) } }
        switch type {
        case "boolean":
            guard let boolean = value as? NSNumber else { return false }
            return CFGetTypeID(boolean) == CFBooleanGetTypeID()
        case "number", "bitset":
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
            let n = number.doubleValue
            guard n.isFinite, type != "bitset" || Int(exactly: n) != nil,
                  minimum.map({ n >= $0 }) ?? true, maximum.map({ n <= $0 }) ?? true else { return false }
            guard let step, step.isFinite, step > 0 else { return true }
            let count = (n - (minimum ?? 0)) / step
            return abs(count - count.rounded()) < 0.000001
        case "string":
            guard let text = value as? String, validCount(text.utf16.count),
                  !(meta["required"] as? Bool == true && text.isEmpty) else { return false }
            guard let pattern = meta["pattern"] as? [String: String], let source = pattern["source"] else { return true }
            let flags = pattern["flags"] ?? ""
            var options: NSRegularExpression.Options = []
            if flags.contains("i") { options.insert(.caseInsensitive) }
            if flags.contains("m") { options.insert(.anchorsMatchLines) }
            if flags.contains("s") { options.insert(.dotMatchesLineSeparators) }
            // The host is authoritative for JavaScript-only patterns.
            guard let regex = try? NSRegularExpression(pattern: source, options: options) else { return true }
            return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        case "array":
            guard let list = value as? [Any], validCount(list.count) else { return false }
            let child = EngineFieldRules(schema: schema, node: inner)
            return list.allSatisfy { child.valid($0, depth: depth + 1) }
        case "tuple":
            let list = node["list"] as? [Any] ?? []
            guard let values = value as? [Any], values.count == list.count else { return false }
            return zip(list, values).allSatisfy {
                EngineFieldRules(schema: schema, node: schema.effective(schema.resolve($0.0))).valid($0.1, depth: depth + 1)
            }
        case "dict":
            guard let map = value as? [String: Any], validCount(map.count) else { return false }
            let child = EngineFieldRules(schema: schema, node: inner)
            return map.values.allSatisfy { child.valid($0, depth: depth + 1) }
        case "object", "intersect":
            guard let map = value as? [String: Any] else { return false }
            return schema.fields(node).allSatisfy { key, child in
                let rules = EngineFieldRules(schema: schema, node: child)
                if rules.hidden || rules.locked || rules.secret { return true }
                guard let item = map[key] else { return rules.meta["required"] as? Bool != true }
                return rules.valid(item, depth: depth + 1)
            }
        case "union":
            return (node["list"] as? [Any] ?? []).contains {
                EngineFieldRules(schema: schema, node: schema.effective(schema.resolve($0))).valid(value, depth: depth + 1)
            }
        case "any":
            return true
        default: return false
        }
    }

    private func validCount(_ count: Int) -> Bool {
        (minimum.map { Double(count) >= $0 } ?? true) && (maximum.map { Double(count) <= $0 } ?? true)
    }
}

func engineValueEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): return true
    case (let a?, let b?):
        let options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .sortedKeys]
        guard let a = try? JSONSerialization.data(withJSONObject: a, options: options),
              let b = try? JSONSerialization.data(withJSONObject: b, options: options) else { return false }
        return a == b
    default: return false
    }
}

func engineValue(_ path: [String], in root: Any?) -> Any? {
    path.reduce(root) { current, key in
        if let map = current as? [String: Any] { return map[key] }
        if let list = current as? [Any], let index = Int(key), list.indices.contains(index) { return list[index] }
        return nil
    }
}

func mediaCatalog(in section: EngineNamespace) -> [String: Any]? {
    let schema = EngineSchema(section.schema)
    let services = schema.fields(schema.root)["services"]
    let extra = (services?["meta"] as? [String: Any])?["extra"] as? [String: Any]
    // Older remote Hosts may still publish the DSH Go key.
    return (extra?["dsh-fan/media/catalog"] ?? extra?["dsh-go/media/catalog"]) as? [String: Any]
}
