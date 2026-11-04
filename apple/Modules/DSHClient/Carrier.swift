// SPDX-License-Identifier: AGPL-3.0-or-later
// A non-HTTP path to a DSH Host (port of DshCarrier in 原 Flutter 版 dsh_client):
// the ds-harness-remote tunnel implements it in DSHRemote. With a carrier,
// DSHClient sends RPCs and mux streams through it instead of URLSession.
import Foundation

public protocol DSHCarrier: AnyObject, Sendable {
    /// One endpoint call; returns `result.value` or throws `DSHError(code)`.
    func call(_ endpoint: String, args: [String: Any]) async throws -> Any?
    /// A mux link: frames are `{type: item|end|error, streamId, value?|error?}`.
    func openLink(onFrame: @escaping @Sendable ([String: Any]) -> Void,
                  onLost: @escaping @Sendable () -> Void) async throws -> DSHMuxLink
    func close()
}

public protocol DSHMuxLink: AnyObject, Sendable {
    func open(streamId: String, endpoint: String, args: [String: Any])
    func cancel(streamId: String)
    func close()
}
