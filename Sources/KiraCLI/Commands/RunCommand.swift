import Foundation
import KiraCompiler
import KiraVM

enum RunCommand {
    static func run(args: [String]) throws {
        _ = args
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let sourcesDir = cwd.appendingPathComponent("Sources", isDirectory: true)
        let sourceFiles = try fm.contentsOfDirectory(at: sourcesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "kira" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let entry = sourceFiles.first(where: { $0.lastPathComponent == "main.kira" }) ?? sourceFiles.first else {
            throw CLIError.message("No .kira sources found in Sources/")
        }

        let text = try String(contentsOf: entry, encoding: .utf8)
        let driver = CompilerDriver()
        let output = try driver.compile(source: SourceText(file: entry.path, text: text), target: defaultTargetForHost())
        guard let bc = output.bytecode else { throw CLIError.message("No bytecode emitted.") }

        let module = try BytecodeLoader().load(data: bc)
        let vm = VirtualMachine(module: module)
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
}
