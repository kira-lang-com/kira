import Foundation
import KiraDebugRuntime

public struct KiraRuntimeDebugStatus: Sendable {
    public var connected: Bool
    public var generation: Int
    public var lastMessage: String
    public var lastCompatibilityLevel: KiraPatchCompatibilityLevel?

    public init(
        connected: Bool = false,
        generation: Int = 0,
        lastMessage: String = "",
        lastCompatibilityLevel: KiraPatchCompatibilityLevel? = nil
    ) {
        self.connected = connected
        self.generation = generation
        self.lastMessage = lastMessage
        self.lastCompatibilityLevel = lastCompatibilityLevel
    }
}

public struct KiraEmbeddedRuntimeConfig: Sendable {
    public var appName: String
    public var projectName: String
    public var targetAppIdentifier: String
    public var entryFunction: String
    public var initialBytecodeURL: URL
    public var initialManifestURL: URL?
    public var debugModeEnabled: Bool
    public var sessionID: String?
    public var sessionToken: String?
    public var patchHost: String?
    public var patchPort: UInt16?
    public var serviceType: String
    public var clientName: String
    public var suspendFunction: String?
    public var disposeFunction: String?
    public var reloadStableStateSnapshotFunction: String?
    public var reloadStableStateRestoreFunction: String?
    public var postReloadFunction: String?

    public init(
        appName: String,
        projectName: String,
        targetAppIdentifier: String,
        entryFunction: String = "main",
        initialBytecodeURL: URL,
        initialManifestURL: URL? = nil,
        debugModeEnabled: Bool,
        sessionID: String? = nil,
        sessionToken: String? = nil,
        patchHost: String? = nil,
        patchPort: UInt16? = nil,
        serviceType: String = "_kira-debug._tcp",
        clientName: String = ProcessInfo.processInfo.hostName,
        suspendFunction: String? = "__kira_suspend",
        disposeFunction: String? = "__kira_dispose",
        reloadStableStateSnapshotFunction: String? = "__kira_debug_snapshot_state",
        reloadStableStateRestoreFunction: String? = "__kira_debug_restore_state",
        postReloadFunction: String? = "graphics_on_reload"
    ) {
        self.appName = appName
        self.projectName = projectName
        self.targetAppIdentifier = targetAppIdentifier
        self.entryFunction = entryFunction
        self.initialBytecodeURL = initialBytecodeURL
        self.initialManifestURL = initialManifestURL
        self.debugModeEnabled = debugModeEnabled
        self.sessionID = sessionID
        self.sessionToken = sessionToken
        self.patchHost = patchHost
        self.patchPort = patchPort
        self.serviceType = serviceType
        self.clientName = clientName
        self.suspendFunction = suspendFunction
        self.disposeFunction = disposeFunction
        self.reloadStableStateSnapshotFunction = reloadStableStateSnapshotFunction
        self.reloadStableStateRestoreFunction = reloadStableStateRestoreFunction
        self.postReloadFunction = postReloadFunction
    }
}

public protocol KiraHostBridge: AnyObject, Sendable {
    func boot(runtimeConfig: KiraEmbeddedRuntimeConfig) throws
    func attach(surface: AnyObject?)
    func loadInitialApp(entryModule: String) throws
    func reloadApp(patchBundle: KiraPatchBundle) throws
    func disposeApp()
    func currentGeneration() -> Int
    func debugStatus() -> KiraRuntimeDebugStatus
    func compatibilitySnapshot() -> KiraRuntimeCompatibilitySnapshot
    func runCallback(named functionName: String, args: [KiraValue])
}

public final class KiraBytecodeHostBridge: KiraHostBridge, @unchecked Sendable {
    private let queue = DispatchQueue(label: "kira.host.bridge")
    private let output: @Sendable (String) -> Void
    private var config: KiraEmbeddedRuntimeConfig?
    private var vm: VirtualMachine?
    private var manifestSnapshot: KiraRuntimeCompatibilitySnapshot?
    private var status = KiraRuntimeDebugStatus()
    private var pendingBundle: KiraPatchBundle?
    private var isExecutingCallback = false

    public init(output: @escaping @Sendable (String) -> Void = { print($0) }) {
        self.output = output
    }

