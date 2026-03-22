import Foundation
import KiraDebugRuntime

public final class PatchCompiler: @unchecked Sendable {
    public struct Config: Sendable {
        public var sessionID: String
        public var sessionToken: String
        public var projectName: String
        public var targetAppIdentifier: String
        public var target: PlatformTarget

        public init(
            sessionID: String,
            sessionToken: String,
            projectName: String,
            targetAppIdentifier: String,
            target: PlatformTarget
        ) {
            self.sessionID = sessionID
            self.sessionToken = sessionToken
            self.projectName = projectName
            self.targetAppIdentifier = targetAppIdentifier
            self.target = target
        }
    }

    public struct FileSnapshot: Sendable {
        public var url: URL
        public var contentHash: String

        public init(url: URL, contentHash: String) {
            self.url = url
            self.contentHash = contentHash
        }
    }

    private let config: Config
    private let driver: CompilerDriver
    private var lastContentHashes: [String: String] = [:]
    private let encoder = JSONEncoder()

    public init(config: Config, driver: CompilerDriver = CompilerDriver()) {
        self.config = config
        self.driver = driver
        self.encoder.outputFormatting = [.sortedKeys]
    }

    public var sessionID: String { config.sessionID }

    public var sessionToken: String { config.sessionToken }

    public var targetAppIdentifier: String { config.targetAppIdentifier }

    public var projectName: String { config.projectName }

    public func changedFiles(in urls: [URL]) throws -> [FileSnapshot] {
        let snapshots = try urls.sorted { $0.path < $1.path }.map { url in
            let data = try Data(contentsOf: url)
            return FileSnapshot(url: url, contentHash: KiraDebugHashing.sha256Hex(data))
        }

        return snapshots.filter { snapshot in
            lastContentHashes[snapshot.url.path] != snapshot.contentHash
        }
    }

    public func buildPatch(
        from sources: [SourceText],
        sourceFiles: [URL],
        generation: Int
    ) throws -> KiraPatchBundle {
        let changed = try changedFiles(in: sourceFiles)
        let output = try driver.compile(sources: sources, target: config.target)
        guard let bytecode = output.bytecode else {
            throw NSError(
                domain: "KiraPatchCompiler",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing bytecode output for patch generation"]
            )
        }

        let digests = buildModuleDigests(typed: output.typed, sourceTexts: sources)
        let metadataHash = KiraPatchAuthenticator.metadataHash(for: digests)
        let integrityHash = KiraPatchAuthenticator.integrityHash(bytecode: bytecode, metadataHash: metadataHash)
        let signature = KiraPatchAuthenticator.sessionSignature(
            sessionID: config.sessionID,
            token: config.sessionToken,
            integrityHash: integrityHash,
            generation: generation
        )

        let manifest = KiraPatchManifest(
            sessionID: config.sessionID,
            generation: generation,
            targetAppIdentifier: config.targetAppIdentifier,
            projectName: config.projectName,
            changedModules: changed.map { moduleIdentifier(for: $0.url.path) },
            dependencyClosure: digests.map(\.moduleName).sorted(),
            modules: digests.sorted { $0.moduleName < $1.moduleName },
            metadataHash: metadataHash,
            integrityHash: integrityHash,
            sessionSignature: signature,
            createdAtEpochMillis: Int64(Date().timeIntervalSince1970 * 1000.0)
        )

        for snapshot in changed {
            lastContentHashes[snapshot.url.path] = snapshot.contentHash
        }
        for url in sourceFiles where lastContentHashes[url.path] == nil {
            let data = try Data(contentsOf: url)
            lastContentHashes[url.path] = KiraDebugHashing.sha256Hex(data)
        }

        return KiraPatchBundle(
            manifest: manifest,
            bytecode: bytecode,
            debugMetadata: [
                "changedFiles": changed.map { $0.url.path }.joined(separator: ","),
                "sourceCount": String(sources.count),
            ]
        )
    }

    public func compatibilitySnapshot(for bundle: KiraPatchBundle) -> KiraRuntimeCompatibilitySnapshot {
        KiraRuntimeCompatibilitySnapshot(manifest: bundle.manifest)
    }

    private func buildModuleDigests(typed: TypedModule, sourceTexts: [SourceText]) -> [KiraPatchModuleDigest] {
        let sourceByPath = Dictionary(uniqueKeysWithValues: sourceTexts.map { ($0.file, $0) })
        let declarationsByPath = Dictionary(grouping: typed.ast.declarations) { decl in
            decl.range.start.file
        }

        return declarationsByPath.keys.sorted().map { path in
            let declarations = declarationsByPath[path] ?? []
            let exportedFunctions = exportedFunctionDigests(in: declarations, symbols: typed.symbols)
            let publicTypes = publicTypeDigests(in: declarations, symbols: typed.symbols)
            let bridgeVisibleSymbols = bridgeVisibleSymbols(in: declarations)
            let implementationHash = KiraDebugHashing.sha256Hex(sourceByPath[path]?.text ?? path)
            return KiraPatchModuleDigest(
                moduleName: moduleIdentifier(for: path),
                sourceFiles: [path],
                exportedFunctions: exportedFunctions,
                publicTypes: publicTypes,
                bridgeVisibleSymbols: bridgeVisibleSymbols,
                implementationHash: implementationHash
            )
        }
    }

