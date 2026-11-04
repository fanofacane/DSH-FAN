// SPDX-License-Identifier: AGPL-3.0-or-later
// Remote hosts (port of 原 Flutter 版 lib/remote: ssh_host_config.dart, secret_store.dart,
// ssh_link.dart). "This phone" is the on-device engine; SSH hosts run
// `dsh web` on a computer or server and are reached through a loopback forward.
// Host settings live in UserDefaults; passwords and private keys only in the
// Keychain (this device only).
import DSHClient
import DSHRemote
import DSHRuntime
import Foundation
import Observation
import Security

struct SSHHost: Codable, Identifiable, Equatable {
    enum Auth: String, Codable { case password, privateKey }
    var id: String
    var name: String
    var host: String
    var port = 22
    var user: String
    var auth = Auth.password
    var launchCommand = defaultDshLaunchCommand
    var workingDirectory: String?
    var hostKeyType: String?
    var hostKeyFingerprint: String?

    var address: String { port == 22 ? "\(user)@\(host)" : "\(user)@\(host):\(port)" }

    static func newId() -> String {
        "ssh-" + (0..<8).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}

/// Keychain items for one app: `remote.<key>`, this device only.
enum Secrets {
    private static let service = "io.github.fanofacane.dsh.remote"

    static func read(_ key: String) -> String? {
        let query: NSDictionary = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: key, kSecReturnData as String: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ key: String, _ value: String?) {
        let base: NSDictionary = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        let add = base.mutableCopy() as! NSMutableDictionary
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func passwordKey(_ id: String) -> String { "ssh.\(id).password" }
    static func privateKeyKey(_ id: String) -> String { "ssh.\(id).privateKey" }
}

/// Asks the person to trust a host key on first connect (host_key_dialog.dart).
struct HostKeyPrompt: Identifiable {
    enum Kind { case ssh, relay }
    let id = UUID()
    var kind = Kind.ssh
    let hostName: String
    let address: String
    let key: PresentedHostKey
}

/// What the UI shows for the active remote host.
struct ActiveHost: Equatable {
    enum Kind { case ssh, relay }
    let kind: Kind
    let id: String
    let name: String
    /// `user@host:port` or "DSH Remote".
    let detail: String
}

@MainActor
@Observable
final class HostStore {

    enum LinkState: Equatable {
        case idle
        case connecting(LinkStep)
        case connected
        case failed(title: String, detail: String?)
    }

    private(set) var hosts: [SSHHost] = []
    /// nil: this phone.
    private(set) var activeId: String?
    private(set) var state = LinkState.idle
    private(set) var reused = false
    var hostKeyPrompt: HostKeyPrompt?
    /// Start on the last used host (Flutter: remoteAutoConnectOnStartup).
    var autoConnect: Bool { didSet { prefs.set(autoConnect, forKey: "remote.autoConnect") } }
    /// Called when an SSH link drops while in use.
    @ObservationIgnored private weak var events: (any HostLinkEvents)?

    @ObservationIgnored private let prefs = UserDefaults.standard
    @ObservationIgnored private var link: SSHHostLink?
    @ObservationIgnored private var linkHostId: String?
    @ObservationIgnored private var cached: (baseURL: URL, token: String)?
    @ObservationIgnored private var lastMismatch: PresentedHostKey?
    @ObservationIgnored private var keyWaiter: CheckedContinuation<Bool, Never>?

    let runtime: any EngineControlling
    let relay: RelayStore

    init(runtime: any EngineControlling, relay: RelayStore, events: any HostLinkEvents) {
        self.events = events
        self.runtime = runtime
        self.relay = relay
        autoConnect = prefs.object(forKey: "remote.autoConnect") as? Bool ?? true
        if let data = prefs.data(forKey: "remote.sshHosts"), let list = try? JSONDecoder().decode([SSHHost].self, from: data) {
            hosts = list
        }
        relayNames = prefs.dictionary(forKey: "remote.relayNames") as? [String: String] ?? [:]
        let last = prefs.string(forKey: "remote.active")
        let valid = last.map { id in id.hasPrefix(Self.relayPrefix) || hosts.contains(where: { $0.id == id }) } ?? false
        activeId = autoConnect && valid ? last : nil
    }