    public func boot(runtimeConfig: KiraEmbeddedRuntimeConfig) throws {
        try queue.sync {
            self.config = runtimeConfig
            self.status = KiraRuntimeDebugStatus(
                connected: false,
                generation: 0,
                lastMessage: "Booting \(runtimeConfig.appName)"
            )
            try self.loadRuntime(
                bytecode: Data(contentsOf: runtimeConfig.initialBytecodeURL),
                manifestData: try runtimeConfig.initialManifestURL.map { try Data(contentsOf: $0) },
                generation: 0,
                entryFunction: runtimeConfig.entryFunction
            )
        }
    }

    public func attach(surface: AnyObject?) {
        _ = surface
    }

    public func loadInitialApp(entryModule: String) throws {
        try queue.sync {
            guard let config else { return }
            try self.loadRuntime(
                bytecode: Data(contentsOf: config.initialBytecodeURL),
                manifestData: try config.initialManifestURL.map { try Data(contentsOf: $0) },
                generation: 0,
                entryFunction: entryModule
            )
        }
    }

    public func reloadApp(patchBundle: KiraPatchBundle) throws {
        try queue.sync {
            pendingBundle = patchBundle
            try applyPendingPatchIfSafe()
        }
    }

    public func disposeApp() {
        queue.sync {
            if let vm, let disposeFunction = config?.disposeFunction {
                try? invokeOptionalFunction(named: disposeFunction, on: vm)
            }
            vm = nil
        }
    }

    public func currentGeneration() -> Int {
        queue.sync { status.generation }
    }

    public func debugStatus() -> KiraRuntimeDebugStatus {
        queue.sync { status }
    }

    public func compatibilitySnapshot() -> KiraRuntimeCompatibilitySnapshot {
        queue.sync {
            manifestSnapshot ?? KiraRuntimeCompatibilitySnapshot(
                targetAppIdentifier: config?.targetAppIdentifier ?? "",
                runtimeABIVersion: KiraDebugProtocolVersion.runtimeABIVersion,
                bytecodeFormatVersion: KiraDebugProtocolVersion.bytecodeFormatVersion,
                hostBridgeABIVersion: KiraDebugProtocolVersion.hostBridgeABIVersion,
                exportedFunctions: [],
                publicTypes: [],
                bridgeVisibleSymbols: [],
                moduleImplementationHashes: [:]
            )
        }
    }

    public func runCallback(named functionName: String, args: [KiraValue] = []) {
        queue.sync {
            isExecutingCallback = true
            defer {
                isExecutingCallback = false
                do {
                    try applyPendingPatchIfSafe()
                } catch {
                    status.lastMessage = "Deferred patch apply failed: \(error)"
                }
            }

            guard let vm else {
                status.lastMessage = "Runtime not prepared for \(functionName)"
                return
            }
            do {
                _ = try vm.run(function: functionName, args: args)
            } catch {
                status.lastMessage = "\(functionName) failed: \(error)"
            }
        }
    }

    public func setConnectionStatus(_ connected: Bool, detail: String) {
        queue.sync {
            status.connected = connected
            status.lastMessage = detail
        }
    }

    public func noteCompatibility(_ level: KiraPatchCompatibilityLevel, detail: String) {
        queue.sync {
            status.lastCompatibilityLevel = level
            status.lastMessage = detail
        }
    }