    private func exportedFunctionDigests(in declarations: [Decl], symbols: SymbolTable) -> [KiraPatchFunctionDigest] {
        var digests: [KiraPatchFunctionDigest] = []

        for declaration in declarations {
            switch declaration {
            case .function(let fn):
                if let symbol = symbols.functions[fn.name] {
                    digests.append(.init(name: fn.name, signatureHash: functionSignatureHash(name: fn.name, type: symbol.type)))
                }
            case .externFunction(let fn):
                if let symbol = symbols.functions[fn.name] {
                    digests.append(.init(name: fn.name, signatureHash: functionSignatureHash(name: fn.name, type: symbol.type)))
                }
            case .type(let td):
                for method in td.methods {
                    if let symbol = symbols.lookupMethod(typeName: td.name, name: method.name) {
                        digests.append(.init(
                            name: symbol.loweredName,
                            signatureHash: methodSignatureHash(
                                typeName: td.name,
                                method: symbol
                            )
                        ))
                    }
                }
                for method in td.statics {
                    if let symbol = symbols.lookupStaticMethod(typeName: td.name, name: method.name) {
                        digests.append(.init(
                            name: symbol.loweredName,
                            signatureHash: methodSignatureHash(
                                typeName: td.name,
                                method: symbol
                            )
                        ))
                    }
                }
            default:
                break
            }
        }

        return digests.sorted { $0.name < $1.name }
    }

    private func publicTypeDigests(in declarations: [Decl], symbols: SymbolTable) -> [KiraPatchTypeDigest] {
        var digests: [KiraPatchTypeDigest] = []

        for declaration in declarations {
            switch declaration {
            case .type(let td):
                let fieldHashes = td.fields
                    .filter { !$0.isStatic }
                    .map { field in
                        "\(field.name):\(render(type: field.type.map(typeDescription) ?? "<inferred>"))"
                    }
                    .sorted()
                let conformanceHashes = td.conformances.sorted()
                digests.append(.init(
                    name: td.name,
                    layoutHash: KiraDebugHashing.stableHash(components: fieldHashes),
                    conformanceHash: KiraDebugHashing.stableHash(components: conformanceHashes)
                ))
            case .enum(let ed):
                let caseHashes = ed.cases.map { enumCase in
                    let payload = enumCase.associatedValues.map {
                        "\($0.label ?? "_"):\(typeDescription($0.type))"
                    }.joined(separator: ",")
                    return "\(enumCase.name)(\(payload))"
                }.sorted()
                digests.append(.init(
                    name: ed.name,
                    layoutHash: KiraDebugHashing.stableHash(components: caseHashes),
                    conformanceHash: KiraDebugHashing.stableHash(components: [])
                ))
            case .protocol(let pd):
                let requirements = pd.requirements.map { requirement in
                    let params = requirement.parameters.map {
                        "\($0.name):\(typeDescription($0.type))"
                    }.joined(separator: ",")
                    return "\(requirement.name)(\(params))->\(requirement.returnType.map(typeDescription) ?? "Void")"
                }.sorted()
                digests.append(.init(
                    name: pd.name,
                    layoutHash: KiraDebugHashing.stableHash(components: requirements),
                    conformanceHash: KiraDebugHashing.stableHash(
                        components: symbols.conformances
                            .filter { $0.value.contains(pd.name) }
                            .map(\.key)
                            .sorted()
                    )
                ))
            default:
                break
            }
        }

        return digests.sorted { $0.name < $1.name }
    }

    private func bridgeVisibleSymbols(in declarations: [Decl]) -> [String] {
        var names: [String] = []

        for declaration in declarations {
            switch declaration {
            case .function(let fn):
                if isBridgeVisibleFunction(fn.name) {
                    names.append(fn.name)
                }
            case .type(let td):
                if td.name == "Application" {
                    names.append(td.name)
                }
            default:
                break
            }
        }

        return names.sorted()
    }

    private func isBridgeVisibleFunction(_ name: String) -> Bool {
        name == "main"
            || name == "__kira_init_globals"
            || name.hasPrefix("graphics_on_")
    }

    private func functionSignatureHash(name: String, type: KiraType) -> String {
        KiraDebugHashing.stableHash(components: [name, render(type: type)])
    }

    private func methodSignatureHash(typeName: String, method: MethodSymbol) -> String {
        KiraDebugHashing.stableHash(components: [
            typeName,
            method.name,
            method.parameterLabels.map { $0 ?? "_" }.joined(separator: ","),
            render(type: method.type),
        ])
    }

    private func render(type: KiraType) -> String {
        type.description
    }

    private func render(type: String) -> String {
        type
    }

    private func typeDescription(_ ref: TypeRef) -> String {
        switch ref.kind {
        case .named(let name):
            return name
        case .applied(let base, let args):
            return "\(base)<\(args.map(typeDescription).joined(separator: ", "))>"
        case .fixedArray(let element, let count):
            return "[\(typeDescription(element)); \(count)]"
        case .array(let inner):
            return "[\(typeDescription(inner))]"
        case .dictionary(let key, let value):
            return "[\(typeDescription(key)): \(typeDescription(value))]"
        case .optional(let inner):
            return "\(typeDescription(inner))?"
        case .function(let params, let returns):
            return "(\(params.map(typeDescription).joined(separator: ", "))) -> \(typeDescription(returns))"
        }
    }

    private func moduleIdentifier(for path: String) -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var components = url.deletingPathExtension().pathComponents

        if let sourcesIndex = components.lastIndex(of: "Sources") {
            let suffix = Array(components.dropFirst(sourcesIndex + 1))
            let prefix: [String]

            if let packagesIndex = components.lastIndex(of: "KiraPackages"),
               packagesIndex + 1 < components.count {
                prefix = [components[packagesIndex + 1]]
            } else {
                prefix = [config.projectName]
            }

            return (prefix + suffix).joined(separator: "::")
        }

        if components.count >= 2 {
            components.removeFirst()
        }
        return ([config.projectName] + components).joined(separator: "::")
    }
}
