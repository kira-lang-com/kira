import Foundation

enum InstallCommand {
    static func run(args: [String]) throws {
        var a = Args(args)
        var dev = false

        while let tok = a.next() {
            switch tok {
            case "--dev":
                dev = true
            case "--help", "-h":
                print(helpText())
                return
            default:
                throw CLIError.invalidOption(tok)
            }
        }

        let fm = FileManager.default
        let workspaceRoot = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        let manifestURL = workspaceRoot.appendingPathComponent("Package.swift")
        guard fm.fileExists(atPath: manifestURL.path) else {
            throw CLIError.message("install must be run from the Kira repository root (missing Package.swift)")
        }

        let artifacts = try resolveArtifacts(dev: dev, workspaceRoot: workspaceRoot)
        let toolchainRoot = KiraCLIInfo.toolchainRoot(fileManager: fm)
        let versionDir = toolchainRoot.appendingPathComponent(KiraCLIInfo.version, isDirectory: true)
        let binDir = versionDir.appendingPathComponent("bin", isDirectory: true)
        let currentLink = toolchainRoot.appendingPathComponent("current", isDirectory: true)

        try fm.createDirectory(at: toolchainRoot, withIntermediateDirectories: true)
        try replaceDirectory(at: versionDir, fileManager: fm)
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)

        try installItem(from: artifacts.kiraExecutable, to: binDir.appendingPathComponent(artifacts.kiraExecutable.lastPathComponent), fileManager: fm)
        try installItem(from: artifacts.lspExecutable, to: binDir.appendingPathComponent(artifacts.lspExecutable.lastPathComponent), fileManager: fm)
        try installItem(from: artifacts.stdlibBundle, to: binDir.appendingPathComponent(artifacts.stdlibBundle.lastPathComponent, isDirectory: true), fileManager: fm)
        if let libffiDLL = artifacts.libffiDLL {
            try installItem(from: libffiDLL, to: binDir.appendingPathComponent(libffiDLL.lastPathComponent), fileManager: fm)
        }

        let installKind = dev ? "dev" : "release"
        let metadata = """
        version = "\(KiraCLIInfo.version)"
        channel = "\(installKind)"
        installed_at = "\(ISO8601DateFormatter().string(from: Date()))"
        """
        try metadata.write(to: versionDir.appendingPathComponent("toolchain.toml"), atomically: true, encoding: .utf8)

        try updateCurrentLink(at: currentLink, destination: versionDir, fileManager: fm)
        let pathHint = currentLink.appendingPathComponent("bin").path

