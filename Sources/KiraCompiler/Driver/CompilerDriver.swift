import Foundation
import KiraStdlib

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
        let importedSources = try loadImportedSources(for: primaryImports, searchRoots: importRoots)
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

    private func loadImportedSources(for imports: [ImportDecl], searchRoots: [URL]) throws -> [SourceText] {
        var pending = imports
        var loadedModules: Set<String> = []
        var loadedFiles: Set<String> = []
        var result: [SourceText] = []
        let lexer = Lexer()

        while !pending.isEmpty {
            let current = pending.removeFirst()
            if !loadedModules.insert(current.modulePath).inserted {
                continue
            }

            let moduleSources = try resolveImportSources(for: current.modulePath, searchRoots: searchRoots)
            for source in moduleSources {
                if !loadedFiles.insert(source.file).inserted {
                    continue
                }
                result.append(source)

                let toks = try lexer.lex(source)
                var parser = Parser(tokens: toks)
                let module = try parser.parseModule()
                pending.append(contentsOf: module.imports)
            }
        }

        return result
    }

    private func resolveImportSources(for modulePath: String, searchRoots: [URL]) throws -> [SourceText] {
        if let stdlibSources = try loadStdlibSources(for: modulePath) {
            return stdlibSources
        }
        if let packageSources = try loadPackageSources(for: modulePath, searchRoots: searchRoots) {
            return packageSources
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

    private func loadPackageSources(for modulePath: String, searchRoots: [URL]) throws -> [SourceText]? {
        let fm = FileManager.default
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
