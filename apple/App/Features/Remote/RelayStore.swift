// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Remote account state for the app (port of 原 Flutter 版 lib/remote/relay/
// relay_backend.dart + dsh_remote_backend.dart, relay only): server address,
// sign-in (browser or email/password), host list, and opening a Host.
import DSHClient
import DSHRemote
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class RelayStore {

    /// Host part of the self-hosted ds-harness-remote Server; empty until the
    /// person enters one. There is no default hosted service.
    private(set) var serverText: String
    private(set) var user: RemoteUser?
    private(set) var hosts: [RemoteHostInfo] = []
    private(set) var providers: [RemoteLoginProvider] = []
    private(set) var loadingHosts = false
    private(set) var hostsError: String?
    private(set) var signingIn = false
    private(set) var signInError: String?
    /// A browser sign-in waiting for the person to finish in Safari.
    private(set) var pendingLogin: RemoteQRLogin?

    @ObservationIgnored private let prefs = UserDefaults.standard
    @ObservationIgnored private(set) var account: RemoteAccount?

    private let application: UIApplication

    init(application: UIApplication) {
        self.application = application
        serverText = prefs.string(forKey: "relay.server") ?? ""
        account = Self.makeAccount(serverText)
        Task { await restore() }
    }

    var signedIn: Bool { user != nil }

    private static func makeAccount(_ server: String) -> RemoteAccount? {
        guard let url = RemoteServerURL.normalize(server) else { return nil }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        return RemoteAccount(server: url, deviceName: "\(UIDevice.current.name) · DSH", clientVersion: version)
    }

    func restore() async {
        user = await account?.currentUser()
        if signedIn { await refreshHosts() } else { await loadProviders() }
    }

    func loadProviders() async {
        providers = (try? await account?.loginProviders()) ?? []
    }

    /// Switches Server (sign-in is per Server origin).
    @discardableResult
    func setServer(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RemoteServerURL.normalize(trimmed) != nil else { return false }
        guard trimmed != serverText else { return true }
        pendingLogin?.cancel(); pendingLogin = nil
        serverText = trimmed
        prefs.set(trimmed, forKey: "relay.server")
        account = Self.makeAccount(trimmed)
        user = nil; hosts = []
        return true
    }

    func signIn(email: String, password: String) async -> Bool {
        guard let account else { signInError = String(localized: "Invalid server address"); return false }
        signingIn = true; signInError = nil
        defer { signingIn = false }
        do {
            user = try await account.login(email: email, password: password)
            await refreshHosts()
            return true
        } catch let failure as RemoteFailure {
            signInError = failure.code == "AUTH_INVALID" || failure.code == "AUTH_REQUIRED"
                ? String(localized: "Incorrect email or password") : Self.message(failure)
            return false
        } catch {
            signInError = String(localized: "Couldn’t sign in")
            return false
        }
    }

    /// Browser sign-in: opens the Server's page in Safari and polls until done.
    func signInWithBrowser(_ provider: RemoteLoginProvider) async {
        guard let account else { return }
        pendingLogin?.cancel()
        signInError = nil
        do {
            let login = try await account.startQRLogin(provider)
            pendingLogin = login
            await application.open(login.scanURL)
            user = try await login.result
            pendingLogin = nil
            await refreshHosts()
        } catch let failure as RemoteFailure {
            pendingLogin = nil
            if failure.code != "LOGIN_CANCELLED" { signInError = Self.message(failure) }
        } catch {
            pendingLogin = nil
        }
    }

    func cancelBrowserSignIn() { pendingLogin?.cancel(); pendingLogin = nil }

    func signOut() async {
        await account?.logout()
        user = nil; hosts = []
        await loadProviders()
    }

    func refreshHosts() async {
        guard let account, signedIn else { return }
        loadingHosts = true
        defer { loadingHosts = false }
        do {
            hosts = try await account.listHosts()
            hostsError = nil
        } catch let failure as RemoteFailure {
            if failure.code == "ACCOUNT_AUTH_REQUIRED" { user = nil }
            hostsError = String(localized: "Couldn’t load hosts · Tap to retry")
        } catch {
            hostsError = String(localized: "Couldn’t load hosts · Tap to retry")
        }
    }

    func forget(_ hostId: String) async { await account?.forgetHost(hostId) }

    /// Opens the Host; `confirm` shows the first-use fingerprint prompt.
    func connect(hostId: String, confirm: @escaping @Sendable (RemoteHostInfo) async -> Bool) async throws -> (DSHClient, RemoteTunnelCarrier) {
        guard let account, signedIn else {
            throw RemoteFailure("ACCOUNT_AUTH_REQUIRED", "Sign in to DSH Remote first.", retryable: false)
        }
        if !hosts.contains(where: { $0.id == hostId }) { await refreshHosts() }
        guard let host = hosts.first(where: { $0.id == hostId }) else {
            throw RemoteFailure("DEVICE_NOT_FOUND", "Host not found.", retryable: false)
        }
        do {
            return try await account.connect(host, confirmNewHost: confirm)
        } catch let failure as RemoteFailure {
            if failure.code == "ACCOUNT_AUTH_REQUIRED" { user = nil }
            throw failure
        }
    }

    /// Flutter remoteErr* strings for a relay failure code.
    static func message(_ failure: RemoteFailure) -> String {
        switch failure.code {
        case "HOST_OFFLINE": String(localized: "Host is offline")
        case "ACCOUNT_AUTH_REQUIRED", "AUTH_INVALID", "TOKEN_EXPIRED": String(localized: "Sign in again")
        case "PEER_IDENTITY_MISMATCH": String(localized: "Host identity key has changed")
        case "HOST_NOT_TRUSTED": String(localized: "Host identity fingerprint hasn’t been confirmed")
        case "CONNECTION_REPLACED": String(localized: "Remote connection was replaced")
        case "CONNECTION_REJECTED": String(localized: "Host declined the connection")
        case "MEMBERSHIP_REQUIRED", "DEVICE_NOT_FOUND", "DEVICE_REVOKED": String(localized: "Host isn’t in your DSH Remote account")
        case "HARNESS_VERSION_INCOMPATIBLE", "CAPABILITY_NOT_SUPPORTED", "UNSUPPORTED_VERSION":
            String(localized: "Update DSH or the remote plugin on the host")
        case "RATE_LIMITED": String(localized: "Too many requests")
        case "LOGIN_EXPIRED": String(localized: "Sign-in timed out")
        default: String(localized: "Couldn’t connect remotely")
        }
    }
}