        print("Installed Kira \(KiraCLIInfo.version) (\(installKind)) to \(versionDir.path)")
        print("Current toolchain link: \(currentLink.path)")
        print("Add \(pathHint) to your PATH to use kira globally.")
    }

    private struct InstallArtifacts {
        let kiraExecutable: URL
        let lspExecutable: URL
        let stdlibBundle: URL
        let libffiDLL: URL?
    }

    private static func helpText() -> String {
        """
        kira install [--dev]

        Installs the Kira toolchain into ~/.kira/toolchain/\(KiraCLIInfo.version).

        Options:
          --dev    install the current local debug toolchain
        """
    }

    private static func resolveArtifacts(dev: Bool, workspaceRoot: URL) throws -> InstallArtifacts {
        let windowsLibffi = windowsBundledLibffi(workspaceRoot: workspaceRoot)
        let buildEnv = windowsLibffi.buildEnvironmentOverrides
        let libffiDLL = windowsLibffi.dll
        let buildPath = buildEnv.isEmpty ? nil : makeBuildPath()

        if dev {
            return try resolveDevArtifacts(
                workspaceRoot: workspaceRoot,
                buildEnvironment: buildEnv,
                libffiDLL: libffiDLL,
                buildPath: buildPath
            )
        }

        try runSwift(arguments: ["build", "-c", "release"], workspaceRoot: workspaceRoot, environment: buildEnv, buildPath: buildPath)
        let binDir = try showBinPath(configuration: "release", workspaceRoot: workspaceRoot, environment: buildEnv, buildPath: buildPath)
        return try artifacts(in: binDir, libffiDLL: libffiDLL)
    }

    private static func resolveDevArtifacts(
        workspaceRoot: URL,
        buildEnvironment: [String: String],
        libffiDLL: URL?,
        buildPath: URL?
    ) throws -> InstallArtifacts {
        let fm = FileManager.default
        let shouldRebuild = !buildEnvironment.isEmpty

        if !shouldRebuild {
            let currentExecutable = KiraCLIInfo.currentExecutableURL(fileManager: fm)
            let buildRoot = workspaceRoot.appendingPathComponent(".build", isDirectory: true).standardizedFileURL.path
            let currentBinDir = currentExecutable.deletingLastPathComponent()

            if currentExecutable.standardizedFileURL.path.hasPrefix(buildRoot) {
                let lspURL = currentBinDir.appendingPathComponent(KiraCLIInfo.lspExecutableName)
                let bundleURL = currentBinDir.appendingPathComponent(KiraCLIInfo.stdlibBundleName, isDirectory: true)
                if !fm.fileExists(atPath: lspURL.path) || !fm.fileExists(atPath: bundleURL.path) {
                    try runSwift(arguments: ["build", "-c", "debug", "--product", "kira-lsp"], workspaceRoot: workspaceRoot, environment: buildEnvironment, buildPath: nil)
                }
                return try artifacts(in: currentBinDir, kiraExecutable: currentExecutable, libffiDLL: libffiDLL)
            }
        }

        try runSwift(arguments: ["build", "-c", "debug"], workspaceRoot: workspaceRoot, environment: buildEnvironment, buildPath: buildPath)
        let binDir = try showBinPath(configuration: "debug", workspaceRoot: workspaceRoot, environment: buildEnvironment, buildPath: buildPath)
        return try artifacts(in: binDir, libffiDLL: libffiDLL)
    }

    private static func artifacts(in binDir: URL, kiraExecutable: URL? = nil, libffiDLL: URL? = nil) throws -> InstallArtifacts {
        let fm = FileManager.default
        let kiraURL = kiraExecutable ?? binDir.appendingPathComponent(KiraCLIInfo.executableName)
        let lspURL = binDir.appendingPathComponent(KiraCLIInfo.lspExecutableName)
        let bundleURL = binDir.appendingPathComponent(KiraCLIInfo.stdlibBundleName, isDirectory: true)

        guard fm.fileExists(atPath: kiraURL.path) else {
            throw CLIError.fileNotFound(kiraURL.path)
        }
        guard fm.fileExists(atPath: lspURL.path) else {
            throw CLIError.fileNotFound(lspURL.path)
        }
        guard fm.fileExists(atPath: bundleURL.path) else {
            throw CLIError.fileNotFound(bundleURL.path)
        }

        return InstallArtifacts(kiraExecutable: kiraURL, lspExecutable: lspURL, stdlibBundle: bundleURL, libffiDLL: libffiDLL)
    }

    private static func replaceDirectory(at url: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func installItem(from source: URL, to destination: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private static func updateCurrentLink(at currentLink: URL, destination: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: currentLink.path) {
            try fileManager.removeItem(at: currentLink)
        }
        do {
            try fileManager.createSymbolicLink(at: currentLink, withDestinationURL: destination)
        } catch {
            #if os(Windows)
            throw CLIError.message("failed to create \(currentLink.path) symlink. Enable Developer Mode or run with symlink permissions. Underlying error: \(error)")
            #else
            throw error
            #endif
        }
    }

    private static func runSwift(arguments: [String], workspaceRoot: URL, environment: [String: String], buildPath: URL?) throws {
        let args = withBuildPath(arguments: arguments, buildPath: buildPath)
        let process = try makeSwiftProcess(arguments: args, workspaceRoot: workspaceRoot, environment: environment)
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let commandLine = args.joined(separator: " ")
            throw CLIError.message("swift \(commandLine) failed with exit code \(process.terminationStatus)")
        }
    }

    private static func showBinPath(configuration: String, workspaceRoot: URL, environment: [String: String], buildPath: URL?) throws -> URL {
        let args = withBuildPath(
            arguments: ["build", "-c", configuration, "--show-bin-path"],
            buildPath: buildPath
        )
        let process = try makeSwiftProcess(arguments: args, workspaceRoot: workspaceRoot, environment: environment)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CLIError.message("swift build -c \(configuration) --show-bin-path failed with exit code \(process.terminationStatus)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw CLIError.message("swift build --show-bin-path returned an empty path")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func resolveSwiftExecutable() throws -> String {
        let env = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let separator: Character = {
            #if os(Windows)
            return ";"
            #else
            return ":"
            #endif
        }()
        let suffixes: [String] = {
            #if os(Windows)
            return [".exe", ".bat", ".cmd", ""]
            #else
            return [""]
            #endif
        }()

        for rawDir in env.split(separator: separator) {
            let dir = String(rawDir)
            guard !dir.isEmpty else { continue }
            for suffix in suffixes {
                let candidate = URL(fileURLWithPath: dir, isDirectory: true)
                    .appendingPathComponent("swift\(suffix)")
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate.path
                }
            }
        }

        return "swift"
    }

    private static func makeSwiftProcess(
        arguments: [String],
        workspaceRoot: URL,
        environment: [String: String]
    ) throws -> Process {
        let process = Process()
        process.currentDirectoryURL = workspaceRoot

        #if os(Windows)
        let comspec = ProcessInfo.processInfo.environment["ComSpec"] ?? "cmd.exe"
        process.executableURL = URL(fileURLWithPath: comspec)
        process.arguments = ["/C", "swift"] + arguments
        #else
        process.executableURL = try URL(fileURLWithPath: resolveSwiftExecutable())
        process.arguments = arguments
        #endif

        if !environment.isEmpty {
            var env = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                env[key] = value
            }
            process.environment = env
        }

        return process
    }

    private static func withBuildPath(arguments: [String], buildPath: URL?) -> [String] {
        guard let buildPath else { return arguments }
        return arguments + ["--build-path", buildPath.path]
    }

    private static func makeBuildPath() -> URL {
        let base = FileManager.default.temporaryDirectory
        return base.appendingPathComponent("kira-toolchain-build-\(UUID().uuidString)", isDirectory: true)
    }

    private struct WindowsLibffiBundle {
        let dll: URL?
        let buildEnvironmentOverrides: [String: String]
    }

    private static func windowsBundledLibffi(workspaceRoot: URL) -> WindowsLibffiBundle {
        #if os(Windows)
        let libDir = workspaceRoot.appendingPathComponent("Sources/ClibffiWindows/lib", isDirectory: true)
        let dll = libDir.appendingPathComponent("libffi-8.dll")
        let lib = libDir.appendingPathComponent("libffi-8.lib")
        let fm = FileManager.default
        guard fm.fileExists(atPath: dll.path), fm.fileExists(atPath: lib.path) else {
            return WindowsLibffiBundle(dll: nil, buildEnvironmentOverrides: [:])
        }

        return WindowsLibffiBundle(
            dll: dll,
            buildEnvironmentOverrides: [
                "KIRA_WINDOWS_LIBFFI": "1"
            ]
        )
        #else
        return WindowsLibffiBundle(dll: nil, buildEnvironmentOverrides: [:])
        #endif
    }
}
