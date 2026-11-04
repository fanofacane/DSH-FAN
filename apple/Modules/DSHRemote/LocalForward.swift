// SPDX-License-Identifier: AGPL-3.0-or-later
// Loopback listener that tunnels each accepted socket through an SSH
// direct-tcpip channel (port of 原 Flutter 版 lib/remote/ssh/local_forward.dart).
//
// `dsh web` only accepts a loopback `Host` (and an `Origin` equal to it). The
// app's URLSession cannot set `Host`, so the listener first tries the same
// port number as the remote server; when that port is taken it rewrites
// `127.0.0.1:<local>` to `127.0.0.1:<remote>` in each connection's first
// request head. DSHClient sends one request per connection, so the first head
// is the only one.
import Foundation
import NIOCore
import NIOPosix
import NIOSSH

public final class LocalForward: @unchecked Sendable {
    public let port: Int
    public let targetPort: Int
    private let server: Channel

    private init(port: Int, targetPort: Int, server: Channel) {
        self.port = port; self.targetPort = targetPort; self.server = server
    }

    public func close() { server.close(promise: nil) }

    static func bind(group: EventLoopGroup, ssh: Channel, targetHost: String, targetPort: Int,
                     preferredPort: Int?) async throws -> LocalForward {
        // One event loop for the SSH connection, its child channels and the
        // accepted sockets, so the glue handlers never cross threads.
        let loop = ssh.eventLoop
        var listenPort = 0
        let rewrite = RewriteBox()
        let bootstrap = ServerBootstrap(group: loop, childGroup: loop)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
            .childChannelInitializer { inbound in
                Self.tunnel(inbound, ssh: ssh, targetHost: targetHost, targetPort: targetPort, rewrite: rewrite.value)
            }
        var server: Channel?
        for candidate in [preferredPort, 0].compactMap({ $0 }) {
            if let bound = try? await bootstrap.bind(host: "127.0.0.1", port: candidate).get() {
                server = bound; listenPort = bound.localAddress?.port ?? candidate; break
            }
        }
        guard let server else { throw RemoteError(.forwardFailed) }
        if listenPort != targetPort {
            rewrite.value = (Array("127.0.0.1:\(listenPort)".utf8), Array("127.0.0.1:\(targetPort)".utf8))
        }
        return LocalForward(port: listenPort, targetPort: targetPort, server: server)
    }

    private static func tunnel(_ inbound: Channel, ssh: Channel, targetHost: String, targetPort: Int,
                               rewrite: ([UInt8], [UInt8])?) -> EventLoopFuture<Void> {
        let loop = inbound.eventLoop
        return ssh.pipeline.handler(type: NIOSSHHandler.self).flatMap { handler in
            let promise = loop.makePromise(of: Channel.self)
            let origin = inbound.remoteAddress ?? (try? SocketAddress(ipAddress: "127.0.0.1", port: 0))!
            let type = SSHChannelType.DirectTCPIP(targetHost: targetHost, targetPort: targetPort, originatorAddress: origin)
            handler.createChannel(promise, channelType: .directTCPIP(type)) { child, _ in
                child.eventLoop.makeCompletedFuture {
                    let (ours, theirs) = Glue.matchedPair()
                    try child.pipeline.syncOperations.addHandlers([SSHDataWrapper(), ours])
                    var handlers: [ChannelHandler] = []
                    if let rewrite { handlers.append(HostRewriter(from: rewrite.0, to: rewrite.1)) }
                    handlers.append(theirs)
                    try inbound.pipeline.syncOperations.addHandlers(handlers)
                }
            }
            return promise.futureResult.map { _ in }
        }.flatMapErrorThrowing { error in
            inbound.close(promise: nil)
            throw error
        }
    }
}

private final class RewriteBox: @unchecked Sendable {
    var value: ([UInt8], [UInt8])?
}

/// Rewrites the authority in the first request head of a connection.
private final class HostRewriter: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    let from: [UInt8]
    let to: [UInt8]
    private var head: [UInt8] = []
    private var done = false

    init(from: [UInt8], to: [UInt8]) { self.from = from; self.to = to }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        guard !done else { context.fireChannelRead(data); return }
        head += buffer.readBytes(length: buffer.readableBytes) ?? []
        let end = Self.find([13, 10, 13, 10], in: head)
        guard end != nil || head.count > 32 * 1024 else { return }
        let split = end.map { $0 + 4 } ?? head.count
        var out = Self.replace(Array(head[..<split]), from, to)
        out += head[split...]
        head = []; done = true
        var next = context.channel.allocator.buffer(capacity: out.count)
        next.writeBytes(out)
        context.fireChannelRead(wrapInboundOut(next))
    }

    static func find(_ needle: [UInt8], in hay: [UInt8], from start: Int = 0) -> Int? {
        guard hay.count >= needle.count, start <= hay.count - needle.count else { return nil }
        for i in start...(hay.count - needle.count) where hay[i] == needle[0] && Array(hay[i..<(i + needle.count)]) == needle {
            return i
        }
        return nil
    }

    static func replace(_ bytes: [UInt8], _ from: [UInt8], _ to: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []; var i = 0
        while let hit = find(from, in: bytes, from: i) {
            out += bytes[i..<hit]; out += to; i = hit + from.count
        }
        return out + bytes[i...]
    }
}

private final class SSHDataWrapper: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { _ in }
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)
        guard case .channel = message.type, case .byteBuffer(let buffer) = message.data else { return }
        context.fireChannelRead(wrapInboundOut(buffer))
    }
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        context.write(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(unwrapOutboundIn(data)))), promise: promise)
    }
}

/// Joins two channels on the same event loop, with back-pressure (from the NIO SSH example).
private final class Glue: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = NIOAny
    typealias OutboundIn = NIOAny
    typealias OutboundOut = NIOAny
    private var partner: Glue?
    private var context: ChannelHandlerContext?
    private var pendingRead = false

    static func matchedPair() -> (Glue, Glue) {
        let a = Glue(), b = Glue()
        a.partner = b; b.partner = a
        return (a, b)
    }

    private func partnerWrite(_ data: NIOAny) { context?.write(data, promise: nil) }
    private func partnerFlush() { context?.flush() }
    private func partnerWriteEOF() { context?.close(mode: .output, promise: nil) }
    private func partnerClose() { context?.close(promise: nil) }
    private func partnerBecameWritable() {
        if pendingRead { pendingRead = false; context?.read() }
    }
    private var partnerWritable: Bool { context?.channel.isWritable ?? false }

    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
        if context.channel.isWritable { partner?.partnerBecameWritable() }
    }
    func handlerRemoved(context: ChannelHandlerContext) { self.context = nil; partner = nil }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) { partner?.partnerWrite(data) }
    func channelReadComplete(context: ChannelHandlerContext) { partner?.partnerFlush() }
    func channelInactive(context: ChannelHandlerContext) { partner?.partnerClose() }
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? ChannelEvent, case .inputClosed = event { partner?.partnerWriteEOF() }
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) { partner?.partnerClose() }
    func channelWritabilityChanged(context: ChannelHandlerContext) {
        if context.channel.isWritable { partner?.partnerBecameWritable() }
    }
    func read(context: ChannelHandlerContext) {
        if let partner, partner.partnerWritable { context.read() } else { pendingRead = true }
    }
}
