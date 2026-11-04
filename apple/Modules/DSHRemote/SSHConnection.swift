// SPDX-License-Identifier: AGPL-3.0-or-later
// SSH transport for remote hosts (port of 原 Flutter 版 lib/remote/ssh/ssh_transport.dart):
// password or OpenSSH-key login, host-key check, one-shot commands, and a
// loopback port forward over direct-tcpip channels.
import CryptoKit
import Foundation
import NIOCore
import NIOPosix
import NIOSSH

public enum SSHAuth: Sendable {
    case password(String)
    /// OpenSSH (`-----BEGIN OPENSSH PRIVATE KEY-----`) or PEM EC key text.
    case privateKey(String)
}

/// The server's host key as shown to the person on first connect.
public struct PresentedHostKey: Sendable, Equatable {
    /// e.g. `ssh-ed25519`.
    public let type: String
    /// `SHA256:<base64, no padding>`, the same as `ssh-keygen -lf`.
    public let fingerprint: String
    public init(type: String, fingerprint: String) { self.type = type; self.fingerprint = fingerprint }
}

public struct ExecResult: Sendable {
    public let exitCode: Int?
    public let stdout: String
    public let stderr: String
}

public struct RemoteError: Error, Sendable, Equatable {
    public enum Kind: String, Sendable {
        case connectFailed, authFailed, hostKeyRejected, hostKeyMismatch, badKey, channelFailed, timeout
        case noShell, dshNotFound, dshStartFailed, dshTimeout, forwardFailed, badAddress
    }
    public let kind: Kind
    /// Extra lines for the person (log tail, fingerprints). Never contains tokens.
    public let detail: String?
    public init(_ kind: Kind, detail: String? = nil) { self.kind = kind; self.detail = detail }
}

/// Decides whether to trust a presented host key. Called once per connect.
public typealias HostKeyCheck = @Sendable (PresentedHostKey) async -> Bool

public final class SSHConnection: @unchecked Sendable {
    private let group: MultiThreadedEventLoopGroup
    private let channel: Channel
    private let lock = NSLock()
    private var forwards: [LocalForward] = []
    private var closeHandlers: [@Sendable () -> Void] = []

    public var isActive: Bool { channel.isActive }

    private init(group: MultiThreadedEventLoopGroup, channel: Channel) {
        self.group = group
        self.channel = channel
        channel.closeFuture.whenComplete { [weak self] _ in self?.didClose() }
    }

    /// Connects and authenticates. `checkHostKey` must return true to proceed.
    public static func connect(host: String, port: Int, user: String, auth: SSHAuth,
                               timeout: TimeInterval = 20,
                               checkHostKey: @escaping HostKeyCheck) async throws -> SSHConnection {
        let userAuth: UserAuth
        switch auth {
        case .password(let password): userAuth = UserAuth(user: user, offer: .password(password))
        case .privateKey(let text):
            guard let key = try? OpenSSHKey.parse(text) else { throw RemoteError(.badKey) }
            userAuth = UserAuth(user: user, offer: .key(key))
        }
        let hostKeys = HostKeyDelegate(check: checkHostKey)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let authDone = group.next().makePromise(of: Void.self)
        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(.seconds(Int64(timeout)))
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let ssh = NIOSSHHandler(role: .client(.init(userAuthDelegate: userAuth, serverAuthDelegate: hostKeys)),
                                            allocator: channel.allocator, inboundChildChannelInitializer: nil)
                    try channel.pipeline.syncOperations.addHandler(ssh)
                    try channel.pipeline.syncOperations.addHandler(AuthWatcher(promise: authDone))
                }
            }
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_KEEPALIVE), value: 1)
        let channel: Channel
        do {
            channel = try await bootstrap.connect(host: host, port: port).get()
        } catch {
            try? await group.shutdownGracefully()
            throw RemoteError(.connectFailed, detail: "\(error)")
        }
        let timer = group.next().scheduleTask(in: .seconds(Int64(timeout + 40))) {
            authDone.fail(RemoteError(.timeout))
        }
        do {
            try await authDone.futureResult.get()
            timer.cancel()
        } catch {
            timer.cancel()
            try? await channel.close()
            try? await group.shutdownGracefully()
            if let rejected = hostKeys.failure { throw rejected }
            if userAuth.exhausted { throw RemoteError(.authFailed) }
            if let error = error as? RemoteError { throw error }
            throw RemoteError(.connectFailed, detail: "\(error)")
        }
        return SSHConnection(group: group, channel: channel)
    }

    /// Called once when the connection drops (or `close()` is called).
    public func onClose(_ handler: @escaping @Sendable () -> Void) {
        let closed = lock.withLock { () -> Bool in
            if !channel.isActive { return true }
            closeHandlers.append(handler); return false
        }
        if closed { handler() }
    }

    private func didClose() {
        let (handlers, open) = lock.withLock { () -> ([@Sendable () -> Void], [LocalForward]) in
            defer { closeHandlers = []; forwards = [] }
            return (closeHandlers, forwards)
        }
        open.forEach { $0.close() }
        handlers.forEach { $0() }
        group.shutdownGracefully { _ in }
    }

    public func close() {
        channel.close(promise: nil)
    }

    // MARK: Commands

    /// Runs `sh -lc <script>` and collects its output (UTF-8, lossy).
    public func run(_ script: String, timeout: TimeInterval = 30) async throws -> ExecResult {
        let command = "sh -lc " + shQuote(script)
        let done = channel.eventLoop.makePromise(of: ExecResult.self)
        let child = channel.eventLoop.makePromise(of: Channel.self)
        channel.pipeline.handler(type: NIOSSHHandler.self).whenComplete { result in
            switch result {
            case .failure(let error): child.fail(error)
            case .success(let ssh):
                ssh.createChannel(child, channelType: .session) { childChannel, _ in
                    childChannel.eventLoop.makeCompletedFuture {
                        try childChannel.pipeline.syncOperations.addHandler(ExecCollector(command: command, done: done))
                    }
                }
            }
        }
        let opened: Channel
        do { opened = try await child.futureResult.get() } catch { throw RemoteError(.channelFailed, detail: "\(error)") }
        let timer = channel.eventLoop.scheduleTask(in: .milliseconds(Int64(timeout * 1000))) {
            done.fail(RemoteError(.timeout)); opened.close(promise: nil)
        }
        defer { timer.cancel() }
        return try await done.futureResult.get()
    }

    // MARK: Port forward

    /// Listens on 127.0.0.1 and tunnels each connection to `targetHost:targetPort`
    /// on the remote side. Tries `preferredPort` first (so the `Host` header the
    /// client sends matches the remote `dsh web`), then any free port.
    public func forward(to targetPort: Int, targetHost: String = "127.0.0.1",
                        preferredPort: Int? = nil) async throws -> LocalForward {
        let forward = try await LocalForward.bind(group: group, ssh: channel, targetHost: targetHost,
                                                  targetPort: targetPort, preferredPort: preferredPort)
        lock.withLock { forwards.append(forward) }
        return forward
    }
}

