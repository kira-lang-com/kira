import Foundation
import KiraDebugRuntime

#if canImport(Network)
import Network

public final class PatchServer: @unchecked Sendable {
    public struct Config: Sendable {
        public var appName: String
        public var projectName: String
        public var runtimeVersion: String
        public var serviceType: String
        public var localhostOnly: Bool
        public var advertiseOnLocalNetwork: Bool
        public var port: UInt16?
        public var historyLimit: Int
        public var rebuildDebounceInterval: TimeInterval

        public init(
            appName: String,
            projectName: String,
            runtimeVersion: String = "dev",
            serviceType: String = "_kira-debug._tcp",
            localhostOnly: Bool = false,
            advertiseOnLocalNetwork: Bool = true,
            port: UInt16? = nil,
            historyLimit: Int = 8,
            rebuildDebounceInterval: TimeInterval = 1.0
        ) {
            self.appName = appName
            self.projectName = projectName
            self.runtimeVersion = runtimeVersion
            self.serviceType = serviceType
            self.localhostOnly = localhostOnly
            self.advertiseOnLocalNetwork = advertiseOnLocalNetwork
            self.port = port
            self.historyLimit = historyLimit
            self.rebuildDebounceInterval = rebuildDebounceInterval
        }
    }

    public struct RuntimeSession: Sendable {
        public var sessionID: String
        public var sessionToken: String
        public var generation: Int
        public var listeningPort: UInt16

        public init(sessionID: String, sessionToken: String, generation: Int, listeningPort: UInt16) {
            self.sessionID = sessionID
            self.sessionToken = sessionToken
            self.generation = generation
            self.listeningPort = listeningPort
        }
    }

    public typealias StatusHandler = @Sendable (KiraDebugStatusMessage) -> Void

    private let config: Config
    private let compiler: PatchCompiler
    private let watcher = FileWatcher()
    private let sourceProvider: @Sendable () throws -> [SourceText]
    private let sourceFileProvider: @Sendable () throws -> [URL]
    private let prepareForBuild: @Sendable ([FileWatcher.Event]) throws -> Void
    private let watchedFiles: [URL]
    private let statusHandler: StatusHandler

    private let queue = DispatchQueue(label: "kira.patch.server")
    private var listener: NWListener?
    private var connections: [UUID: ServerConnection] = [:]
    private var watchHandle: AnyObject?
    private var generation: Int = 0
    private var bundleHistory: [KiraPatchBundle] = []
    private var pendingRebuildWorkItem: DispatchWorkItem?
    private var pendingEventsByPath: [String: FileWatcher.Event] = [:]

    public init(
        config: Config,
        compiler: PatchCompiler,
        watchedFiles: [URL],
        prepareForBuild: @escaping @Sendable ([FileWatcher.Event]) throws -> Void = { _ in },
        sourceFileProvider: @escaping @Sendable () throws -> [URL],
        sourceProvider: @escaping @Sendable () throws -> [SourceText],
        statusHandler: @escaping StatusHandler = { _ in }
    ) {
        self.config = config
        self.compiler = compiler
        self.watchedFiles = watchedFiles.sorted { $0.path < $1.path }
        self.prepareForBuild = prepareForBuild
        self.sourceFileProvider = sourceFileProvider
        self.sourceProvider = sourceProvider
        self.statusHandler = statusHandler
    }

