// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

extension DSHClient {
    /// A typed consumer owns the mux stream task and cancels it on termination.
    func domainStream<Value>(_ endpoint: String, _ args: [String: Any] = [:],
                             decode: @escaping @Sendable ([String: Any]) -> Value) async throws -> AsyncThrowingStream<Value, Error> {
        let frames = try await muxConnection().open(endpoint: endpoint, args: args).1
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await frame in frames { continuation.yield(decode(frame.value)) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
