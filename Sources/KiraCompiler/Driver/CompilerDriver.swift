import Foundation
import KiraStdlib

public enum CompilerDriverError: Error, CustomStringConvertible, Sendable {
    case circularImport([String])

    public var description: String {
        switch self {
        case .circularImport(let chain):
            return "error: circular import detected: \(chain.joined(separator: " -> "))"
        }
    }
}

public struct CompilerOutput: Sendable {
    public var typed: TypedModule
    public var ir: KiraIRModule
    public var bytecode: Data?
    public var wasm: Data?

    public init(typed: TypedModule, ir: KiraIRModule, bytecode: Data?, wasm: Data?) {
        self.typed = typed
        self.ir = ir
        self.bytecode = bytecode
        self.wasm = wasm
    }
}

public struct CompilerDriver: Sendable {
    public init() {}

    public func compile(source: SourceText, target: PlatformTarget) throws -> CompilerOutput {
        return try compile(sources: [source], target: target)
    }

    public func compile(sources: [SourceText], target: PlatformTarget) throws -> CompilerOutput {
        let lexer = Lexer()
        var primaryImports: [ImportDecl] = []
        var primaryDecls: [Decl] = []
        var primaryRange: SourceRange?
        for s in sources {
            let toks = try lexer.lex(s)
            var p = Parser(tokens: toks)
            let m = try p.parseModule()
            if primaryRange == nil { primaryRange = m.range }
            primaryImports.append(contentsOf: m.imports)
            primaryDecls.append(contentsOf: m.declarations)
        }

        var importedDecls: [Decl] = []
        var importedImports: [ImportDecl] = []
        let importRoots = importSearchRoots(for: sources)
        let packageRegistry = packageRegistry(for: sources, searchRoots: importRoots)
        let importedSources = try loadImportedSources(for: primaryImports, searchRoots: importRoots, packageRegistry: packageRegistry)
        for s in importedSources {
            let toks = try lexer.lex(s)
            var p = Parser(tokens: toks)
            let m = try p.parseModule()
            importedImports.append(contentsOf: m.imports)
            importedDecls.append(contentsOf: m.declarations)
        }

        let module = ModuleAST(
            imports: primaryImports + importedImports,
            declarations: importedDecls + primaryDecls,
            range: primaryRange ?? SourceRange(
                start: SourceLocation(file: "", offset: 0, line: 0, column: 0),
                end: SourceLocation(file: "", offset: 0, line: 0, column: 0)
            )
        )

        // Build construct registry.
        var registry = ConstructRegistry()
        for decl in module.declarations {
            if case .construct(let c) = decl { registry.register(c) }
        }

        // Construct validation pass.
        let validator = AnnotationValidator()
        try validator.validate(module: module, registry: registry)

        // Type checking.
        let tc = TypeChecker()
        let typed = try tc.typeCheck(module: module, registry: registry, target: target)

        // IR build.
        let ir = try IRBuilder().build(from: typed)

        // Codegen selection:
        // - wasm32: emit minimal wasm module, and still emit bytecode for @Runtime-free programs for tooling.
        // - others: emit bytecode (debug/hybrid) as primary scaffold artifact.
        let bytecode = try BytecodeEmitter().emit(module: ir)
        let wasm = target.isWasm ? WasmCodegen().emitMinimalModule() : nil

        return CompilerOutput(typed: typed, ir: ir, bytecode: bytecode, wasm: wasm)
    }

    private func loadImportedSources(for imports: [ImportDecl], searchRoots: [URL], packageRegistry: [String: URL]) throws -> [SourceText] {
        var loadedModules: Set<String> = []
        var loadedFiles: Set<String> = []
        var result: [SourceText] = []
        let lexer = Lexer()

        func visit(_ modulePath: String, stack: [String]) throws {
            if stack.contains(modulePath) {
                throw CompilerDriverError.circularImport(stack + [modulePath])
            }
            if !loadedModules.insert(modulePath).inserted {
                return
            }

            let moduleSources = try resolveImportSources(for: modulePath, searchRoots: searchRoots, packageRegistry: packageRegistry)
            for source in moduleSources {
                if !loadedFiles.insert(source.file).inserted {
                    continue
                }
                result.append(source)

                let toks = try lexer.lex(source)
                var parser = Parser(tokens: toks)
                let module = try parser.parseModule()
                for importDecl in module.imports {
                    try visit(importDecl.modulePath, stack: stack + [modulePath])
                }
            }
        }

        for importDecl in imports {
            try visit(importDecl.modulePath, stack: [])
        }

        return result
    }

    private func resolveImportSources(for modulePath: String, searchRoots: [URL], packageRegistry: [String: URL]) throws -> [SourceText] {
        if let packageSources = try loadPackageSources(for: modulePath, searchRoots: searchRoots, packageRegistry: packageRegistry) {
            return packageSources
        }
        if let stdlibSources = try loadStdlibSources(for: modulePath) {
            return stdlibSources
        }
        return []
    }