/// `'…'` with embedded quotes escaped; safe for POSIX sh.
public func shQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

// MARK: Auth delegates

private final class UserAuth: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    enum Offer { case password(String), key(NIOSSHPrivateKey) }
    let user: String
    let offer: Offer
    private var offered = false
    private(set) var exhausted = false

    init(user: String, offer: Offer) { self.user = user; self.offer = offer }

    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods,
                                nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        guard !offered else { exhausted = true; nextChallengePromise.succeed(nil); return }
        offered = true
        switch offer {
        case .password(let password):
            guard availableMethods.contains(.password) else { exhausted = true; nextChallengePromise.succeed(nil); return }
            nextChallengePromise.succeed(.init(username: user, serviceName: "", offer: .password(.init(password: password))))
        case .key(let key):
            guard availableMethods.contains(.publicKey) else { exhausted = true; nextChallengePromise.succeed(nil); return }
            nextChallengePromise.succeed(.init(username: user, serviceName: "", offer: .privateKey(.init(privateKey: key))))
        }
    }
}

private final class HostKeyDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let check: HostKeyCheck
    var failure: RemoteError?
    init(check: @escaping HostKeyCheck) { self.check = check }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let presented = Self.present(hostKey)
        Task {
            if await check(presented) {
                validationCompletePromise.succeed(())
            } else {
                failure = RemoteError(.hostKeyRejected, detail: presented.fingerprint)
                validationCompletePromise.fail(failure!)
            }
        }
    }

    static func present(_ key: NIOSSHPublicKey) -> PresentedHostKey {
        let parts = String(openSSHPublicKey: key).split(separator: " ")
        let type = parts.first.map(String.init) ?? "unknown"
        let blob = parts.count > 1 ? Data(base64Encoded: String(parts[1])) ?? Data() : Data()
        let digest = Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return PresentedHostKey(type: type, fingerprint: "SHA256:" + digest)
    }
}

/// Completes once user auth succeeds; fails when the connection closes first.
private final class AuthWatcher: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = Any
    let promise: EventLoopPromise<Void>
    init(promise: EventLoopPromise<Void>) { self.promise = promise }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is UserAuthSuccessEvent { promise.succeed(()) }
        context.fireUserInboundEventTriggered(event)
    }
    func channelInactive(context: ChannelHandlerContext) {
        promise.fail(RemoteError(.connectFailed, detail: "connection closed"))
        context.fireChannelInactive()
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise.fail(error)
        context.close(promise: nil)
    }
}

// MARK: Exec

private final class ExecCollector: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias OutboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData

    let command: String
    let done: EventLoopPromise<ExecResult>
    private var stdout = Data()
    private var stderr = Data()
    private var exitCode: Int?
    private let limit = 1 << 20

    init(command: String, done: EventLoopPromise<ExecResult>) { self.command = command; self.done = done }

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { _ in }
    }

    func channelActive(context: ChannelHandlerContext) {
        context.triggerUserOutboundEvent(SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true), promise: nil)
        // No stdin: the scripts never read it.
        context.close(mode: .output, promise: nil)
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = message.data else { return }
        let bytes = Data(buffer.readableBytesView)
        switch message.type {
        case .channel where stdout.count < limit: stdout.append(bytes)
        case .stdErr where stderr.count < limit: stderr.append(bytes)
        default: break
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let status = event as? SSHChannelRequestEvent.ExitStatus { exitCode = status.exitStatus }
        if event is ChannelFailureEvent { done.fail(RemoteError(.noShell)) }
        context.fireUserInboundEventTriggered(event)
    }

    func channelInactive(context: ChannelHandlerContext) {
        done.succeed(ExecResult(exitCode: exitCode,
                                stdout: String(decoding: stdout, as: UTF8.self),
                                stderr: String(decoding: stderr, as: UTF8.self)))
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        done.fail(RemoteError(.channelFailed, detail: "\(error)"))
        context.close(promise: nil)
    }
}