    static let relayPrefix = "relay:"
    /// Display names of relay Hosts, by device id (the list itself comes from the Server).
    @ObservationIgnored private var relayNames: [String: String]
    @ObservationIgnored private var carrier: RemoteTunnelCarrier?

    /// The active SSH host (nil for this phone or a relay Host).
    var active: SSHHost? { hosts.first { $0.id == activeId } }
    var activeRelayId: String? {
        guard let activeId, activeId.hasPrefix(Self.relayPrefix) else { return nil }
        return String(activeId.dropFirst(Self.relayPrefix.count))
    }
    var activeHost: ActiveHost? {
        if let ssh = active { return ActiveHost(kind: .ssh, id: ssh.id, name: ssh.name, detail: ssh.address) }
        if let relay = activeRelayId {
            return ActiveHost(kind: .relay, id: relay, name: relayNames[relay] ?? String(localized: "This host"), detail: "DSH Remote")
        }
        return nil
    }
    var isRemote: Bool { activeHost != nil }
    var linkAlive: Bool { activeRelayId != nil ? carrier?.isConnected ?? false : link?.isAlive ?? false }

    static func relayId(_ deviceId: String) -> String { relayPrefix + deviceId }

    func rememberRelayName(_ deviceId: String, _ name: String) {
        relayNames[deviceId] = name
        prefs.set(relayNames, forKey: "remote.relayNames")
    }

    /// Working directory for new chats on the active SSH host (`~/` expanded), else nil.
    var sessionDirectory: String? {
        guard let raw = active?.workingDirectory?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        guard let home = link?.endpoint?.home, !home.isEmpty else { return raw.hasPrefix("~") ? nil : raw }
        let base = home.hasSuffix("/") ? String(home.dropLast()) : home
        if raw == "~" { return base }
        if raw.hasPrefix("~/") { return base + "/" + raw.dropFirst(2) }
        return raw
    }

    // MARK: Hosts

    func save(_ host: SSHHost, password: String?, privateKey: String?) {
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            let old = hosts[index]
            hosts[index] = host
            if old.host != host.host || old.port != host.port || old.user != host.user || old.launchCommand != host.launchCommand,
               linkHostId == host.id {
                dropLink()
            }
        } else {
            hosts.append(host)
        }
        if let password { Secrets.write(Secrets.passwordKey(host.id), host.auth == .password ? password : nil) }
        if let privateKey { Secrets.write(Secrets.privateKeyKey(host.id), host.auth == .privateKey ? privateKey : nil) }
        if host.auth == .password { Secrets.write(Secrets.privateKeyKey(host.id), nil) } else { Secrets.write(Secrets.passwordKey(host.id), nil) }
        persist()
    }

    func delete(_ host: SSHHost) {
        if activeId == host.id { select(nil) }
        hosts.removeAll { $0.id == host.id }
        Secrets.write(Secrets.passwordKey(host.id), nil)
        Secrets.write(Secrets.privateKeyKey(host.id), nil)
        persist()
    }

    func resetFingerprint(_ host: SSHHost) {
        guard var copy = hosts.first(where: { $0.id == host.id }) else { return }
        copy.hostKeyType = nil; copy.hostKeyFingerprint = nil
        save(copy, password: nil, privateKey: nil)
    }

    func hasSecret(_ host: SSHHost) -> Bool {
        Secrets.read(host.auth == .password ? Secrets.passwordKey(host.id) : Secrets.privateKeyKey(host.id)) != nil
    }

    /// Switches host; the caller reconnects the chat.
    func select(_ id: String?) {
        guard id != activeId else { return }
        dropLink()
        activeId = id
        prefs.set(id, forKey: "remote.active")
        state = .idle
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(hosts) { prefs.set(data, forKey: "remote.sshHosts") }
    }

    private func dropLink() {
        link?.close(); link = nil; linkHostId = nil; cached = nil
        carrier = nil // The chat client owns and closes it.
    }

    /// A signed-in client for the active host: this phone's engine, an SSH
    /// host through its forward, or a DSH Remote Host through the relay tunnel.
    func makeClient(forceRestart: Bool = false) async throws -> DSHClient {
        if let relay = activeRelayId { return try await openRelay(relay) }
        let info = try await endpoint(forceRestart: forceRestart)
        let client = DSHClient(baseURL: info.baseURL)
        do { try await client.login(token: info.token) } catch {
            noteClientFailure((error as? DSHError)?.code ?? "E_LOGIN")
            throw error
        }
        return client
    }

