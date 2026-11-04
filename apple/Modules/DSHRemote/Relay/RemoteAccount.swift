// SPDX-License-Identifier: AGPL-3.0-or-later
// One DSH Remote account on one Server (port of
// 原 Flutter 版 dsh_remote/lib/src/account/remote_account.dart; upstream MIT):
// device identity (X25519), rotating device tokens, Host pins, and opening a
// Host session (relay transport → Noise IK → harness.transport.describe).
// Secrets live only in the Keychain under `dsh_remote.v1.<sha256(origin)[:24]>.*`.
import CryptoKit
import DSHClient
import Foundation
import Security

/// Keychain storage for the account (this device only).
public struct RemoteKeychain: Sendable {
    let service: String
    public init(service: String = "io.github.fanofacane.dsh.remote") { self.service = service }

    func read(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key, kSecReturnData as String: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ key: String, _ value: String?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard let value else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

public struct RemoteUser: Sendable, Equatable {
    public let account: String
    public let deviceId: String
    public let provider: String?
}

public struct RemoteHostInfo: Sendable, Identifiable, Equatable {
    public enum Trust: Sendable { case pinned, unpinned, keyChanged, unknown }
    public let id: String
    /// Untrusted text from the Server.
    public let name: String
    public let platform: String
    public let online: Bool
    public let harnessVersion: String?
    public let pluginVersion: String?
    public let lastSeen: Date?
    public let identityKey: String?
    public let trust: Trust
    /// `ABCD EF01 2345` (48 bits of SHA-256 of the identity key).
    public var fingerprint: String? { identityKey.map { RemoteBytes.formatFingerprint(RemoteBytes.identityFingerprint($0)) } }
}

/// A pending browser sign-in. Open `scanURL`, then await `result`.
public final class RemoteQRLogin: @unchecked Sendable {
    public let scanURL: URL
    public let expiresAt: Date
    public let provider: RemoteLoginProvider
    let task: Task<RemoteUser, Error>
    init(scanURL: URL, expiresAt: Date, provider: RemoteLoginProvider, task: Task<RemoteUser, Error>) {
        self.scanURL = scanURL; self.expiresAt = expiresAt; self.provider = provider; self.task = task
    }
    public var result: RemoteUser { get async throws { try await task.value } }
    public func cancel() { task.cancel() }
}

public actor RemoteAccount {
    public let server: URL
    let api: RemoteServerAPI
    private let keychain: RemoteKeychain
    private let deviceName: String
    private let platform: String
    private let clientVersion: String
    private let scope: String

    private struct Identity: Codable { var v = 1; let deviceId: String; let privateKey: String; let publicKey: String; let name: String; let platform: String }
    private struct Credentials: Codable {
        var v = 1
        let deviceId: String
        let account: String
        let accessToken: String
        let accessTokenExpiresAt: Int
        let refreshToken: String
        let refreshTokenExpiresAt: Int
        var provider: String?
    }
    private struct Pin: Codable { let identityKey: String; let name: String; let pinnedAt: Int }

    private var identity: Identity?
    private var credentials: Credentials?
    private var pins: [String: Pin]?
    private var restored = false
    private var refreshing: Task<String, Error>?

    public init(server: URL, deviceName: String, platform: String = "dsh-app-ios", clientVersion: String,
                keychain: RemoteKeychain = RemoteKeychain()) {
        self.server = server
        api = RemoteServerAPI(server: server)
        self.keychain = keychain
        self.deviceName = String(deviceName.prefix(64))
        self.platform = platform
        self.clientVersion = clientVersion
        let origin = "\(server.scheme!)://\(server.host!)\(server.port.map { ":\($0)" } ?? "")"
        scope = String(SHA256.hash(data: Data(origin.utf8)).map { String(format: "%02x", $0) }.joined().prefix(24))
    }

    private var identityKey: String { "dsh_remote.v1.\(scope).identity" }
    private var credentialsKey: String { "dsh_remote.v1.\(scope).credentials" }
    private var pinsKey: String { "dsh_remote.v1.\(scope).pins" }

    private func restore() {
        guard !restored else { return }
        restored = true
        identity = keychain.read(identityKey).flatMap { try? JSONDecoder().decode(Identity.self, from: Data($0.utf8)) }
        if let saved = keychain.read(credentialsKey).flatMap({ try? JSONDecoder().decode(Credentials.self, from: Data($0.utf8)) }),
           saved.deviceId == identity?.deviceId {
            credentials = saved
        }
    }

    public func currentUser() -> RemoteUser? {
        restore()
        guard let credentials, Double(credentials.refreshTokenExpiresAt) / 1000 > Date().timeIntervalSince1970 + 30 else { return nil }
        return RemoteUser(account: credentials.account, deviceId: credentials.deviceId, provider: credentials.provider)
    }

    // MARK: Sign-in

    public func loginProviders() async throws -> [RemoteLoginProvider] {
        try await guarded { try await self.api.oauthProviders().filter { $0.qrStartPath != nil } }
    }

    public func startQRLogin(_ provider: RemoteLoginProvider) async throws -> RemoteQRLogin {
        let session = try await guarded { try await self.api.startQRLogin(provider) }
        let expires = Date().addingTimeInterval(session.expiresIn)
        let task = Task<RemoteUser, Error> {
            while Date() < expires {
                try Task.checkCancellation()
                let status: RemoteServerAPI.QRStatus
                do { status = try await self.api.pollQRLogin(session.qrId) } catch let error as RemoteAPIError where error.retryable {
                    try await Task.sleep(nanoseconds: 2_000_000_000); continue
                } catch let error as RemoteAPIError { throw error.failure }
                switch status {
                case .pending: try await Task.sleep(nanoseconds: 2_000_000_000)
                case .expired: throw RemoteFailure("LOGIN_EXPIRED", "The sign-in session expired.", retryable: true)
                case .complete(let token):
                    try Task.checkCancellation()
                    let account = try await self.guarded { try await self.api.accountMe(token) }
                    return try await self.register(accountToken: token, account: account, provider: provider.id)
                }
            }
            throw RemoteFailure("LOGIN_EXPIRED", "The sign-in session expired.", retryable: true)
        }
        return RemoteQRLogin(scanURL: session.scanURL, expiresAt: expires, provider: provider, task: task)
    }

    public func login(email: String, password: String) async throws -> RemoteUser {
        let login = try await guarded { try await self.api.login(email: email, password: password) }
        return try await register(accountToken: login.token, account: login.account, provider: "password")
    }

    private func register(accountToken: String, account: String, provider: String?) async throws -> RemoteUser {
        restore()
        var current = ensureIdentity(rotate: false)
        let tokens: RemoteTokens
        do {
            tokens = try await api.registerDevice(descriptor(current), accountToken: accountToken)
        } catch let error as RemoteAPIError where error.code == "DEVICE_REVOKED" || error.code == "PEER_IDENTITY_MISMATCH" {
            current = ensureIdentity(rotate: true)
            tokens = try await guarded { try await self.api.registerDevice(self.descriptor(current), accountToken: accountToken) }
        } catch let error as RemoteAPIError { throw error.failure }
        save(Credentials(deviceId: current.deviceId, account: account, accessToken: tokens.accessToken,
                         accessTokenExpiresAt: Int(tokens.accessExpires.timeIntervalSince1970 * 1000),
                         refreshToken: tokens.refreshToken,
                         refreshTokenExpiresAt: Int(tokens.refreshExpires.timeIntervalSince1970 * 1000), provider: provider))
        return RemoteUser(account: account, deviceId: current.deviceId, provider: provider)
    }

    private func descriptor(_ identity: Identity) -> [String: Any] {
        ["deviceId": identity.deviceId, "name": identity.name, "role": "client", "platform": identity.platform,
         "identityKey": identity.publicKey, "clientVersion": clientVersion]
    }

    private func ensureIdentity(rotate: Bool) -> Identity {
        if let identity, !rotate { return identity }
        let keys = X25519.generate()
        let fresh = Identity(deviceId: RemoteBytes.uuidV7(), privateKey: RemoteBytes.base64URL(keys.privateKey),
                             publicKey: RemoteBytes.base64URL(keys.publicKey), name: deviceName, platform: platform)
        keychain.write(identityKey, String(decoding: (try? JSONEncoder().encode(fresh)) ?? Data(), as: UTF8.self))
        identity = fresh
        credentials = nil
        keychain.write(credentialsKey, nil)
        return fresh
    }

    private func save(_ value: Credentials) {
        keychain.write(credentialsKey, String(decoding: (try? JSONEncoder().encode(value)) ?? Data(), as: UTF8.self))
        credentials = value
    }

    /// Revokes this device on the Server (best effort) and forgets tokens and identity. Pins stay.
    public func logout() async {
        restore()
        if credentials != nil, let token = try? await accessToken() { try? await api.revokeSelf(token) }
        credentials = nil; identity = nil
        keychain.write(credentialsKey, nil)
        keychain.write(identityKey, nil)
    }

    // MARK: Tokens

    func accessToken(forceRefresh: Bool = false) async throws -> String {
        restore()
        guard let current = credentials else {
            throw RemoteFailure("ACCOUNT_AUTH_REQUIRED", "Sign in to the remote Server first.", retryable: false)
        }
        if !forceRefresh, Double(current.accessTokenExpiresAt) / 1000 > Date().timeIntervalSince1970 + 60 { return current.accessToken }
        if let refreshing { return try await refreshing.value }
        let task = Task { try await self.rotate(current) }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    private func rotate(_ current: Credentials) async throws -> String {
        guard Double(current.refreshTokenExpiresAt) / 1000 > Date().timeIntervalSince1970 else {
            dropCredentials()
            throw RemoteFailure("ACCOUNT_AUTH_REQUIRED", "The device sign-in expired; sign in again.", retryable: false)
        }
        do {
            let tokens = try await api.refresh(deviceId: current.deviceId, refreshToken: current.refreshToken)
            save(Credentials(deviceId: current.deviceId, account: current.account, accessToken: tokens.accessToken,
                             accessTokenExpiresAt: Int(tokens.accessExpires.timeIntervalSince1970 * 1000),
                             refreshToken: tokens.refreshToken,
                             refreshTokenExpiresAt: Int(tokens.refreshExpires.timeIntervalSince1970 * 1000), provider: current.provider))
            return tokens.accessToken
        } catch let error as RemoteAPIError {
            if error.retryable || error.code == "CONNECTION_FAILED" || error.code == "RATE_LIMITED" {
                throw RemoteFailure(error.code, error.message, retryable: true)
            }
            dropCredentials()
            throw RemoteFailure("ACCOUNT_AUTH_REQUIRED", "The Server refused the device token (\(error.code)); sign in again.", retryable: false)
        }
    }

    private func dropCredentials() { credentials = nil; keychain.write(credentialsKey, nil) }

    private func withToken<T>(_ action: (String) async throws -> T) async throws -> T {
        do { return try await action(try await accessToken()) } catch let error as RemoteAPIError where error.isAuthFailure {
            return try await action(try await accessToken(forceRefresh: true))
        }
    }

    // MARK: Hosts and pins

    public func listHosts() async throws -> [RemoteHostInfo] {
        try await guarded {
            let listings = try await self.withToken { try await self.api.listHosts($0) }
            let pins = self.loadPins()
            var out: [RemoteHostInfo] = []
            for listing in listings {
                let peer = try? await self.withToken { try await self.api.device($0, listing.deviceId) }
                let key = peer.flatMap { $0.role == "host" && RemoteBytes.isIdentityKey($0.identityKey) ? $0.identityKey : nil }
                let pin = pins[listing.deviceId]
                let trust: RemoteHostInfo.Trust = key == nil ? .unknown : pin == nil ? .unpinned : pin!.identityKey == key ? .pinned : .keyChanged
                out.append(RemoteHostInfo(id: listing.deviceId, name: listing.name, platform: listing.platform,
                                          online: peer?.online ?? listing.online,
                                          harnessVersion: listing.harnessVersion ?? peer?.harnessVersion,
                                          pluginVersion: listing.clientVersion ?? peer?.clientVersion,
                                          lastSeen: listing.lastSeen, identityKey: key, trust: trust))
            }
            return out
        }
    }

    public func forgetHost(_ id: String) {
        var pins = loadPins()
        if pins.removeValue(forKey: id) != nil { savePins(pins) }
    }

    private func loadPins() -> [String: Pin] {
        if let pins { return pins }
        struct File: Codable { var v = 1; var hosts: [String: Pin] }
        let loaded = keychain.read(pinsKey).flatMap { try? JSONDecoder().decode(File.self, from: Data($0.utf8)) }?.hosts ?? [:]
        pins = loaded
        return loaded
    }

    private func savePins(_ value: [String: Pin]) {
        struct File: Codable { var v = 1; var hosts: [String: Pin] }
        pins = value
        keychain.write(pinsKey, String(decoding: (try? JSONEncoder().encode(File(hosts: value))) ?? Data(), as: UTF8.self))
    }

    // MARK: Connect

    /// A DSHClient whose calls go through an end-to-end encrypted tunnel to `host`.
    /// The first session opens here, so a refused or offline Host fails right away.
    public func connect(_ host: RemoteHostInfo,
                        confirmNewHost: @escaping @Sendable (RemoteHostInfo) async -> Bool) async throws -> (DSHClient, RemoteTunnelCarrier) {
        let carrier = RemoteTunnelCarrier(hostId: host.id) { [weak self] previous in
            guard let self else { throw RemoteFailure("CLIENT_CLOSED", "The account is gone.", retryable: false) }
            return try await self.openSession(host, previous: previous, confirm: confirmNewHost)
        }
        try await carrier.start()
        return (DSHClient(carrier: carrier), carrier)
    }

    func openSession(_ host: RemoteHostInfo, previous: RemoteFailure?,
                     confirm: @escaping @Sendable (RemoteHostInfo) async -> Bool) async throws -> RemoteHostSession {
        try await guarded {
            self.restore()
            guard let identity = self.identity, self.credentials != nil else {
                throw RemoteFailure("ACCOUNT_AUTH_REQUIRED", "Sign in to the remote Server first.", retryable: false)
            }
            let stale = previous?.code == "TOKEN_EXPIRED" || previous?.code == "AUTH_INVALID"
            var token = try await self.accessToken(forceRefresh: stale)
            let peer: RemotePeer
            do { peer = try await self.api.device(token, host.id) } catch let error as RemoteAPIError where error.isAuthFailure {
                token = try await self.accessToken(forceRefresh: true)
                peer = try await self.api.device(token, host.id)
            }
            guard peer.role == "host", peer.deviceId == host.id, RemoteBytes.isIdentityKey(peer.identityKey),
                  let hostKey = RemoteBytes.fromBase64URL(peer.identityKey) else {
                throw RemoteFailure("INVALID_MESSAGE", "The Server returned an invalid Host descriptor.", retryable: false)
            }
            if peer.online == false { throw RemoteFailure("HOST_OFFLINE", "The Host is offline.", retryable: true) }
            try await self.checkPin(host, peer, confirm: confirm)

            var transport: RelayTransport
            do {
                transport = try await RelayTransport.connect(url: self.api.controlSocketURL, deviceId: identity.deviceId,
                                                             accessToken: token, hostDeviceId: host.id, clientVersion: self.clientVersion)
            } catch let failure as RemoteFailure where failure.code == "AUTH_INVALID" || failure.code == "TOKEN_EXPIRED" {
                token = try await self.accessToken(forceRefresh: true)
                transport = try await RelayTransport.connect(url: self.api.controlSocketURL, deviceId: identity.deviceId,
                                                             accessToken: token, hostDeviceId: host.id, clientVersion: self.clientVersion)
            }
            guard let privateKey = RemoteBytes.fromBase64URL(identity.privateKey) else {
                throw RemoteFailure("ACCOUNT_AUTH_REQUIRED", "The device identity is damaged; sign in again.", retryable: false)
            }
            let channel = try await SecureChannel.establish(transport: transport, clientPrivateKey: privateKey,
                                                            clientDeviceId: identity.deviceId, hostDeviceId: host.id,
                                                            hostIdentityKey: hostKey)
            let rpc = RemoteRPCClient(channel: channel)
            do {
                let description = try await rpc.call("harness.transport.describe", timeout: 10) as? [String: Any]
                guard let capabilities = description?["capabilities"] as? [String], capabilities.count <= 128,
                      Set(capabilities).count == capabilities.count else {
                    throw RemoteFailure("INVALID_MESSAGE", "The Host returned invalid transport capabilities.", retryable: false)
                }
                let v3 = capabilities.contains("harness.remote.v3"), v1 = capabilities.contains("harness.remote.v1")
                if v3 && v1 { throw RemoteFailure("INVALID_MESSAGE", "The Host advertised conflicting session formats.", retryable: false) }
                guard v3 else {
                    throw RemoteFailure("HARNESS_VERSION_INCOMPATIBLE",
                                        v1 ? "The Host runs a DSH older than 0.2." : "Update the ds-harness-remote plugin on the Host.",
                                        retryable: false)
                }
                return RemoteHostSession(rpc: rpc, capabilities: capabilities, harnessVersion: peer.harnessVersion)
            } catch let error as RemoteRPCError {
                rpc.close()
                if error.code == "METHOD_NOT_FOUND" {
                    throw RemoteFailure("HARNESS_VERSION_INCOMPATIBLE", "Update the ds-harness-remote plugin on the Host.", retryable: false)
                }
                throw RemoteFailure(error.code, error.message, retryable: error.retryable || error.isLocal)
            } catch {
                rpc.close()
                throw error
            }
        }
    }

    private func checkPin(_ host: RemoteHostInfo, _ peer: RemotePeer,
                          confirm: @Sendable (RemoteHostInfo) async -> Bool) async throws {
        var pins = loadPins()
        if let pinned = pins[host.id] {
            guard RemoteBytes.constantTimeEquals(Data(pinned.identityKey.utf8), Data(peer.identityKey.utf8)) else {
                throw RemoteFailure("PEER_IDENTITY_MISMATCH",
                                    "The identity key of this Host changed (pinned \(RemoteBytes.identityFingerprint(pinned.identityKey)), Server reports \(RemoteBytes.identityFingerprint(peer.identityKey))).",
                                    retryable: false)
            }
            return
        }
        let candidate = RemoteHostInfo(id: host.id, name: peer.name, platform: peer.platform, online: peer.online ?? host.online,
                                       harnessVersion: peer.harnessVersion ?? host.harnessVersion,
                                       pluginVersion: peer.clientVersion ?? host.pluginVersion, lastSeen: host.lastSeen,
                                       identityKey: peer.identityKey, trust: .unpinned)
        guard await confirm(candidate) else {
            throw RemoteFailure("HOST_NOT_TRUSTED", "The new Host identity was not confirmed.", retryable: false)
        }
        pins = loadPins()
        pins[host.id] = Pin(identityKey: peer.identityKey, name: peer.name, pinnedAt: RemoteBytes.now())
        savePins(pins)
    }

    /// Maps lower-level errors to `RemoteFailure`.
    private func guarded<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch let failure as RemoteFailure {
            throw RemoteFailure(failure.code, failure.message,
                                retryable: failure.retryable && !RemoteFailure.terminalCodes.contains(failure.code))
        } catch let error as RemoteAPIError {
            throw error.failure
        } catch let error as NoiseError {
            throw RemoteFailure(error.code, error.message, retryable: false)
        } catch is CancellationError {
            throw RemoteFailure("LOGIN_CANCELLED", "Cancelled.", retryable: true)
        } catch {
            throw RemoteFailure("CONNECTION_FAILED", "\(error)", retryable: true)
        }
    }
}