    private func applyPendingPatchIfSafe() throws {
        guard !isExecutingCallback, let bundle = pendingBundle else {
            return
        }
        pendingBundle = nil

        let currentSnapshot = manifestSnapshot ?? compatibilitySnapshot()
        let decision = KiraPatchCompatibilityEvaluator.evaluate(
            current: currentSnapshot,
            incoming: bundle.manifest
        )
        status.lastCompatibilityLevel = decision.level

        switch decision.level {
        case .fullRelaunchRequired:
            pendingBundle = bundle
            throw NSError(
                domain: "KiraHostBridge",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: decision.reasons.joined(separator: ", ")]
            )
        case .hotPatch, .softReboot:
            let previousVM = vm
            if let previousVM, let suspendFunction = config?.suspendFunction {
                try? invokeOptionalFunction(named: suspendFunction, on: previousVM)
            }
            let stateSnapshot = try previousVM.flatMap(captureReloadStableState(from:))
            try loadRuntime(
                bytecode: bundle.bytecode,
                manifestData: try JSONEncoder().encode(bundle.manifest),
                generation: bundle.manifest.generation,
                entryFunction: config?.entryFunction ?? "main",
                restoredStatePayload: stateSnapshot
            )
            if let previousVM, let disposeFunction = config?.disposeFunction {
                try? invokeOptionalFunction(named: disposeFunction, on: previousVM)
            }
            status.lastMessage = decision.level == .hotPatch
                ? "Applied hot patch generation \(bundle.manifest.generation)"
                : "Applied soft reboot generation \(bundle.manifest.generation)"
        }
    }

    private func loadRuntime(
        bytecode: Data,
        manifestData: Data?,
        generation: Int,
        entryFunction: String,
        restoredStatePayload: String? = nil
    ) throws {
        let module = try BytecodeLoader().load(data: bytecode)
        let loadedVM = VirtualMachine(module: module, output: output)

        if module.functions.contains(where: { $0.name == "__kira_init_globals" }) {
            _ = try loadedVM.run(function: "__kira_init_globals")
        }
        _ = try loadedVM.run(function: entryFunction)
        try restoreReloadStableState(restoredStatePayload, into: loadedVM)
        if generation > 0, let postReloadFunction = config?.postReloadFunction {
            try invokeOptionalFunction(named: postReloadFunction, on: loadedVM)
        }

        vm = loadedVM
        status.generation = generation

        if let manifestData {
            if let manifest = try? JSONDecoder().decode(KiraPatchManifest.self, from: manifestData) {
                manifestSnapshot = KiraRuntimeCompatibilitySnapshot(manifest: manifest)
            } else if let snapshot = try? JSONDecoder().decode(KiraRuntimeCompatibilitySnapshot.self, from: manifestData) {
                manifestSnapshot = snapshot
            }
        }
    }

    private func captureReloadStableState(from vm: VirtualMachine) throws -> String? {
        guard let functionName = config?.reloadStableStateSnapshotFunction else {
            return nil
        }
        guard vm.module.functions.contains(where: { $0.name == functionName }) else {
            return nil
        }

        let value = try vm.run(function: functionName)
        switch value {
        case .nil_:
            return nil
        case .reference(let ref):
            let object = try vm.heap.get(ref)
            guard let string = object as? KiraString else {
                throw NSError(
                    domain: "KiraHostBridge",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "reload-stable snapshot must return String or nil"]
                )
            }
            return string.value
        default:
            throw NSError(
                domain: "KiraHostBridge",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "reload-stable snapshot must return String or nil"]
            )
        }
    }

    private func restoreReloadStableState(_ payload: String?, into vm: VirtualMachine) throws {
        guard let payload else {
            return
        }
        guard let functionName = config?.reloadStableStateRestoreFunction else {
            return
        }
        guard vm.module.functions.contains(where: { $0.name == functionName }) else {
            return
        }

        let ref = vm.heap.allocate(KiraString(payload))
        _ = try vm.run(function: functionName, args: [.reference(ref)])
    }

    private func invokeOptionalFunction(named functionName: String, on vm: VirtualMachine) throws {
        guard vm.module.functions.contains(where: { $0.name == functionName }) else {
            return
        }
        _ = try vm.run(function: functionName)
    }
}

public final class KiraEmbeddedAppController: @unchecked Sendable {
    private let hostBridge: KiraBytecodeHostBridge
    private var patchClient: EmbeddedPatchClient?

    public init(hostBridge: KiraBytecodeHostBridge = KiraBytecodeHostBridge()) {
        self.hostBridge = hostBridge
    }

    public func prepare(config: KiraEmbeddedRuntimeConfig) throws {
        try hostBridge.boot(runtimeConfig: config)
        guard config.debugModeEnabled, let sessionID = config.sessionID, let sessionToken = config.sessionToken else {
            return
        }
        let client = EmbeddedPatchClient(
            config: .init(
                appName: config.appName,
                projectName: config.projectName,
                targetAppIdentifier: config.targetAppIdentifier,
                clientName: config.clientName,
                sessionID: sessionID,
                sessionToken: sessionToken,
                patchHost: config.patchHost,
                patchPort: config.patchPort,
                serviceType: config.serviceType
            ),
            hostBridge: hostBridge
        )
        patchClient = client
        client.start()
    }

    public func runCallback(named functionName: String) {
        hostBridge.runCallback(named: functionName, args: [])
    }

    public func runCallback(named functionName: String, args: [KiraValue]) {
        hostBridge.runCallback(named: functionName, args: args)
    }

    public func debugStatus() -> KiraRuntimeDebugStatus {
        hostBridge.debugStatus()
    }
}
