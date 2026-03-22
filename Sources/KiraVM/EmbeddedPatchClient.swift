import Foundation
import KiraDebugRuntime

#if canImport(Network)
import Network
#endif

struct EmbeddedPatchClientConfig: Sendable {
    var appName: String
    var projectName: String
    var targetAppIdentifier: String
    var clientName: String
    var sessionID: String
    var sessionToken: String
    var patchHost: String?
    var patchPort: UInt16?
    var serviceType: String
}

#if canImport(Network)

final class EmbeddedPatchClient: @unchecked Sendable {
    private let config: EmbeddedPatchClientConfig
    private let hostBridge: KiraBytecodeHostBridge
    private let queue = DispatchQueue(label: "kira.embedded.patch-client")

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var receiveBuffer = Data()

    init(config: EmbeddedPatchClientConfig, hostBridge: KiraBytecodeHostBridge) {
        self.config = config
        self.hostBridge = hostBridge
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            if let host = self.config.patchHost, let port = self.config.patchPort {
                self.connect(host: host, port: port)
            } else {
                self.beginDiscovery()
            }
        }
    }

    private func beginDiscovery() {
        hostBridge.setConnectionStatus(false, detail: "Discovering patch server")
        let browser = NWBrowser(
            for: .bonjour(type: config.serviceType, domain: nil),
            using: .tcp
        )
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed(let error):
                self.hostBridge.setConnectionStatus(false, detail: "Patch discovery failed: \(error)")
            default:
                break
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            guard let result = results.first else { return }
            self.browser?.cancel()
            self.browser = nil
            self.connect(endpoint: result.endpoint)
        }

        browser.start(queue: queue)
    }

    private func connect(host: String, port: UInt16) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            hostBridge.setConnectionStatus(false, detail: "Invalid patch port \(port)")
            return
        }
        connect(endpoint: .hostPort(host: NWEndpoint.Host(host), port: nwPort))
    }

    private func connect(endpoint: NWEndpoint) {
        hostBridge.setConnectionStatus(false, detail: "Connecting to patch server")
        let connection = NWConnection(to: endpoint, using: .tcp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.hostBridge.setConnectionStatus(true, detail: "Connected to patch server")
                self.sendHello()
                self.receive()
            case .failed(let error):
                self.hostBridge.setConnectionStatus(false, detail: "Patch connection failed: \(error)")
            case .cancelled:
                self.hostBridge.setConnectionStatus(false, detail: "Patch connection closed")
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func sendHello() {
        let hello = KiraDebugHandshakeHello(
            sessionID: config.sessionID,
            targetAppIdentifier: config.targetAppIdentifier,
            projectName: config.projectName,
            clientName: config.clientName,
            platformName: currentPlatformName,
            runtimeABIVersion: KiraDebugProtocolVersion.runtimeABIVersion,
            bytecodeFormatVersion: KiraDebugProtocolVersion.bytecodeFormatVersion,
            hostBridgeABIVersion: KiraDebugProtocolVersion.hostBridgeABIVersion,
            currentGeneration: hostBridge.currentGeneration(),
            sessionToken: config.sessionToken
        )
        send(.init(kind: .hello, hello: hello))
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4 * 1024 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBufferedMessages()
            }

            if let error {
                self.hostBridge.setConnectionStatus(false, detail: "Patch receive failed: \(error)")
                return
            }

            if isComplete {
                self.hostBridge.setConnectionStatus(false, detail: "Patch server disconnected")
                return
            }

            self.receive()
        }
    }

    private func processBufferedMessages() {
        while let newline = receiveBuffer.firstIndex(of: 0x0A) {
            let line = receiveBuffer.prefix(upTo: newline)
            receiveBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }

            do {
                let envelope = try JSONDecoder().decode(KiraDebugWireEnvelope.self, from: Data(line))
                try handle(envelope)
            } catch {
                hostBridge.setConnectionStatus(false, detail: "Failed to decode patch message: \(error)")
            }
        }
    }

    private func handle(_ envelope: KiraDebugWireEnvelope) throws {
        switch envelope.kind {
        case .helloAck:
            guard let ack = envelope.helloAck else {
                throw NSError(
                    domain: "EmbeddedPatchClient",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing hello ack payload"]
                )
            }
            if ack.accepted {
                hostBridge.setConnectionStatus(true, detail: "Attached to session \(ack.sessionID)")
            } else {
                hostBridge.setConnectionStatus(false, detail: ack.rejectionReason ?? "Patch attach rejected")
            }

        case .patch:
            guard let patch = envelope.patch else {
                throw NSError(
                    domain: "EmbeddedPatchClient",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Missing patch payload"]
                )
            }
            try handlePatch(patch)

        case .status:
            if let status = envelope.status {
                hostBridge.setConnectionStatus(true, detail: status.detail)
            }

        case .error:
            if let error = envelope.error {
                hostBridge.setConnectionStatus(false, detail: "\(error.code): \(error.message)")
            }

        case .hello:
            break
        }
    }

    private func handlePatch(_ patch: KiraPatchBundle) throws {
        guard KiraPatchAuthenticator.validate(bundle: patch, sessionToken: config.sessionToken) else {
            let detail = "Rejected generation \(patch.manifest.generation): integrity verification failed"
            hostBridge.noteCompatibility(.fullRelaunchRequired, detail: detail)
            send(.init(
                kind: .status,
                status: .init(kind: .rejected, generation: patch.manifest.generation, detail: detail)
            ))
            return
        }

        let decision = KiraPatchCompatibilityEvaluator.evaluate(
            current: hostBridge.compatibilitySnapshot(),
            incoming: patch.manifest
        )
        let detail = decision.reasons.isEmpty
            ? "Patch generation \(patch.manifest.generation) accepted"
            : decision.reasons.joined(separator: ", ")
        hostBridge.noteCompatibility(decision.level, detail: detail)

        switch decision.level {
        case .fullRelaunchRequired:
            send(.init(
                kind: .status,
                status: .init(kind: .rejected, generation: patch.manifest.generation, detail: detail)
            ))
        case .hotPatch, .softReboot:
            do {
                try hostBridge.reloadApp(patchBundle: patch)
                let message = decision.level == .hotPatch
                    ? "Applied hot patch generation \(patch.manifest.generation)"
                    : "Applied soft reboot generation \(patch.manifest.generation)"
                send(.init(
                    kind: .status,
                    status: .init(kind: .applied, generation: patch.manifest.generation, detail: message)
                ))
            } catch {
                send(.init(
                    kind: .status,
                    status: .init(kind: .applyFailed, generation: patch.manifest.generation, detail: String(describing: error))
                ))
            }
        }
    }

    private func send(_ envelope: KiraDebugWireEnvelope) {
        guard let connection else { return }
        do {
            var data = try JSONEncoder().encode(envelope)
            data.append(0x0A)
            connection.send(content: data, completion: .contentProcessed({ _ in }))
        } catch {
            hostBridge.setConnectionStatus(false, detail: "Failed to send patch message: \(error)")
        }
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

#else

final class EmbeddedPatchClient: @unchecked Sendable {
    init(config: EmbeddedPatchClientConfig, hostBridge: KiraBytecodeHostBridge) {
        let detail = "Embedded patch client requires Apple Network.framework support"
        hostBridge.setConnectionStatus(false, detail: detail)
        _ = config
    }

    func start() {}
}

#endif