    private func openRelay(_ hostId: String) async throws -> DSHClient {
        dropLink()
        state = .connecting(.connecting)
        let expected = activeId
        do {
            let (client, carrier) = try await relay.connect(hostId: hostId) { [weak self] candidate in
                await self?.confirmRelay(candidate) ?? false
            }
            guard activeId == expected else { client.close(); throw LinkFailure("E_SWITCHED") }
            self.carrier = carrier
            carrier.onFailure = { [weak self, weak carrier] failure in
                Task { @MainActor in
                    guard let self, let carrier, self.carrier === carrier else { return }
                    self.state = .failed(title: RelayStore.message(failure), detail: failure.code)
                    if !failure.retryable || !carrier.isConnected { self.events?.hostLinkLost() }
                }
            }
            state = .connected
            return client
        } catch let failure as RemoteFailure {
            state = .failed(title: RelayStore.message(failure), detail: failure.code)
            throw LinkFailure(failure.code)
        }
    }

    private func confirmRelay(_ host: RemoteHostInfo) async -> Bool {
        let key = PresentedHostKey(type: "DSH Remote", fingerprint: host.fingerprint ?? "")
        return await withCheckedContinuation { continuation in
            keyWaiter?.resume(returning: false)
            keyWaiter = continuation
            hostKeyPrompt = HostKeyPrompt(kind: .relay, hostName: host.name, address: "DSH Remote", key: key)
        }
    }

    // MARK: Endpoint

    /// Base URL + launch token of the active host, opening the SSH link when needed.
    func endpoint(forceRestart: Bool = false) async throws -> (baseURL: URL, token: String) {
        guard let host = active else {
            guard let info = await runtime.connection() else { throw LinkFailure("E_ENGINE_NOT_RUNNING") }
            return (info.baseURL, info.token)
        }
        if !forceRestart, linkHostId == host.id, let link, link.isAlive, let cached { return cached }
        dropLink()
        return try await open(host, forceRestart: forceRestart)
    }

    private func open(_ host: SSHHost, forceRestart: Bool) async throws -> (baseURL: URL, token: String) {
        let auth: SSHAuth
        switch host.auth {
        case .password:
            guard let password = Secrets.read(Secrets.passwordKey(host.id)) else {
                return try fail(String(localized: "Enter a password"), nil)
            }
            auth = .password(password)
        case .privateKey:
            guard let key = Secrets.read(Secrets.privateKeyKey(host.id)) else {
                return try fail(String(localized: "Enter a private key"), nil)
            }
            auth = .privateKey(key)
        }
        let target = SSHTarget(host: host.host, port: host.port, user: host.user, launchCommand: host.launchCommand,
                               workingDirectory: host.workingDirectory)
        let link = SSHHostLink(target: target)
        self.link = link; linkHostId = host.id
        state = .connecting(.connecting)
        lastMismatch = nil
        do {
            let result = try await link.open(
                auth: auth,
                checkHostKey: { [weak self] key in
                    guard let self else { return false }
                    return await self.verify(key, for: host.id) == .trusted
                },
                forceRestart: forceRestart,
                onLost: { [weak self] in Task { @MainActor in self?.linkLost(link) } },
                progress: { [weak self] step in Task { @MainActor in
                    if case .connecting = self?.state { self?.state = .connecting(step) }
                } })
            guard self.link === link else { link.close(); throw LinkFailure("E_SWITCHED") }
            cached = result
            reused = link.endpoint?.reused ?? false
            state = .connected
            return result
        } catch let error as RemoteError {
            if self.link === link { dropLink() }
            if let mismatch = lastMismatch {
                let saved = hosts.first { $0.id == host.id }?.hostKeyFingerprint ?? ""
                return try fail(String(localized: "Host fingerprint changed. Disconnected."),
                                String(localized: "If the host was reinstalled or replaced, reset its fingerprint in host settings.\nSaved: \(saved)\nReceived: \(mismatch.fingerprint) (\(mismatch.type))"))
            }
            return try fail(Self.title(error, host: host), error.detail.map(RemoteBootstrap.redactTokens))
        } catch let error as LinkFailure {
            throw error
        } catch {
            if self.link === link { dropLink() }
            return try fail(String(localized: "Couldn’t connect over SSH"), "\(error)")
        }
    }

