import Foundation
import KiraCompiler

enum DocCommand {
    static func run(args: [String]) throws {
        var a = Args(args)
        var all = false
        var onlyDocumented = false
        var out: String?
        var force = false
        var clean = false

        while let tok = a.next() {
            switch tok {
            case "--all":
                all = true
            case "--only-documented":
                onlyDocumented = true
            case "--out":
                out = a.next()
            case "--force":
                force = true
            case "--clean":
                clean = true
            case "--help", "-h":
                print("kira doc [--all|--only-documented] --out <dir> [--force] [--clean]")
                return
            default:
                throw CLIError.invalidOption(tok)
            }
        }
        guard let out else { throw CLIError.missingArgument("--out <dir>") }

        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let sourcesDir = cwd.appendingPathComponent("Sources", isDirectory: true)
        let sourceFiles = try fm.contentsOfDirectory(at: sourcesDir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "kira" }
        guard let entry = sourceFiles.first else { throw CLIError.message("No .kira sources found in Sources/") }

        let text = try String(contentsOf: entry, encoding: .utf8)
        let output = try CompilerDriver().compile(source: SourceText(file: entry.path, text: text), target: .macOS(arch: .arm64))

        let symbols = DocExtractor().extract(from: output.typed, moduleName: "App")
        let filtered: [DocSymbol]
        if onlyDocumented {
            filtered = symbols.filter { ($0.doc?.isEmpty == false) || $0.properties.contains(where: { ($0.doc?.isEmpty == false) }) }
        } else if all {
            filtered = symbols
        } else {
            filtered = symbols.filter { ($0.doc?.isEmpty == false) }
        }

        let outURL = URL(fileURLWithPath: out, isDirectory: true)
        var expected: Set<String> = []
        for s in filtered {
            let subdir: String
            switch s.kind {
            case .widget: subdir = "widgets"
            case .construct: subdir = "constructs"
            default: subdir = "types"
            }
            let fileRel = "\(subdir)/\(s.name).md"
            expected.insert(fileRel)
            let fileURL = outURL.appendingPathComponent(fileRel)
            let rendered = DocRenderer().render(symbol: s)
            try DocRenderer().writeFenceSafe(rendered: rendered, to: fileURL, force: force)
        }

        if clean {
            try DocOrphanCleaner().clean(orphanableRoot: outURL, expectedFiles: expected)
        }
    }
}