    private func loadStdlibSources(for modulePath: String) throws -> [SourceText]? {
        let moduleDirs: Set<String>
        switch modulePath {
        case "Kira.Fondation", "Kira.Foundation":
            moduleDirs = ["Fondation"]
        default:
            return nil
        }

        var selected: [URL] = []
        if moduleDirs.contains("Fondation") {
            if let url = KiraStdlib.resourceURL("Fondation/Color.kira") ?? KiraStdlib.resourceURL("Color.kira") {
                selected.append(url)
            }
        }

        let urls = KiraStdlib.listKiraFiles()
        for url in urls {
            if selected.contains(where: { $0.path == url.path }) { continue }
            let comps = url.pathComponents
            if moduleDirs.contains(where: { comps.contains($0) }) {
                selected.append(url)
                continue
            }
            if moduleDirs.contains("Fondation"), url.lastPathComponent == "Color.kira" {
                selected.append(url)
            }
        }

        return try sourceTexts(from: selected)
    }

    private func loadPackageSources(for modulePath: String, searchRoots: [URL], packageRegistry: [String: URL]) throws -> [SourceText]? {
        let fm = FileManager.default
        if let sourcesDir = packageRegistry[modulePath], fm.fileExists(atPath: sourcesDir.path) {
            let urls = try collectKiraSources(in: sourcesDir)
            return try sourceTexts(from: urls)
        }
        for root in searchRoots {
            let sourcesDir = root
                .appendingPathComponent("KiraPackages", isDirectory: true)
                .appendingPathComponent(modulePath, isDirectory: true)
                .appendingPathComponent("Sources", isDirectory: true)
            guard fm.fileExists(atPath: sourcesDir.path) else { continue }
            let urls = try collectKiraSources(in: sourcesDir)
            return try sourceTexts(from: urls)
        }
        return nil
    }

    private func packageRegistry(for sources: [SourceText], searchRoots: [URL]) -> [String: URL] {
        let fm = FileManager.default
        var registry: [String: URL] = [:]

        func registerPackages(in root: URL) {
            let packagesDir = root.appendingPathComponent("KiraPackages", isDirectory: true)
            guard let packageDirs = try? fm.contentsOfDirectory(at: packagesDir, includingPropertiesForKeys: nil) else {
                return
            }
            for dir in packageDirs {
                let sourcesDir = dir.appendingPathComponent("Sources", isDirectory: true)
                if fm.fileExists(atPath: sourcesDir.path), registry[dir.lastPathComponent] == nil {
                    registry[dir.lastPathComponent] = sourcesDir
                }
            }
        }

        func registerDependencies(from projectRoot: URL) {
            let manifestURL = projectRoot.appendingPathComponent("Kira.toml")
            guard fm.fileExists(atPath: manifestURL.path),
                  let dependencyNames = try? dependencyNames(from: manifestURL) else {
                return
            }
            for dependencyName in dependencyNames {
                let sourcesDir = projectRoot
                    .appendingPathComponent("KiraPackages", isDirectory: true)
                    .appendingPathComponent(dependencyName, isDirectory: true)
                    .appendingPathComponent("Sources", isDirectory: true)
                if fm.fileExists(atPath: sourcesDir.path), registry[dependencyName] == nil {
                    registry[dependencyName] = sourcesDir
                }
            }
        }

        for root in searchRoots {
            registerPackages(in: root)
            registerDependencies(from: root)
        }
        for source in sources {
            let sourceURL = URL(fileURLWithPath: source.file)
            var candidate = sourceURL.deletingLastPathComponent()
            while candidate.path != "/" && !candidate.path.isEmpty {
                registerPackages(in: candidate)
                registerDependencies(from: candidate)
                let parent = candidate.deletingLastPathComponent()
                if parent.path == candidate.path { break }
                candidate = parent
            }
        }

        return registry
    }

    private func dependencyNames(from manifestURL: URL) throws -> [String] {
        let text = try String(contentsOf: manifestURL, encoding: .utf8)
        var section = ""
        var names: [String] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            if let hash = line.firstIndex(of: "#") {
                line = String(line[..<hash])
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                section = String(trimmed.dropFirst().dropLast())
                continue
            }

            guard section == "dependencies" else {
                continue
            }

            let parts = trimmed.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let rawName = parts.first, !rawName.isEmpty else {
                continue
            }

            let dependencyName = rawName.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !dependencyName.isEmpty {
                names.append(dependencyName)
            }
        }

        return names
    }

    private func importSearchRoots(for sources: [SourceText]) -> [URL] {
        var roots: [URL] = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)]
        var seen: Set<String> = [roots[0].standardizedFileURL.path]

        for source in sources {
            let sourceURL = URL(fileURLWithPath: source.file)
            var candidate = sourceURL.deletingLastPathComponent()
            while true {
                let standardized = candidate.standardizedFileURL.path
                if seen.insert(standardized).inserted {
                    roots.append(candidate)
                }
                if candidate.lastPathComponent == "Sources" {
                    let parent = candidate.deletingLastPathComponent()
                    let parentPath = parent.standardizedFileURL.path
                    if seen.insert(parentPath).inserted {
                        roots.append(parent)
                    }
                }
                let parent = candidate.deletingLastPathComponent()
                if parent.path == candidate.path || parent.path.isEmpty {
                    break
                }
                candidate = parent
            }
        }

        return roots
    }

    private func collectKiraSources(in dir: URL) throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        var out: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "kira" {
            out.append(url)
        }
        out.sort { $0.path < $1.path }
        return out
    }

    private func sourceTexts(from urls: [URL]) throws -> [SourceText] {
        var result: [SourceText] = []
        result.reserveCapacity(urls.count)
        for url in urls.sorted(by: { $0.path < $1.path }) {
            let text = try String(contentsOf: url, encoding: .utf8)
            result.append(SourceText(file: url.path, text: text))
        }
        return result
    }
}