    @discardableResult
    public func start() throws -> RuntimeSession {
        let listener: NWListener
        if let fixedPort = config.port {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: fixedPort)!)
        } else {
            listener = try NWListener(using: .tcp)
        }

        let startupSemaphore = DispatchSemaphore(value: 0)
        var startupError: Error?
        var assignedPort: UInt16?

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection: connection)
        }
        if config.advertiseOnLocalNetwork {
            listener.service = NWListener.Service(
                name: "\(config.projectName)-\(config.appName)",
                type: config.serviceType,
                txtRecord: self.makeTXTRecord()
            )
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                assignedPort = listener.port?.rawValue ?? self.config.port ?? 0
                startupSemaphore.signal()
            case .failed(let error):
                startupError = error
                startupSemaphore.signal()
                self.statusHandler(.init(kind: .applyFailed, generation: self.generation, detail: "Patch listener failed: \(error)"))
            default:
                break
            }
        }
        listener.start(queue: queue)
        self.listener = listener

        let startupResult = startupSemaphore.wait(timeout: .now() + .seconds(5))
        if let startupError {
            listener.cancel()
            self.listener = nil
            throw startupError
        }
        if startupResult == .timedOut {
            listener.cancel()
            self.listener = nil
            throw NSError(
                domain: "KiraPatchServer",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for patch listener to become ready"]
            )
        }

        self.watchHandle = watcher.watch(urls: watchedFiles) { [weak self] event in
            self?.scheduleRebuild(for: event)
        }

        let port = assignedPort ?? listener.port?.rawValue ?? config.port ?? 0
        let session = RuntimeSession(
            sessionID: compiler.sessionID,
            sessionToken: compiler.sessionToken,
            generation: generation,
            listeningPort: port
        )
        statusHandler(.init(kind: .connected, generation: generation, detail: "Patch server listening on port \(port)"))
        return session
    }

    public func stop() {
        watchHandle = nil
        pendingRebuildWorkItem?.cancel()
        pendingRebuildWorkItem = nil
        listener?.cancel()
        listener = nil
        for connection in connections.values {
            connection.connection.cancel()
        }
        connections.removeAll()
    }

    private func rebuildAndBroadcast() {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingRebuildWorkItem = nil
            let pendingEvents = self.pendingEventsByPath.values.sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.url.path < rhs.url.path
                }
                return lhs.timestamp < rhs.timestamp
            }
            self.pendingEventsByPath.removeAll()
            do {
                try self.prepareForBuild(pendingEvents)
                let sourceFiles = try self.sourceFileProvider()
                let sources = try self.sourceProvider()
                let nextGeneration = self.generation + 1
                let bundle = try self.compiler.buildPatch(
                    from: sources,
                    sourceFiles: sourceFiles,
                    generation: nextGeneration
                )
                self.generation = bundle.manifest.generation
                self.remember(bundle)
                self.statusHandler(.init(kind: .compiled, generation: self.generation, detail: "Compiled patch generation \(self.generation)"))
                self.broadcast(.init(kind: .patch, patch: bundle))
            } catch {
                let detail = String(describing: error)
                self.statusHandler(.init(kind: .compileFailed, generation: self.generation, detail: detail))
                self.broadcast(.init(
                    kind: .status,
                    status: .init(kind: .compileFailed, generation: self.generation, detail: detail)
                ))
            }
        }
    }

    private func scheduleRebuild(for event: FileWatcher.Event) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingRebuildWorkItem?.cancel()
            self.pendingEventsByPath[event.url.standardizedFileURL.path] = event
            self.statusHandler(.init(
                kind: .connected,
                generation: self.generation,
                detail: "Detected \(event.kind.rawValue) in \(event.url.lastPathComponent); scheduling patch build"
            ))
            let workItem = DispatchWorkItem { [weak self] in
                self?.rebuildAndBroadcast()
            }
            self.pendingRebuildWorkItem = workItem
            self.queue.asyncAfter(
                deadline: .now() + self.config.rebuildDebounceInterval,
                execute: workItem
            )
        }
    }

    private func accept(connection: NWConnection) {
        let id = UUID()
        let serverConnection = ServerConnection(id: id, connection: connection)
        connections[id] = serverConnection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.receive(on: serverConnection)
            case .failed, .cancelled:
                self.connections.removeValue(forKey: id)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(on serverConnection: ServerConnection) {
        serverConnection.connection.receive(minimumIncompleteLength: 1, maximumLength: 4 * 1024 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                serverConnection.buffer.append(data)
                self.processBufferedMessages(for: serverConnection)
            }
            if isComplete || error != nil {
                self.connections.removeValue(forKey: serverConnection.id)
                serverConnection.connection.cancel()
                return
            }
            self.receive(on: serverConnection)
        }
    }

    private func processBufferedMessages(for serverConnection: ServerConnection) {
        while let newline = serverConnection.buffer.firstIndex(of: 0x0A) {
            let message = serverConnection.buffer.prefix(upTo: newline)
            serverConnection.buffer.removeSubrange(...newline)
            guard !message.isEmpty else { continue }
            do {
                let envelope = try JSONDecoder().decode(KiraDebugWireEnvelope.self, from: Data(message))
                try handle(envelope: envelope, on: serverConnection)
            } catch {
                send(
                    .init(kind: .error, error: .init(code: "decode_failed", message: String(describing: error))),
                    to: serverConnection
                )
            }
        }
    }

    private func handle(envelope: KiraDebugWireEnvelope, on serverConnection: ServerConnection) throws {
        switch envelope.kind {
        case .hello:
            guard let hello = envelope.hello else {
                send(.init(kind: .error, error: .init(code: "missing_hello", message: "Missing hello payload")), to: serverConnection)
                return
            }
            guard hello.wireVersion == KiraDebugProtocolVersion.wireVersion else {
                send(.init(
                    kind: .helloAck,
                    helloAck: .init(
                        accepted: false,
                        sessionID: compiler.sessionID,
                        currentGeneration: generation,
                        rejectionReason: "Wire protocol mismatch"
                    )
                ), to: serverConnection)
                return
            }
            guard hello.sessionID == compiler.sessionID else {
                send(.init(
                    kind: .helloAck,
                    helloAck: .init(
                        accepted: false,
                        sessionID: compiler.sessionID,
                        currentGeneration: generation,
                        rejectionReason: "Session mismatch"
                    )
                ), to: serverConnection)
                return
            }
            guard hello.sessionToken == compiler.sessionToken else {
                send(.init(
                    kind: .helloAck,
                    helloAck: .init(
                        accepted: false,
                        sessionID: compiler.sessionID,
                        currentGeneration: generation,
                        rejectionReason: "Authentication failed"
                    )
                ), to: serverConnection)
                return
            }

            serverConnection.handshake = hello
            serverConnection.clientName = hello.clientName
            serverConnection.platformName = hello.platformName
            serverConnection.currentGeneration = hello.currentGeneration
            send(.init(
                kind: .helloAck,
                helloAck: .init(
                    accepted: true,
                    sessionID: compiler.sessionID,
                    currentGeneration: generation
                )
            ), to: serverConnection)
            statusHandler(.init(
                kind: .connected,
                generation: generation,
                detail: "Client attached: \(hello.clientName) on \(hello.platformName) (g\(hello.currentGeneration))"
            ))
            if let catchUpBundle = latestBundle(afterGeneration: hello.currentGeneration) {
                send(.init(kind: .patch, patch: catchUpBundle), to: serverConnection)
            }
        case .status:
            if let status = envelope.status {
                statusHandler(status)
            }
        case .error:
            if let error = envelope.error {
                statusHandler(.init(kind: .applyFailed, generation: generation, detail: "[client] \(error.code): \(error.message)"))
            }
        case .helloAck, .patch:
            break
        }
    }

    private func remember(_ bundle: KiraPatchBundle) {
        bundleHistory.append(bundle)
        if bundleHistory.count > max(1, config.historyLimit) {
            bundleHistory.removeFirst(bundleHistory.count - max(1, config.historyLimit))
        }
    }

    private func latestBundle(afterGeneration generation: Int) -> KiraPatchBundle? {
        bundleHistory.last { $0.manifest.generation > generation }
    }

    private func broadcast(_ envelope: KiraDebugWireEnvelope) {
        for connection in connections.values where connection.handshake != nil {
            send(envelope, to: connection)
        }
    }

    private func send(_ envelope: KiraDebugWireEnvelope, to serverConnection: ServerConnection) {
        do {
            var data = try JSONEncoder().encode(envelope)
            data.append(0x0A)
            serverConnection.connection.send(content: data, completion: .contentProcessed { _ in })
        } catch {
            statusHandler(.init(kind: .applyFailed, generation: generation, detail: "Failed to encode server message: \(error)"))
        }
    }

    private func makeTXTRecord() -> Data {
        let txt: [String: Data] = [
            "app": Data(config.appName.utf8),
            "project": Data(config.projectName.utf8),
            "runtime": Data(config.runtimeVersion.utf8),
            "platform": Data(currentPlatformName.utf8),
            "auth": Data("1".utf8),
        ]
        return NetService.data(fromTXTRecord: txt)
    }

    private var currentPlatformName: String {
        #if os(macOS)
        return "macOS"
        #elseif os(iOS)
        return "iOS"
        #elseif os(Linux)
        return "Linux"
        #elseif os(Windows)
        return "Windows"
        #else
        return "unknown"
        #endif
    }
}

