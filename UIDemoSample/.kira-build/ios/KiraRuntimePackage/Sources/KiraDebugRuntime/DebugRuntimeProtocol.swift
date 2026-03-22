import Foundation

public enum KiraDebugProtocolVersion {
    public static let wireVersion = 1
    public static let runtimeABIVersion = 1
    public static let bytecodeFormatVersion = 1
    public static let hostBridgeABIVersion = 1
}

public enum KiraPatchCompatibilityLevel: String, Codable, Sendable {
    case hotPatch
    case softReboot
    case fullRelaunchRequired
}

public struct KiraPatchFunctionDigest: Codable, Hashable, Sendable {
    public var name: String
    public var signatureHash: String

    public init(name: String, signatureHash: String) {
        self.name = name
        self.signatureHash = signatureHash
    }
}

public struct KiraPatchTypeDigest: Codable, Hashable, Sendable {
    public var name: String
    public var layoutHash: String
    public var conformanceHash: String

    public init(name: String, layoutHash: String, conformanceHash: String) {
        self.name = name
        self.layoutHash = layoutHash
        self.conformanceHash = conformanceHash
    }
}

public struct KiraPatchModuleDigest: Codable, Hashable, Sendable {
    public var moduleName: String
    public var sourceFiles: [String]
    public var exportedFunctions: [KiraPatchFunctionDigest]
    public var publicTypes: [KiraPatchTypeDigest]
    public var bridgeVisibleSymbols: [String]
    public var implementationHash: String

    public init(
        moduleName: String,
        sourceFiles: [String],
        exportedFunctions: [KiraPatchFunctionDigest],
        publicTypes: [KiraPatchTypeDigest],
        bridgeVisibleSymbols: [String],
        implementationHash: String
    ) {
        self.moduleName = moduleName
        self.sourceFiles = sourceFiles
        self.exportedFunctions = exportedFunctions
        self.publicTypes = publicTypes
        self.bridgeVisibleSymbols = bridgeVisibleSymbols
        self.implementationHash = implementationHash
    }
}

public struct KiraPatchManifest: Codable, Sendable {
    public var sessionID: String
    public var generation: Int
    public var targetAppIdentifier: String
    public var projectName: String
    public var runtimeABIVersion: Int
    public var bytecodeFormatVersion: Int
    public var hostBridgeABIVersion: Int
    public var changedModules: [String]
    public var dependencyClosure: [String]
    public var modules: [KiraPatchModuleDigest]
    public var metadataHash: String
    public var integrityHash: String
    public var sessionSignature: String
    public var createdAtEpochMillis: Int64

    public init(
        sessionID: String,
        generation: Int,
        targetAppIdentifier: String,
        projectName: String,
        runtimeABIVersion: Int = KiraDebugProtocolVersion.runtimeABIVersion,
        bytecodeFormatVersion: Int = KiraDebugProtocolVersion.bytecodeFormatVersion,
        hostBridgeABIVersion: Int = KiraDebugProtocolVersion.hostBridgeABIVersion,
        changedModules: [String],
        dependencyClosure: [String],
        modules: [KiraPatchModuleDigest],
        metadataHash: String,
        integrityHash: String,
        sessionSignature: String,
        createdAtEpochMillis: Int64
    ) {
        self.sessionID = sessionID
        self.generation = generation
        self.targetAppIdentifier = targetAppIdentifier
        self.projectName = projectName
        self.runtimeABIVersion = runtimeABIVersion
        self.bytecodeFormatVersion = bytecodeFormatVersion
        self.hostBridgeABIVersion = hostBridgeABIVersion
        self.changedModules = changedModules
        self.dependencyClosure = dependencyClosure
        self.modules = modules
        self.metadataHash = metadataHash
        self.integrityHash = integrityHash
        self.sessionSignature = sessionSignature
        self.createdAtEpochMillis = createdAtEpochMillis
    }
}

public struct KiraPatchBundle: Codable, Sendable {
    public var manifest: KiraPatchManifest
    public var bytecode: Data
    public var sourceMap: Data?
    public var debugMetadata: [String: String]
    public var assetDeltas: [String: Data]

    public init(
        manifest: KiraPatchManifest,
        bytecode: Data,
        sourceMap: Data? = nil,
        debugMetadata: [String: String] = [:],
        assetDeltas: [String: Data] = [:]
    ) {
        self.manifest = manifest
        self.bytecode = bytecode
        self.sourceMap = sourceMap
        self.debugMetadata = debugMetadata
        self.assetDeltas = assetDeltas
    }
}

public struct KiraRuntimeCompatibilitySnapshot: Codable, Sendable {
    public var targetAppIdentifier: String
    public var runtimeABIVersion: Int
    public var bytecodeFormatVersion: Int
    public var hostBridgeABIVersion: Int
    public var exportedFunctions: [KiraPatchFunctionDigest]
    public var publicTypes: [KiraPatchTypeDigest]
    public var bridgeVisibleSymbols: [String]
    public var moduleImplementationHashes: [String: String]

