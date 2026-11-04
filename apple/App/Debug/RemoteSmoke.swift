// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import Foundation

/// Simulator remote smoke test (`-dsh-remote-smoke`). The launch environment
/// names a throwaway SSH host: `DSH_SSH_TARGET=user@host:port` plus
/// `DSH_SSH_PASSWORD` or `DSH_SSH_KEYFILE`. The host key is trusted after a
/// short pause (so the prompt can be screenshotted). Results
/// (Documents/remote-smoke.json) hold states and counts only.
extension HostStore {
    static var remoteSmokeRequested: Bool { ProcessInfo.processInfo.arguments.contains("-dsh-remote-smoke") }

    /// Relay mode: `DSH_RELAY_SERVER`, `DSH_RELAY_EMAIL`, `DSH_RELAY_PASSWORD`.
    func seedRelaySmoke() async -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["DSH_RELAY_SERVER"], let email = env["DSH_RELAY_EMAIL"], let password = env["DSH_RELAY_PASSWORD"] else { return false }
        if env["DSH_RELAY_RESET"] != nil { await relay.signOut() }
        relay.setServer(server)
        if !relay.signedIn { _ = await relay.signIn(email: email, password: password) }
        await relay.refreshHosts()
        guard let host = relay.hosts.first(where: { $0.online }) else { return true }
        rememberRelayName(host.id, host.name)
        select(HostStore.relayId(host.id))
        return true
    }

    func seedSmokeHost() {
        let env = ProcessInfo.processInfo.environment
        guard let target = env["DSH_SSH_TARGET"], let at = target.firstIndex(of: "@") else { return }
        let user = String(target[..<at])
        let rest = target[target.index(after: at)...]
        let parts = rest.split(separator: ":")
        let host = SSHHost(id: "ssh-smoke", name: "Docker test", host: String(parts[0]),
                           port: parts.count > 1 ? Int(parts[1]) ?? 22 : 22, user: user,
                           auth: env["DSH_SSH_KEYFILE"] == nil ? .password : .privateKey,
                           workingDirectory: env["DSH_SSH_CWD"])
        let key = env["DSH_SSH_KEYFILE"].flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
        if env["DSH_SSH_RESET"] != nil, hosts.contains(where: { $0.id == host.id }) { delete(host) }
        var merged = host
        if let old = hosts.first(where: { $0.id == host.id }) {
            merged.hostKeyType = old.hostKeyType; merged.hostKeyFingerprint = old.hostKeyFingerprint
        }
        save(merged, password: env["DSH_SSH_PASSWORD"], privateKey: key)
        select(host.id)
    }

    func autoTrustForSmoke() {
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if hostKeyPrompt != nil {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    answerHostKey(true)
                }
            }
        }
    }
}

extension AppSession {
    func runRemoteSmoke(hosts: HostStore, relay: RelayStore) async {
        var result = SmokeReport()
        func save() {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("remote-smoke.json")
            if let data = try? result.data() {
                try? data.write(to: url, options: .atomic)
            }
        }
        // A foreground reconnect may already be running; wait for it to settle.
        for _ in 0..<120 where self.connection.state == .connecting || self.connection.state == .idle {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        result.set("connection", "\(self.connection.state)")
        result.set("link", "\(hosts.state)")
        result.set("reused", hosts.reused)
        result.set("models", self.connection.models.count)
        result.set("sessions", self.sessionList.sessions.count)
        result.set("keyConfigured", self.connection.keyConfigured)
        result.set("fingerprintPinned", hosts.active?.hostKeyFingerprint != nil)
        result.set("kind", hosts.activeRelayId != nil ? "relay" : "ssh")
        result.set("relaySignedIn", relay.signedIn)
        result.set("relayHosts", relay.hosts.count)
        if self.connection.state == .ready, hosts.activeRelayId != nil {
            // Round trip through the tunnel: new chat session, then the list again.
            self.transcript.newChat()
            result.set("sessionsAfterRefresh", self.sessionList.sessions.count)
        }
        result.set("cwd", hosts.sessionDirectory ?? "")
        result.set("result", self.connection.state == .ready ? "PASS" : "FAIL")
        save()
    }
}
#endif
