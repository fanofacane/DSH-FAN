// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct AccountClientInfo: Sendable {
    public let version: String, locale: String
    public let timezoneOffsetSeconds: Int
    public init(version: String, locale: String, timezoneOffsetSeconds: Int) {
        self.version = version; self.locale = locale; self.timezoneOffsetSeconds = timezoneOffsetSeconds
    }
    var payload: [String: Any] { ["version": version, "locale": locale, "timezoneOffsetSeconds": timezoneOffsetSeconds] }
}
public struct AccountAttempt: Sendable {
    public let id: String?, phase: String?, authorizeUrl: String?, errorCode: String?
    init(_ row: [String: Any]) {
        id = row["id"] as? String; phase = row["phase"] as? String
        authorizeUrl = row["authorizeUrl"] as? String; errorCode = row["errorCode"] as? String
    }
}
public struct AccountState: Sendable {
    public let status: String?
    public let attempt: AccountAttempt
    public init() { self.init([:]) }
    init(_ row: [String: Any]) { status = row["status"] as? String; attempt = AccountAttempt(row["attempt"] as? [String: Any] ?? [:]) }
}
public struct AccountProfile: Sendable {
    public let name: String?, contact: String?
    public init() { self.init([:]) }
    init(_ row: [String: Any]) { name = row["name"] as? String; contact = row["contact"] as? String }
}
public struct AccountWallet: Sendable {
    public let currency: String?, balance: String?
    public let bonus: Bool
    init(_ row: [String: Any], bonus: Bool = false) {
        currency = row["currency"] as? String; balance = row["balance"] as? String
        self.bonus = bonus || row["bonus"] as? Bool == true
    }
}
/// Account grants remain inside the local engine. SSH is remote even without a carrier.
public struct AccountAPI: Sendable {
    let client: DSHClient
    let isLocal: Bool
    public init(client: DSHClient, isLocal: Bool) { self.client = client; self.isLocal = isLocal }
    private func requireLocal() throws { guard isLocal else { throw DSHError("E_ACCOUNT_LOCAL_ONLY") } }
    public func getState() async throws -> AccountState {
        try requireLocal(); return AccountState(try await client.rpc("account/getState") as? [String: Any] ?? [:])
    }
    public func watch() async throws -> AsyncThrowingStream<AccountState, Error> {
        try requireLocal(); return try await client.domainStream("account/watch", decode: { AccountState($0) })
    }
    public func startSignIn(client info: AccountClientInfo, callbackOrigin: String, loginSource: String = "web") async throws -> AccountState {
        try requireLocal()
        let value = try await client.rpc("account/startSignIn", ["client": info.payload, "callbackOrigin": callbackOrigin, "loginSource": loginSource]) as? [String: Any] ?? [:]
        return AccountState(value)
    }
    public func cancelSignIn(attemptId: String) async throws -> AccountState {
        try requireLocal(); return AccountState(try await client.rpc("account/cancelSignIn", ["attemptId": attemptId]) as? [String: Any] ?? [:])
    }
    public func signOut(client info: AccountClientInfo) async throws -> AccountState {
        try requireLocal(); return AccountState(try await client.rpc("account/signOut", ["client": info.payload]) as? [String: Any] ?? [:])
    }
    public func getProfile(client info: AccountClientInfo) async throws -> AccountProfile {
        try requireLocal()
        let response = try await client.rpc("account/getProfile", ["client": info.payload]) as? [String: Any] ?? [:]
        guard response["status"] as? String == "ready" else { throw DSHError("E_ACCOUNT_PROFILE_UNAVAILABLE") }
        return AccountProfile(response["value"] as? [String: Any] ?? [:])
    }
    public func getBalance(client info: AccountClientInfo) async throws -> [AccountWallet] {
        try requireLocal()
        let response = try await client.rpc("account/getBalance", ["client": info.payload]) as? [String: Any] ?? [:]
        guard response["status"] as? String == "ready" else { throw DSHError("E_ACCOUNT_BALANCE_UNAVAILABLE") }
        return (response["value"] as? [[String: Any]] ?? []).map { AccountWallet($0) }
            + (response["bonusWallets"] as? [[String: Any]] ?? []).map { AccountWallet($0, bonus: true) }
    }
}