    public init(
        targetAppIdentifier: String,
        runtimeABIVersion: Int,
        bytecodeFormatVersion: Int,
        hostBridgeABIVersion: Int,
        exportedFunctions: [KiraPatchFunctionDigest],
        publicTypes: [KiraPatchTypeDigest],
        bridgeVisibleSymbols: [String],
        moduleImplementationHashes: [String: String]
    ) {
        self.targetAppIdentifier = targetAppIdentifier
        self.runtimeABIVersion = runtimeABIVersion
        self.bytecodeFormatVersion = bytecodeFormatVersion
        self.hostBridgeABIVersion = hostBridgeABIVersion
        self.exportedFunctions = exportedFunctions
        self.publicTypes = publicTypes
        self.bridgeVisibleSymbols = bridgeVisibleSymbols
        self.moduleImplementationHashes = moduleImplementationHashes
    }

    public init(manifest: KiraPatchManifest) {
        self.targetAppIdentifier = manifest.targetAppIdentifier
        self.runtimeABIVersion = manifest.runtimeABIVersion
        self.bytecodeFormatVersion = manifest.bytecodeFormatVersion
        self.hostBridgeABIVersion = manifest.hostBridgeABIVersion
        self.exportedFunctions = manifest.modules
            .flatMap(\.exportedFunctions)
            .sorted { lhs, rhs in
                lhs.name == rhs.name ? lhs.signatureHash < rhs.signatureHash : lhs.name < rhs.name
            }
        self.publicTypes = manifest.modules
            .flatMap(\.publicTypes)
            .sorted { lhs, rhs in
                lhs.name == rhs.name ? lhs.layoutHash < rhs.layoutHash : lhs.name < rhs.name
            }
        self.bridgeVisibleSymbols = manifest.modules
            .flatMap(\.bridgeVisibleSymbols)
            .sorted()
        self.moduleImplementationHashes = Dictionary(uniqueKeysWithValues: manifest.modules.map {
            ($0.moduleName, $0.implementationHash)
        })
    }
}

public struct KiraPatchCompatibilityDecision: Codable, Sendable {
    public var level: KiraPatchCompatibilityLevel
    public var reasons: [String]

    public init(level: KiraPatchCompatibilityLevel, reasons: [String]) {
        self.level = level
        self.reasons = reasons
    }
}

public enum KiraPatchCompatibilityEvaluator {
    public static func evaluate(
        current: KiraRuntimeCompatibilitySnapshot,
        incoming manifest: KiraPatchManifest
    ) -> KiraPatchCompatibilityDecision {
        var reasons: [String] = []

        if current.targetAppIdentifier != manifest.targetAppIdentifier {
            reasons.append("target app identifier changed")
            return .init(level: .fullRelaunchRequired, reasons: reasons)
        }
        if current.runtimeABIVersion != manifest.runtimeABIVersion {
            reasons.append("runtime ABI version changed")
            return .init(level: .fullRelaunchRequired, reasons: reasons)
        }
        if current.bytecodeFormatVersion != manifest.bytecodeFormatVersion {
            reasons.append("bytecode format version changed")
            return .init(level: .fullRelaunchRequired, reasons: reasons)
        }
        if current.hostBridgeABIVersion != manifest.hostBridgeABIVersion {
            reasons.append("host bridge ABI version changed")
            return .init(level: .fullRelaunchRequired, reasons: reasons)
        }

        let incomingSnapshot = KiraRuntimeCompatibilitySnapshot(manifest: manifest)
        if current.exportedFunctions != incomingSnapshot.exportedFunctions {
            reasons.append("exported function signatures changed")
        }
        if current.publicTypes != incomingSnapshot.publicTypes {
            reasons.append("public type layouts changed")
        }
        if current.bridgeVisibleSymbols != incomingSnapshot.bridgeVisibleSymbols {
            reasons.append("bridge-visible symbol set changed")
        }

        if !reasons.isEmpty {
            return .init(level: .softReboot, reasons: reasons)
        }

        if current.moduleImplementationHashes != incomingSnapshot.moduleImplementationHashes {
            reasons.append("implementation bytecode changed")
        }

        return .init(level: .hotPatch, reasons: reasons)
    }
}

public struct KiraPatchServiceInfo: Codable, Sendable {
    public var appName: String
    public var projectName: String
    public var runtimeVersion: String
    public var deviceName: String
    public var platformName: String
    public var port: UInt16
    public var authRequired: Bool

    public init(
        appName: String,
        projectName: String,
        runtimeVersion: String,
        deviceName: String,
        platformName: String,
        port: UInt16,
        authRequired: Bool
    ) {
        self.appName = appName
        self.projectName = projectName
        self.runtimeVersion = runtimeVersion
        self.deviceName = deviceName
        self.platformName = platformName
        self.port = port
        self.authRequired = authRequired
    }
}