    private func fail(_ title: String, _ detail: String?) throws -> (baseURL: URL, token: String) {
        state = .failed(title: title, detail: detail)
        throw LinkFailure("E_REMOTE")
    }

    private func linkLost(_ lost: SSHHostLink) {
        guard link === lost else { return }
        dropLink()
        state = .failed(title: String(localized: "SSH disconnected"), detail: nil)
        events?.hostLinkLost()
    }

    /// Records a failure that happened after the tunnel came up (sign-in, RPC).
    func noteClientFailure(_ code: String) {
        guard isRemote else { return }
        let title = code.hasPrefix("URL_ERROR") || code == "E_LOGIN"
            ? String(localized: "Couldn’t connect to DSH through the tunnel")
            : String(localized: "Couldn’t sign in to remote DSH")
        state = .failed(title: title, detail: code)
    }

    // MARK: Host key (TOFU)

    private enum Verdict { case trusted, mismatch, rejected }

    private func verify(_ key: PresentedHostKey, for id: String) async -> Verdict {
        guard let host = hosts.first(where: { $0.id == id }) else { return .rejected }
        if let pinned = host.hostKeyFingerprint, !pinned.isEmpty {
            if pinned == key.fingerprint { return .trusted }
            lastMismatch = key
            return .mismatch
        }
        let trusted = await withCheckedContinuation { continuation in
            keyWaiter?.resume(returning: false)
            keyWaiter = continuation
            hostKeyPrompt = HostKeyPrompt(hostName: host.name, address: host.address, key: key)
        }
        guard trusted, var pinned = hosts.first(where: { $0.id == id }) else { return .rejected }
        pinned.hostKeyType = key.type; pinned.hostKeyFingerprint = key.fingerprint
        if let index = hosts.firstIndex(where: { $0.id == id }) { hosts[index] = pinned; persist() }
        return .trusted
    }

    func answerHostKey(_ trust: Bool) {
        hostKeyPrompt = nil
        let waiter = keyWaiter; keyWaiter = nil
        waiter?.resume(returning: trust)
    }

    // MARK: Messages (Flutter remoteErr* strings)

    static func title(_ error: RemoteError, host: SSHHost) -> String {
        switch error.kind {
        case .connectFailed:
            let detail = error.detail ?? ""
            if detail.contains("connectTimeout") || detail.contains("timed out") {
                return String(localized: "\(host.host):\(String(host.port)) isn’t responding")
            }
            if detail.contains("refused") { return String(localized: "\(host.host):\(String(host.port)) refused the connection") }
            if detail.contains("resolve") || detail.contains("NXDOMAIN") || detail.contains("getaddrinfo") {
                return String(localized: "Host \(host.host) not found")
            }
            return String(localized: "Couldn’t connect over SSH")
        case .authFailed:
            return host.auth == .password ? String(localized: "Incorrect username or password")
                                          : String(localized: "Server doesn’t accept this private key")
        case .hostKeyRejected: return String(localized: "Host trust cancelled")
        case .hostKeyMismatch: return String(localized: "Host fingerprint changed. Disconnected.")
        case .badKey: return String(localized: "Couldn’t read the private key")
        case .channelFailed: return String(localized: "SSH connection interrupted")
        case .timeout: return String(localized: "SSH handshake timed out")
        case .noShell: return String(localized: "Host has no sh. Only Linux and macOS are supported.")
        case .dshNotFound:
            return host.launchCommand == defaultDshLaunchCommand
                ? String(localized: "dsh isn’t installed on the host. Install it and retry, or enter its full path as the start command.")
                : String(localized: "“\(host.launchCommand)” not found on the host")
        case .dshTimeout: return String(localized: "Remote DSH took too long to start")
        case .dshStartFailed: return String(localized: "Couldn’t start remote DSH")
        case .forwardFailed: return String(localized: "Couldn’t connect to DSH through the tunnel")
        case .badAddress: return String(localized: "Enter a host address (IP or domain)")
        }
    }
}

struct LinkFailure: Error { let code: String; init(_ code: String) { self.code = code } }
