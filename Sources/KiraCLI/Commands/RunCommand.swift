import Foundation
import KiraCompiler
import KiraVM

enum RunCommand {
    static func run(args: [String]) throws {
        let fm = FileManager.default
        let sourceFiles: [URL]

        if let input = args.first {
            let inputURL = URL(fileURLWithPath: input, relativeTo: URL(fileURLWithPath: fm.currentDirectoryPath))
                .standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
                throw CLIError.message("Input path not found: \(inputURL.path)")
            }

            if isDirectory.boolValue {
                let sourcesDir = inputURL.appendingPathComponent("Sources", isDirectory: true)
                sourceFiles = try collectKiraSources(in: sourcesDir)
            } else if inputURL.pathExtension == "kira" {
                sourceFiles = [inputURL]
            } else {
                throw CLIError.message("Expected a .kira file or a project directory: \(inputURL.path)")
            }
        } else {
            let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
            let sourcesDir = cwd.appendingPathComponent("Sources", isDirectory: true)
            sourceFiles = try collectKiraSources(in: sourcesDir)
        }

        guard !sourceFiles.isEmpty else {
            throw CLIError.message("No .kira sources found.")
        }

        let sources: [SourceText] = try sourceFiles.map { url in
            let text = try String(contentsOf: url, encoding: .utf8)
            return SourceText(file: url.path, text: text)
        }
        let driver = CompilerDriver()
        let output = try driver.compile(sources: sources, target: defaultTargetForHost())
        guard let bc = output.bytecode else { throw CLIError.message("No bytecode emitted.") }

        let module = try BytecodeLoader().load(data: bc)
        let vm = VirtualMachine(module: module)
        if module.functions.contains(where: { $0.name == "__kira_init_globals" }) {
            _ = try vm.run(function: "__kira_init_globals")
        }
        _ = try vm.run(function: "main")
    }

    private static func defaultTargetForHost() -> PlatformTarget {
        #if os(macOS)
        return .macOS(arch: .arm64)
        #elseif os(Linux)
        return .linux(arch: .x86_64)
        #elseif os(Windows)
        return .windows(arch: .x86_64)
        #else
        return .macOS(arch: .arm64)
        #endif
    }

    private static func collectKiraSources(in dir: URL) throws -> [URL] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var out: [URL] = []
        for case let u as URL in e {
            if u.pathExtension == "kira" {
                out.append(u)
            }
        }
        out.sort { $0.path < $1.path }
        return out
    }
}
