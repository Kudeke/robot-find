import Foundation
import Citadel
import NIOSSH
import NIOCore
import NIOPosix

final class SSHConnectionManager: ObservableObject {
    @Published private(set) var state: SSHConnectionState = .disconnected
    @Published private(set) var localBaseURL: URL?

    private var sshClient: SSHClient?
    private var localListener: Channel?
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var forwardingChannels: [Channel] = []
    private let healthClient = ServerHealthClient()

    func connectAndCheckHealth(config: ServerConnectionConfig) async {
        await MainActor.run { self.state = .connecting }
        do {
            try validate(config)
            await MainActor.run { self.state = .authenticating }
            let client = try await withTimeout(seconds: 15) {
                try await self.connectSSH(config: config)
            }
            sshClient = client
            await MainActor.run { self.state = .forwarding }
            let baseURL = try await startLocalForwarding(client: client, config: config)
            localBaseURL = baseURL
            await MainActor.run { self.state = .checkingHealth }
            _ = try await withTimeout(seconds: 15) {
                try await self.healthClient.check(baseURL: baseURL)
            }
            print("[Connection] server ready")
            await MainActor.run { self.state = .connected }
        } catch {
            await disconnect()
            let connectionError = classify(error)
            await MainActor.run { self.state = .failed(connectionError.localizedDescription) }
        }
    }

    func disconnect() async {
        localBaseURL = nil
        for channel in forwardingChannels {
            try? await channel.close()
        }
        forwardingChannels.removeAll()
        try? await localListener?.close()
        localListener = nil
        try? await sshClient?.close()
        sshClient = nil
        if let eventLoopGroup {
            try? await eventLoopGroup.shutdownGracefully()
        }
        self.eventLoopGroup = nil
        await MainActor.run { self.state = .disconnected }
    }

    private func connectSSH(config: ServerConnectionConfig) async throws -> SSHClient {
        print("[SSH] connecting host=\(config.host) port=\(config.sshPort)")
        do {
            let settings = SSHClientSettings(
                host: config.host,
                port: config.sshPort,
                authenticationMethod: { .passwordBased(username: config.username, password: config.password) },
                hostKeyValidator: .acceptAnything()
            )
            let client = try await SSHClient.connect(to: settings)
            print("[SSH] authentication succeeded")
            return client
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("auth") || message.contains("password") || message.contains("credential") {
                throw SSHConnectionError.authenticationFailed
            }
            throw SSHConnectionError.networkFailure(error.localizedDescription)
        }
    }

    private func startLocalForwarding(client: SSHClient, config: ServerConnectionConfig) async throws -> URL {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        eventLoopGroup = group
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 16)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { localChannel in
                let localHandler = LocalForwardingHandler()
                let promise = localChannel.eventLoop.makePromise(of: Void.self)
                localChannel.pipeline.addHandler(localHandler).whenComplete { result in
                    guard case .success = result else {
                        promise.fail(SSHConnectionError.forwardingFailed("Local socket setup failed."))
                        return
                    }
                    Task { [weak self, weak localChannel] in
                        guard let self, let localChannel else {
                            promise.fail(SSHConnectionError.forwardingFailed("Local socket closed."))
                            return
                        }
                        do {
                            let originator = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
                            var remoteHandler: LocalForwardingHandler?
                            let remoteChannel = try await client.createDirectTCPIPChannel(
                                using: SSHChannelType.DirectTCPIP(
                                    targetHost: "127.0.0.1",
                                    targetPort: config.remoteAPIPort,
                                    originatorAddress: originator
                                )
                            ) { proxyChannel in
                                let handler = LocalForwardingHandler()
                                remoteHandler = handler
                                return proxyChannel.pipeline.addHandler(handler)
                            }
                            guard let remoteHandler else {
                                throw SSHConnectionError.forwardingFailed("Remote channel setup failed.")
                            }
                            localHandler.setPeer(remoteChannel)
                            remoteHandler.setPeer(localChannel)
                            self.forwardingChannels.append(remoteChannel)
                            promise.succeed(())
                        } catch {
                            promise.fail(error)
                            localChannel.close(promise: nil)
                        }
                    }
                }
                return promise.futureResult
            }

        do {
            let listener = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
            localListener = listener
            guard let address = listener.localAddress,
                  let port = address.port else {
                throw SSHConnectionError.forwardingFailed("No local port was assigned.")
            }
            print("[SSH] local forwarding started port=\(port)")
            return URL(string: "http://127.0.0.1:\(port)")!
        } catch {
            throw SSHConnectionError.forwardingFailed(error.localizedDescription)
        }
    }

    private func validate(_ config: ServerConnectionConfig) throws {
        guard !config.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !config.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !config.password.isEmpty,
              (1...65535).contains(config.sshPort),
              (1...65535).contains(config.remoteAPIPort) else {
            throw SSHConnectionError.invalidConfiguration
        }
    }

    private func classify(_ error: Error) -> SSHConnectionError {
        if let error = error as? SSHConnectionError { return error }
        return .networkFailure(error.localizedDescription)
    }

    private func withTimeout<T>(seconds: UInt64, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw SSHConnectionError.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}

private final class LocalForwardingHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private var peer: Channel?
    private var pending: [ByteBuffer] = []

    func setPeer(_ peer: Channel) {
        self.peer = peer
        for buffer in pending {
            peer.writeAndFlush(buffer, promise: nil)
        }
        pending.removeAll()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        if let peer {
            peer.writeAndFlush(buffer, promise: nil)
        } else {
            pending.append(buffer)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        peer?.close(promise: nil)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        peer?.close(promise: nil)
        context.close(promise: nil)
    }
}
