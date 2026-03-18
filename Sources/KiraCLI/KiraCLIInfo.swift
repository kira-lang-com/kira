import Foundation

enum KiraCLIInfo {
    static let version = "1.0.0"
    static let stdlibBundleName = "Kira_KiraStdlib.resources"

    static var executableSuffix: String {
        #if os(Windows)
        return ".exe"
        #else
        return ""
        #endif
    }

    static var executableName: String { "kira\(executableSuffix)" }
    static var lspExecutableName: String { "kira-lsp\(executableSuffix)" }

    static func currentExecutableURL(fileManager: FileManager = .default) -> URL {
        let raw = CommandLine.arguments.first ?? executableName
        let baseURL: URL
        if raw.hasPrefix("/") || raw.hasPrefix("\\") || raw.contains(":") {
            baseURL = URL(fileURLWithPath: raw).standardizedFileURL
        } else {
            baseURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent(raw)
                .standardizedFileURL
        }

        #if os(Windows)
        if fileManager.fileExists(atPath: baseURL.path) {
            return baseURL
        }

        if baseURL.pathExtension.isEmpty {
            let exeURL = baseURL.appendingPathExtension("exe")
            if fileManager.fileExists(atPath: exeURL.path) {
                return exeURL
            }
        }
        #endif

        return baseURL
    }

    static func toolchainRoot(fileManager: FileManager = .default) -> URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env["KIRA_TOOLCHAIN_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let kiraHome = env["KIRA_HOME"], !kiraHome.isEmpty {
            return URL(fileURLWithPath: kiraHome, isDirectory: true)
                .appendingPathComponent("toolchain", isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".kira", isDirectory: true)
            .appendingPathComponent("toolchain", isDirectory: true)
    }
}
