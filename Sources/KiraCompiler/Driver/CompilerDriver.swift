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
        let lexer = Lexer()
        let primaryTokens = try lexer.lex(source)
        var primaryParser = Parser(tokens: primaryTokens)
        let primaryModule = try primaryParser.parseModule()

        let stdlibSources = try loadStdlibSources(for: primaryModule.imports)
        var importedDecls: [Decl] = []
        var importedImports: [ImportDecl] = []
        for s in stdlibSources {
            let toks = try lexer.lex(s)
            var p = Parser(tokens: toks)
            let m = try p.parseModule()
            importedImports.append(contentsOf: m.imports)
            importedDecls.append(contentsOf: m.declarations)
        }

        let module = ModuleAST(
            imports: primaryModule.imports + importedImports,
            declarations: importedDecls + primaryModule.declarations,
            range: primaryModule.range
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

    private func loadStdlibSources(for imports: [ImportDecl]) throws -> [SourceText] {
        var moduleDirs: Set<String> = []
        for i in imports {
            switch i.modulePath {
            case "Kira.Fondation", "Kira.Foundation":
                moduleDirs.insert("Fondation")
            default:
                break
            }
        }
        if moduleDirs.isEmpty { return [] }

        var selected: [URL] = []

        // Prefer explicit resource paths (works even if the bundle flattens resources).
        if moduleDirs.contains("Fondation") {
            if let u = KiraStdlib.resourceURL("Fondation/Color.kira") ?? KiraStdlib.resourceURL("Color.kira") {
                selected.append(u)
            }
        }

        // Fallback to enumerating resources.
        let urls = KiraStdlib.listKiraFiles()
        for u in urls {
            if selected.contains(where: { $0.path == u.path }) { continue }
            let comps = u.pathComponents
            if moduleDirs.contains(where: { comps.contains($0) }) {
                selected.append(u)
                continue
            }
            // If directory structure wasn't preserved, match by filename.
            if moduleDirs.contains("Fondation"), u.lastPathComponent == "Color.kira" {
                selected.append(u)
            }
        }
        selected.sort { $0.path < $1.path }

        var result: [SourceText] = []
        result.reserveCapacity(selected.count)
        for url in selected {
            let text = try String(contentsOf: url, encoding: .utf8)
            result.append(SourceText(file: url.path, text: text))
        }
        return result
    }
}