public struct KiraDebugHandshakeHello: Codable, Sendable {
    public var wireVersion: Int
    public var sessionID: String
    public var targetAppIdentifier: String
    public var projectName: String
    public var clientName: String
    public var platformName: String
    public var runtimeABIVersion: Int
    public var bytecodeFormatVersion: Int
    public var hostBridgeABIVersion: Int
    public var currentGeneration: Int
    public var sessionToken: String

    public init(
        wireVersion: Int = KiraDebugProtocolVersion.wireVersion,
        sessionID: String,
        targetAppIdentifier: String,
        projectName: String,
        clientName: String,
        platformName: String,
        runtimeABIVersion: Int,
        bytecodeFormatVersion: Int,
        hostBridgeABIVersion: Int,
        currentGeneration: Int,
        sessionToken: String
    ) {
        self.wireVersion = wireVersion
        self.sessionID = sessionID
        self.targetAppIdentifier = targetAppIdentifier
        self.projectName = projectName
        self.clientName = clientName
        self.platformName = platformName
        self.runtimeABIVersion = runtimeABIVersion
        self.bytecodeFormatVersion = bytecodeFormatVersion
        self.hostBridgeABIVersion = hostBridgeABIVersion
        self.currentGeneration = currentGeneration
        self.sessionToken = sessionToken
    }
}

public struct KiraDebugHandshakeAck: Codable, Sendable {
    public var accepted: Bool
    public var sessionID: String
    public var currentGeneration: Int
    public var wireVersion: Int
    public var rejectionReason: String?

    public init(
        accepted: Bool,
        sessionID: String,
        currentGeneration: Int,
        wireVersion: Int = KiraDebugProtocolVersion.wireVersion,
        rejectionReason: String? = nil
    ) {
        self.accepted = accepted
        self.sessionID = sessionID
        self.currentGeneration = currentGeneration
        self.wireVersion = wireVersion
        self.rejectionReason = rejectionReason
    }
}

public struct KiraDebugStatusMessage: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case connected
        case compiled
        case compileFailed
        case applied
        case applyFailed
        case rejected
    }

    public var kind: Kind
    public var generation: Int
    public var detail: String

    public init(kind: Kind, generation: Int, detail: String) {
        self.kind = kind
        self.generation = generation
        self.detail = detail
    }
}

public struct KiraDebugErrorMessage: Codable, Sendable {
    public var code: String
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct KiraDebugWireEnvelope: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case hello
        case helloAck
        case patch
        case status
        case error
    }

    public var kind: Kind
    public var hello: KiraDebugHandshakeHello?
    public var helloAck: KiraDebugHandshakeAck?
    public var patch: KiraPatchBundle?
    public var status: KiraDebugStatusMessage?
    public var error: KiraDebugErrorMessage?

    public init(
        kind: Kind,
        hello: KiraDebugHandshakeHello? = nil,
        helloAck: KiraDebugHandshakeAck? = nil,
        patch: KiraPatchBundle? = nil,
        status: KiraDebugStatusMessage? = nil,
        error: KiraDebugErrorMessage? = nil
    ) {
        self.kind = kind
        self.hello = hello
        self.helloAck = helloAck
        self.patch = patch
        self.status = status
        self.error = error
    }
}

public enum KiraPatchAuthenticator {
    public static func metadataHash(for modules: [KiraPatchModuleDigest]) -> String {
        let components = modules
            .sorted { $0.moduleName < $1.moduleName }
            .flatMap { module in
                [
                    module.moduleName,
                    module.sourceFiles.sorted().joined(separator: ","),
                    module.exportedFunctions
                        .sorted { $0.name < $1.name }
                        .map { "\($0.name)=\($0.signatureHash)" }
                        .joined(separator: ","),
                    module.publicTypes
                        .sorted { $0.name < $1.name }
                        .map { "\($0.name)=\($0.layoutHash):\($0.conformanceHash)" }
                        .joined(separator: ","),
                    module.bridgeVisibleSymbols.sorted().joined(separator: ","),
                    module.implementationHash,
                ]
            }
        return KiraDebugHashing.stableHash(components: components)
    }

    public static func integrityHash(bytecode: Data, metadataHash: String) -> String {
        KiraDebugHashing.sha256Hex(Data(metadataHash.utf8) + bytecode)
    }

    public static func sessionSignature(sessionID: String, token: String, integrityHash: String, generation: Int) -> String {
        KiraDebugHashing.sha256Hex([sessionID, token, integrityHash, String(generation)].joined(separator: "|"))
    }

    public static func validate(bundle: KiraPatchBundle, sessionToken: String) -> Bool {
        let metadataHash = metadataHash(for: bundle.manifest.modules)
        guard metadataHash == bundle.manifest.metadataHash else { return false }
        let integrityHash = integrityHash(bytecode: bundle.bytecode, metadataHash: metadataHash)
        guard integrityHash == bundle.manifest.integrityHash else { return false }
        let signature = sessionSignature(
            sessionID: bundle.manifest.sessionID,
            token: sessionToken,
            integrityHash: integrityHash,
            generation: bundle.manifest.generation
        )
        return signature == bundle.manifest.sessionSignature
    }
}
