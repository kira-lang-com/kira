import Foundation
import KiraCompiler

enum DocCommand {
    static func run(args: [String]) throws {
        var a = Args(args)
        var all = false
        var package: String?
        var onlyDocumented = false
        var out: String?
        var force = false
        var clean = false

        while let tok = a.next() {
            switch tok {
            case "--all":
                all = true
            case "--package":
                package = a.next()
            case "--only-documented":
                onlyDocumented = true
            case "--out":
                out = a.next()
            case "--force":
                force = true
            case "--clean":
                clean = true
            case "--help", "-h":
                print("kira doc [--package <name>|--all|--only-documented] --out <dir> [--force] [--clean]")
                return
            default:
                throw CLIError.invalidOption(tok)
            }
        }
        guard let out else { throw CLIError.missingArgument("--out <dir>") }

        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let outURL = URL(fileURLWithPath: out, isDirectory: true)
        let jobs = try documentationJobs(cwd: cwd, package: package, all: all)
        for job in jobs {
            let destination = jobs.count == 1 ? outURL : outURL.appendingPathComponent(job.moduleName, isDirectory: true)
            try renderDocs(
                moduleName: job.moduleName,
                sourcesDir: job.sourcesDir,
                outURL: destination,
                onlyDocumented: onlyDocumented,
                includeAll: all,
                force: force,
                clean: clean
            )
        }
    }

    private struct DocJob {
        var moduleName: String
        var sourcesDir: URL
    }

    private static func documentationJobs(cwd: URL, package: String?, all: Bool) throws -> [DocJob] {
        let fm = FileManager.default
        if let package {
            let dir = cwd
                .appendingPathComponent("KiraPackages", isDirectory: true)
                .appendingPathComponent(package, isDirectory: true)
                .appendingPathComponent("Sources", isDirectory: true)
            guard fm.fileExists(atPath: dir.path) else {
                throw CLIError.message("Package '\(package)' was not found in KiraPackages/")
            }
            return [.init(moduleName: package, sourcesDir: dir)]
        }

        if all {
            var jobs: [DocJob] = []
            let projectSources = cwd.appendingPathComponent("Sources", isDirectory: true)
            if fm.fileExists(atPath: projectSources.path) {
                let moduleName = (try? KiraPackage.load(from: cwd.appendingPathComponent("Kira.toml")).package.name) ?? "App"
                jobs.append(.init(moduleName: moduleName, sourcesDir: projectSources))
            }
            let packagesDir = cwd.appendingPathComponent("KiraPackages", isDirectory: true)
            if let packageDirs = try? fm.contentsOfDirectory(at: packagesDir, includingPropertiesForKeys: nil) {
                for dir in packageDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let sourcesDir = dir.appendingPathComponent("Sources", isDirectory: true)
                    if fm.fileExists(atPath: sourcesDir.path) {
                        jobs.append(.init(moduleName: dir.lastPathComponent, sourcesDir: sourcesDir))
                    }
                }
            }
            return jobs
        }

        let sourcesDir = cwd.appendingPathComponent("Sources", isDirectory: true)
        guard fm.fileExists(atPath: sourcesDir.path) else {
            throw CLIError.message("No .kira sources found in Sources/")
        }
        let moduleName = (try? KiraPackage.load(from: cwd.appendingPathComponent("Kira.toml")).package.name) ?? "App"
        return [.init(moduleName: moduleName, sourcesDir: sourcesDir)]
    }

    private static func renderDocs(
        moduleName: String,
        sourcesDir: URL,
        outURL: URL,
        onlyDocumented: Bool,
        includeAll: Bool,
        force: Bool,
        clean: Bool
    ) throws {
        let sourceFiles = try collectKiraSources(in: sourcesDir)
        guard !sourceFiles.isEmpty else { return }
        let sources = try sourceFiles.map { url in
            SourceText(file: url.path, text: try String(contentsOf: url, encoding: .utf8))
        }
        let output = try CompilerDriver().compile(sources: sources, target: .macOS(arch: .arm64))
        let symbols = DocExtractor().extract(
            from: output.typed,
            moduleName: moduleName,
            sourceRoot: sourcesDir.path
        )
        let filtered: [DocSymbol]
        if onlyDocumented {
            filtered = symbols.filter {
                hasDocs($0.doc) || $0.properties.contains(where: { hasDocs($0.doc) })
                    || $0.methods.contains(where: { hasDocs($0.doc) })
                    || $0.variants.contains(where: { hasDocs($0.doc) })
                    || $0.requirements.contains(where: { hasDocs($0.doc) })
            }
        } else if includeAll {
            filtered = symbols
        } else {
            filtered = symbols.filter { hasDocs($0.doc) }
        }

        var expected: Set<String> = []
        for symbol in filtered {
            let subdir: String
            switch symbol.kind {
            case .widget: subdir = "widgets"
            case .construct: subdir = "constructs"
            default: subdir = "types"
            }
            let fileRel = "\(subdir)/\(symbol.name).md"
            expected.insert(fileRel)
            let fileURL = outURL.appendingPathComponent(fileRel)
            let rendered = DocRenderer().render(symbol: symbol)
            try DocRenderer().writeFenceSafe(rendered: rendered, to: fileURL, force: force)
        }

        if clean {
            try DocOrphanCleaner().clean(orphanableRoot: outURL, expectedFiles: expected)
        }
    }

    private static func collectKiraSources(in dir: URL) throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        var out: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "kira" {
            out.append(url)
        }
        return out.sorted(by: { $0.path < $1.path })
    }

    private static func hasDocs(_ doc: String?) -> Bool {
        guard let doc else { return false }
        return !doc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
