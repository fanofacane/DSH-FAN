// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct SettingsAPI: Sendable {
    let client: DSHClient
    public init(client: DSHClient) { self.client = client }
    public func describe() async throws -> [EngineNamespace] { EngineNamespace.parse(try await client.rpc("settings/describe")) }
    /// Engine-defined schema forms intentionally retain their arbitrary fields and values.
    public func mutate(ns: String, expectedRevision: Int, ops: [[String: Any]], writable: Bool = true) async throws -> EngineNamespace {
        let value = try await client.rpc("settings/mutate", ["ns": ns, "expectedRevision": expectedRevision, "ops": ops]) as? [String: Any] ?? [:]
        return EngineNamespace(value, writable: writable)
    }
}