private final class ServerConnection: @unchecked Sendable {
    let id: UUID
    let connection: NWConnection
    var buffer = Data()
    var handshake: KiraDebugHandshakeHello?
    var clientName: String?
    var platformName: String?
    var currentGeneration: Int = 0

    init(id: UUID, connection: NWConnection) {
        self.id = id
        self.connection = connection
    }
}

#else

public final class PatchServer: @unchecked Sendable {
    public struct Config: Sendable {
        public init(
            appName: String,
            projectName: String,
            runtimeVersion: String = "dev",
            serviceType: String = "_kira-debug._tcp",
            localhostOnly: Bool = false,
            advertiseOnLocalNetwork: Bool = true,
            port: UInt16? = nil,
            historyLimit: Int = 8,
            rebuildDebounceInterval: TimeInterval = 1.0
        ) {}
    }

    public struct RuntimeSession: Sendable {
        public var sessionID: String
        public var sessionToken: String
        public var generation: Int
        public var listeningPort: UInt16

        public init(sessionID: String, sessionToken: String, generation: Int, listeningPort: UInt16) {
            self.sessionID = sessionID
            self.sessionToken = sessionToken
            self.generation = generation
            self.listeningPort = listeningPort
        }
    }

    public typealias StatusHandler = @Sendable (KiraDebugStatusMessage) -> Void

    public init(
        config: Config,
        compiler: PatchCompiler,
        watchedFiles: [URL],
        prepareForBuild: @escaping @Sendable ([FileWatcher.Event]) throws -> Void = { _ in },
        sourceFileProvider: @escaping @Sendable () throws -> [URL],
        sourceProvider: @escaping @Sendable () throws -> [SourceText],
        statusHandler: @escaping StatusHandler = { _ in }
    ) {
        _ = config
        _ = compiler
        _ = watchedFiles
        _ = prepareForBuild
        _ = sourceFileProvider
        _ = sourceProvider
        _ = statusHandler
    }

    @discardableResult
    public func start() throws -> RuntimeSession {
        throw NSError(
            domain: "KiraPatchServer",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Patch server requires Network.framework on this host"]
        )
    }

    public func stop() {}
}

#endif
