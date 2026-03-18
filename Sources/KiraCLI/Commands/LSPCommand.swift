import Foundation

enum LSPCommand {
    static func run(args: [String]) throws {
        _ = args
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        let sibling = KiraCLIInfo.currentExecutableURL(fileManager: fm)
            .deletingLastPathComponent()
            .appendingPathComponent(KiraCLIInfo.lspExecutableName)

        let candidates = [sibling] + findBuildExecutables(named: KiraCLIInfo.lspExecutableName, from: cwd)
        for candidate in candidates {
            guard fm.fileExists(atPath: candidate.path) else { continue }
            let process = Process()
            process.executableURL = candidate
            process.arguments = []
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            try process.run()
            process.waitUntilExit()
            return
        }
        throw CLIError.message("kira-lsp executable not found. Build it with: swift build --product kira-lsp or install the toolchain with: kira install")
    }

    private static func findBuildExecutables(named name: String, from cwd: URL) -> [URL] {
        let buildDir = cwd.appendingPathComponent(".build", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: buildDir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }

        var matches: [URL] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent == name {
                matches.append(url)
            }
        }
        return matches.sorted { lhs, rhs in
            func score(_ url: URL) -> Int {
                let path = url.path.lowercased()
                if path.contains("\\release\\") || path.contains("/release/") { return 2 }
                if path.contains("\\debug\\") || path.contains("/debug/") { return 1 }
                return 0
            }
            return score(lhs) > score(rhs)
        }
    }
}
