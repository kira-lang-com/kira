import Foundation

enum LSPCommand {
    static func run(args: [String]) throws {
        _ = args
        // Prefer launching the dedicated `kira-lsp` executable if present.
        let path = ".build/debug/kira-lsp"
        if FileManager.default.fileExists(atPath: path) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = []
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            try process.run()
            process.waitUntilExit()
            return
        }
        throw CLIError.message("kira-lsp executable not found. Build it with: swift build --product kira-lsp")
    }
}
