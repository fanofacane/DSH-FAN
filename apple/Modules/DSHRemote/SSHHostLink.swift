// SPDX-License-Identifier: AGPL-3.0-or-later
// One SSH host end to end: log in, make sure `dsh web` runs there, and forward
// a loopback port to it. The app's DSHClient then talks to `baseURL` exactly as
// it does to the on-device engine.
import Foundation

public struct SSHTarget: Sendable, Equatable {
    public var host: String
    public var port: Int
    public var user: String
    public var launchCommand: String
    public var workingDirectory: String?
    public init(host: String, port: Int = 22, user: String, launchCommand: String = defaultDshLaunchCommand,
                workingDirectory: String? = nil) {
        self.host = host; self.port = port; self.user = user
        self.launchCommand = launchCommand; self.workingDirectory = workingDirectory
    }
}

public enum LinkStep: String, Sendable { case connecting, authenticating, starting, forwarding }

public final class SSHHostLink: @unchecked Sendable {
    public let target: SSHTarget
    private let lock = NSLock()
    private var ssh: SSHConnection?
    private var forward: LocalForward?
    public private(set) var endpoint: RemoteEndpoint?

    public init(target: SSHTarget) { self.target = target }

    public var isAlive: Bool { lock.withLock { ssh?.isActive ?? false } }

    /// Returns the loopback base URL and the remote launch token.
    public func open(auth: SSHAuth, checkHostKey: @escaping HostKeyCheck, forceRestart: Bool = false,
                     onLost: @escaping @Sendable () -> Void,
                     progress: @escaping @Sendable (LinkStep) -> Void) async throws -> (baseURL: URL, token: String) {
        close()
        progress(.connecting)
        let connection = try await SSHConnection.connect(host: target.host, port: target.port, user: target.user,
                                                         auth: auth, checkHostKey: checkHostKey)
        do {
            progress(.starting)
            let bootstrap = RemoteBootstrap(launchCommand: target.launchCommand, workingDirectory: target.workingDirectory)
            let endpoint = try await bootstrap.ensureRunning(on: connection, forceRestart: forceRestart)
            progress(.forwarding)
            let forward = try await connection.forward(to: endpoint.port, preferredPort: endpoint.port)
            lock.withLock { self.ssh = connection; self.forward = forward; self.endpoint = endpoint }
            connection.onClose { [weak self] in
                guard let self else { return }
                let current = self.lock.withLock { self.ssh === connection }
                if current { onLost() }
            }
            return (URL(string: "http://127.0.0.1:\(forward.port)")!, endpoint.token)
        } catch {
            connection.close()
            throw error
        }
    }

    /// Stops `dsh web` on the host (the person asked to).
    public func stopRemote() async {
        guard let ssh = lock.withLock({ ssh }) else { return }
        await RemoteBootstrap(launchCommand: target.launchCommand).stop(on: ssh)
    }

    public func close() {
        let (ssh, forward) = lock.withLock { () -> (SSHConnection?, LocalForward?) in
            defer { self.ssh = nil; self.forward = nil }
            return (self.ssh, self.forward)
        }
        forward?.close(); ssh?.close()
    }
}
