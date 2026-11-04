// SPDX-License-Identifier: AGPL-3.0-or-later
// Loopback TCP endpoint for the guest relay (relay.cjs). Same rules as
// 原 Flutter 版 lib/phone_ios/phone_ios_server.dart: 127.0.0.1 only, random port,
// per-launch 32-byte token, first line must be {"dshPhone":1,"token":...}.
//
// Plain BSD sockets on purpose: on iOS an NWListener counts as a local-network
// service and its connections are dropped before delivery, while a socket bound
// to 127.0.0.1 (what Dart's ServerSocket uses) is not subject to that policy.
import Darwin
import Foundation
import Security

public final class PhoneBridgeServer: @unchecked Sendable {
    public struct LaunchConfig: Sendable {
        public let port: Int
        /// Private launch secret: never log it or publish it as an event.
        public let token: String
        public var json: String { "{\"v\":1,\"tcpPort\":\(port),\"token\":\"\(token)\"}" }
    }

    private let mcp: McpServer
    private let queue = DispatchQueue(label: "dsh.phone.bridge")
    // All state below is owned by `queue`.
    private var listenSource: DispatchSourceRead?
    private var clients: [Int32: Client] = [:]
    private var token: String?
    private var generation = 0
    private var events: [String] = []

    /// Connection lifecycle notes (no secrets) for diagnostics.
    public var diagnostics: [String] { queue.sync { events } }
    private func note(_ text: String) { events.append(text); if events.count > 50 { events.removeFirst() } }

    public init(mcp: McpServer) { self.mcp = mcp }

    private final class Client: @unchecked Sendable {
        let fd: Int32
        let context = PhoneCallContext()
        var source: DispatchSourceRead?
        var buffer = Data()
        var authed = false
        var pending = 0
        var closed = false
        init(fd: Int32) { self.fd = fd }
    }

    /// Starts a fresh listener and token.
    public func start() async throws -> LaunchConfig {
        await stop()
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw PhoneError("E_PHONE_RANDOM") }
        let secret = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        return try queue.sync {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { throw PhoneError("E_PHONE_LISTEN") }
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
            address.sin_port = 0; address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            var actual = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let named = withUnsafeMutablePointer(to: &actual) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
            }
            guard bound == 0, Darwin.listen(fd, 8) == 0, named == 0, fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
                Darwin.close(fd); throw PhoneError("E_PHONE_LISTEN")
            }
            generation += 1
            let current = generation
            token = secret
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.acceptAll(fd, generation: current) }
            source.setCancelHandler { Darwin.close(fd) }
            listenSource = source
            source.resume()
            note("start gen \(current)")
            return LaunchConfig(port: Int(UInt16(bigEndian: actual.sin_port)), token: secret)
        }
    }

    public func stop() async {
        queue.sync {
            generation += 1; token = nil
            note("stop -> gen \(generation)")
            listenSource?.cancel(); listenSource = nil
            for client in Array(clients.values) { close(client) }
        }
    }

    private func matches(_ value: Any?) -> Bool {
        guard let given = value as? String, let expected = token, given.utf8.count == expected.utf8.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(given.utf8, expected.utf8) { diff |= a ^ b }
        return diff == 0
    }

    // MARK: Connections (all on `queue`)

    private func acceptAll(_ listenFD: Int32, generation current: Int) {
        while true {
            let fd = Darwin.accept(listenFD, nil, nil)
            if fd < 0 { return } // EAGAIN: drained.
            guard current == generation, clients.count < 8 else {
                note("reject accept: gen \(current) now \(generation), clients \(clients.count)")
                Darwin.close(fd); continue
            }
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &on, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(fd, F_SETFL, O_NONBLOCK)
            let client = Client(fd: fd)
            clients[fd] = client
            note("accept gen \(current)")
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.read(client, generation: current) }
            source.setCancelHandler { Darwin.close(fd) }
            client.source = source
            source.resume()
            queue.asyncAfter(deadline: .now() + 3) { [weak self] in
                if !client.authed && !client.closed { self?.note("auth timeout"); self?.close(client) }
            }
        }
    }

    private func close(_ client: Client) {
        guard !client.closed else { return }
        client.closed = true
        client.context.cancel()
        client.source?.cancel() // Closes the descriptor in the cancel handler.
        clients[client.fd] = nil
    }

    private func read(_ client: Client, generation current: Int) {
        var chunk = [UInt8](repeating: 0, count: 65536)
        while !client.closed {
            let count = Darwin.read(client.fd, &chunk, chunk.count)
            if count > 0 {
                client.buffer.append(contentsOf: chunk[0..<count])
                if !consume(client, generation: current) { close(client); return }
            } else if count == 0 {
                close(client); return // Peer closed.
            } else {
                if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { return }
                close(client); return
            }
        }
    }

    /// Splits complete lines; returns false when the peer must be dropped.
    private func consume(_ client: Client, generation current: Int) -> Bool {
        while let newline = client.buffer.firstIndex(of: 10) {
            let bytes = client.buffer[client.buffer.startIndex..<newline]
            client.buffer.removeSubrange(client.buffer.startIndex...newline)
            guard let line = String(data: bytes, encoding: .utf8) else { return false }
            if !client.authed {
                guard let hello = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      (hello["dshPhone"] as? NSNumber)?.intValue == 1, matches(hello["token"]) else {
                    note("hello rejected"); return false
                }
                client.authed = true; note("authed")
                continue
            }
            client.pending += 1
            guard client.pending <= 16 else { return false }
            // Tool calls are not awaited in the input loop: pings stay responsive
            // while a tool waits for the person (up to ten minutes).
            Task { [weak self] in
                let reply = await self?.mcp.handle(line, context: client.context)
                self?.queue.async {
                    guard let self else { return }
                    client.pending -= 1
                    guard let reply, current == self.generation, !client.closed else { return }
                    guard self.write(client, Data((reply.line + "\n").utf8)) else { self.close(client); return }
                    if let after = reply.afterSend { Task { await after() } }
                }
            }
        }
        return client.buffer.count <= (client.authed ? 262_144 : 1024)
    }

    /// Writes the whole buffer (replies are small; waits briefly if the socket is full).
    private func write(_ client: Client, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var offset = 0, waited = 0
            while offset < data.count {
                let sent = Darwin.write(client.fd, base + offset, data.count - offset)
                if sent > 0 { offset += sent; continue }
                if sent < 0 && errno == EINTR { continue }
                if sent < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) && waited < 200 {
                    var poller = pollfd(fd: client.fd, events: Int16(POLLOUT), revents: 0)
                    _ = poll(&poller, 1, 10); waited += 1; continue
                }
                return false
            }
            return true
        }
    }
}
