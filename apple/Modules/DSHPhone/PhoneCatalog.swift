// SPDX-License-Identifier: AGPL-3.0-or-later
// The fixed tool catalog. apple/Resources/Phone/phone-ios-tools.json is the single source,
// pinned by SHA-256 (update the hash with any edit). It is served verbatim: names, descriptions and key order enter the model's prompt cache.
import CryptoKit
import Foundation

public struct PhoneCatalog: Sendable {
    public static let sha256 = "ee9227447996bde75770c02a20af4d233626124655b310867930fedac4673636"

    /// The exact JSON array text for `tools/list`.
    public let raw: String
    private let schemas: [String: Schema]

    struct Schema: Sendable {
        let properties: [String: Rule]
        let required: [String]
    }
    struct Rule: Sendable {
        let type: String
        let allowed: [String]?
    }

    public init(raw: String) throws {
        let digest = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        guard digest == Self.sha256 else { throw PhoneError("E_CATALOG_HASH") }
        guard let tools = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]] else {
            throw PhoneError("E_CATALOG_JSON")
        }
        var schemas: [String: Schema] = [:]
        for tool in tools {
            guard let name = tool["name"] as? String, let schema = tool["inputSchema"] as? [String: Any] else { continue }
            var rules: [String: Rule] = [:]
            for (key, value) in schema["properties"] as? [String: [String: Any]] ?? [:] {
                rules[key] = Rule(type: value["type"] as? String ?? "", allowed: value["enum"] as? [String])
            }
            schemas[name] = Schema(properties: rules, required: schema["required"] as? [String] ?? [])
        }
        self.raw = raw
        self.schemas = schemas
    }

    /// Loads the bundled `phone-ios-tools.json`.
    public static func bundled(_ bundle: Bundle = .main) throws -> PhoneCatalog {
        guard let url = bundle.url(forResource: "phone-ios-tools", withExtension: "json") else { throw PhoneError("E_CATALOG_MISSING") }
        return try PhoneCatalog(raw: String(decoding: try Data(contentsOf: url), as: UTF8.self))
    }

    /// Same rules as PhoneIosCatalog.valid in Dart.
    public func valid(_ name: String, _ args: [String: Any]) -> Bool {
        guard let schema = schemas[name] else { return false }
        if args.keys.contains(where: { schema.properties[$0] == nil }) { return false }
        if schema.required.contains(where: { args[$0] == nil }) { return false }
        for (key, value) in args {
            guard let rule = schema.properties[key] else { return false }
            switch rule.type {
            case "string":
                guard let text = value as? String, text.count <= 16384, !text.contains("\0") else { return false }
                if let allowed = rule.allowed, !allowed.contains(text) { return false }
            case "integer":
                guard Self.isInteger(value) else { return false }
            case "number":
                guard let number = value as? NSNumber, !Self.isBool(number), number.doubleValue.isFinite else { return false }
            case "boolean":
                guard let number = value as? NSNumber, Self.isBool(number) else { return false }
            case "array":
                guard let list = value as? [Any], list.count <= 7,
                      list.allSatisfy({ Self.isInteger($0) && (1...7).contains(($0 as! NSNumber).intValue) }) else { return false }
            default:
                return false
            }
        }
        if name == "clipboard" { return (args["set"] is String) != ((args["get"] as? NSNumber).map { Self.isBool($0) && $0.boolValue } ?? false) }
        if name == "open" { return (args["url"] is String) != (args["app"] is String) }
        return true
    }

    static func isBool(_ number: NSNumber) -> Bool { CFGetTypeID(number) == CFBooleanGetTypeID() }
    static func isInteger(_ value: Any) -> Bool {
        guard let number = value as? NSNumber, !isBool(number) else { return false }
        return !["d", "f"].contains(String(cString: number.objCType))
    }
}

public struct PhoneError: Error, Equatable, Sendable {
    public let code: String
    public init(_ code: String) { self.code = code }
}
