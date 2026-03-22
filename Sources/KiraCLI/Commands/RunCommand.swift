import Foundation
import KiraCompiler
import KiraPlatform
import KiraVM

enum RunCommand {
    static func run(args: [String]) throws {
        let fm = FileManager.default
        var parsed = Args(args)
        var input: String?
        var target: String?
        var rebuild = false

        while let token = parsed.peek() {
            if token == "--target" {
                _ = parsed.next()
                target = parsed.next()
                if target == nil {
                    throw CLIError.missingArgument("--target <platform>")
                }
            } else if token == "--rebuild" {
                _ = parsed.next()
                rebuild = true
            } else if token == "--help" || token == "-h" {
                print("kira run [<path>] [--target macos|linux|windows|wasm] [--rebuild]")
                return
            } else if token.hasPrefix("-") {
                throw CLIError.invalidOption(token)
            } else if input == nil {
                input = parsed.next()
            } else {
                throw CLIError.message("Unexpected argument: \(token)")
            }
        }

        let inputURL: URL?
        if let input {
            let resolved = URL(fileURLWithPath: input, relativeTo: URL(fileURLWithPath: fm.currentDirectoryPath))
                .standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: resolved.path, isDirectory: &isDirectory) else {
                throw CLIError.message("Input path not found: \(resolved.path)")
            }
            inputURL = resolved
        } else {
            inputURL = nil
        }

        if let inputURL, inputURL.pathExtension == "kira" {
            try runBytecodeSources(sourceFiles: [inputURL], target: resolvedPlatformTarget(from: target))
            return
        }

        let projectRoot = inputURL ?? URL(fileURLWithPath: fm.currentDirectoryPath)
        if shouldRunNativeProject(at: projectRoot, requestedTarget: target) {
            try runNativeProject(at: projectRoot, rebuild: rebuild)
            return
        }

        let sourceFiles: [URL]
        if let inputURL {
            let sourcesDir = inputURL.appendingPathComponent("Sources", isDirectory: true)
            sourceFiles = try collectKiraSources(in: sourcesDir)
        } else {
            let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
            let sourcesDir = cwd.appendingPathComponent("Sources", isDirectory: true)
            sourceFiles = try collectKiraSources(in: sourcesDir)
        }
        guard !sourceFiles.isEmpty else {
            throw CLIError.message("No .kira sources found.")
        }

        try runBytecodeSources(sourceFiles: sourceFiles, target: resolvedPlatformTarget(from: target))
    }

    private static func runBytecodeSources(sourceFiles: [URL], target: PlatformTarget) throws {
        let sources: [SourceText] = try sourceFiles.map { url in
            let text = try String(contentsOf: url, encoding: .utf8)
            return SourceText(file: url.path, text: text)
        }
        let driver = CompilerDriver()
        let output = try driver.compile(sources: sources, target: target)
        guard let bc = output.bytecode else { throw CLIError.message("No bytecode emitted.") }

        let module = try BytecodeLoader().load(data: bc)
        let vm = VirtualMachine(module: module)
        if module.functions.contains(where: { $0.name == "__kira_init_globals" }) {
            _ = try vm.run(function: "__kira_init_globals")
        }
        _ = try vm.run(function: "main")
    }

    private static func shouldRunNativeProject(at projectRoot: URL, requestedTarget: String?) -> Bool {
        #if os(macOS)
        let targetName = (requestedTarget ?? "macos").lowercased()
        guard targetName == "macos" else {
            return false
        }
        let manifestURL = projectRoot.appendingPathComponent("Kira.toml")
        guard FileManager.default.fileExists(atPath: manifestURL.path),
              let manifest = try? KiraPackage.load(from: manifestURL) else {
            return false
        }
        return manifest.targets.macos
        #else
        return false
        #endif
    }

    private static func runNativeProject(at projectRoot: URL, rebuild: Bool) throws {
        let manifestURL = projectRoot.appendingPathComponent("Kira.toml")
        let manifest = try KiraPackage.load(from: manifestURL)
        let executableURL = projectRoot
            .appendingPathComponent(".kira-build", isDirectory: true)
            .appendingPathComponent("macos", isDirectory: true)
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("Debug", isDirectory: true)
            .appendingPathComponent("\(manifest.package.name).app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(manifest.package.name)

        if rebuild || nativeBuildNeedsRefresh(projectRoot: projectRoot, manifest: manifest, executableURL: executableURL) {
            try withCurrentDirectory(projectRoot) {
                try BuildCommand.run(args: ["--target", "macos"])
            }
        } else {
            print("Using cached macOS app")
        }

        let patchSession = try startPatchServerIfNeeded(projectRoot: projectRoot, manifest: manifest)
        defer {
            patchSession?.server.stop()
        }

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw CLIError.message("Native app executable was not found at \(executableURL.path)")
        }

        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = projectRoot
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        var environment = ProcessInfo.processInfo.environment
        if let patchSession {
            environment["KIRA_PATCH_SESSION"] = patchSession.session.sessionID
            environment["KIRA_PATCH_TOKEN"] = patchSession.session.sessionToken
            environment["KIRA_PATCH_HOST"] = "127.0.0.1"
            environment["KIRA_PATCH_PORT"] = String(patchSession.session.listeningPort)
        }
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw CLIError.message("Native app exited with status \(process.terminationStatus)")
        }
    }

    private static func nativeBuildNeedsRefresh(projectRoot: URL, manifest: KiraPackage, executableURL: URL) -> Bool {
        guard let executableDate = modificationDate(for: executableURL) else {
            return true
        }

        for url in nativeRunInputs(projectRoot: projectRoot, manifest: manifest) {
            if let inputDate = modificationDate(for: url), inputDate > executableDate {
                return true
            }
        }
        return false
    }

    private static func nativeRunInputs(projectRoot: URL, manifest: KiraPackage) -> [URL] {
        var urls: [URL] = []
        urls.append(projectRoot.appendingPathComponent("Kira.toml"))
        urls.append(currentToolchainExecutableURL())

        let sourcesDir = projectRoot.appendingPathComponent("Sources", isDirectory: true)
        if let projectSources = try? collectKiraSources(in: sourcesDir) {
            urls.append(contentsOf: projectSources)
        }

        for dependencyName in manifest.dependencies.keys.sorted() {
            if let dependencySources = resolveDependencySources(named: dependencyName, from: projectRoot),
               let kiraFiles = try? collectKiraSources(in: dependencySources) {
                urls.append(contentsOf: kiraFiles)
            }
        }

        var seen: Set<String> = []
        return urls.filter { seen.insert($0.path).inserted }
    }

    private static func currentToolchainExecutableURL() -> URL {
        URL(fileURLWithPath: CommandLine.arguments[0])
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    private static func resolveDependencySources(named dependencyName: String, from projectRoot: URL) -> URL? {
        let fm = FileManager.default
        var candidate = projectRoot
        while true {
            let sourcesDir = candidate
                .appendingPathComponent("KiraPackages", isDirectory: true)
                .appendingPathComponent(dependencyName, isDirectory: true)
                .appendingPathComponent("Sources", isDirectory: true)
            if fm.fileExists(atPath: sourcesDir.path) {
                return sourcesDir
            }

            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                return nil
            }
            candidate = parent
        }
    }

    private static func modificationDate(for url: URL) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

    private static func withCurrentDirectory<T>(_ url: URL, body: () throws -> T) throws -> T {
        let fm = FileManager.default
        let previous = fm.currentDirectoryPath
        guard fm.changeCurrentDirectoryPath(url.path) else {
            throw CLIError.message("Failed to change directory to \(url.path)")
        }
        defer {
            _ = fm.changeCurrentDirectoryPath(previous)
        }
        return try body()
    }

    private static func resolvedPlatformTarget(from requestedTarget: String?) -> PlatformTarget {
        guard let requestedTarget else {
            return defaultTargetForHost()
        }
        switch requestedTarget.lowercased() {
        case "macos":
            return .macOS(arch: .arm64)
        case "linux":
            return .linux(arch: .x86_64)
        case "windows":
            return .windows(arch: .x86_64)
        case "wasm":
            return .wasm32
        case "ios":
            return .iOS(arch: .arm64)
        case "android":
            return .android(arch: .arm64)
        default:
            return defaultTargetForHost()
        }
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

    private static func startPatchServerIfNeeded(
        projectRoot: URL,
        manifest: KiraPackage
    ) throws -> (server: PatchServer, session: PatchServer.RuntimeSession)? {
        guard manifest.build.optimization == .debug, manifest.build.hotReload else {
            return nil
        }

        let bundleID = {
            if let configured = manifest.native?.macos?.signing?.bundleID, !configured.isEmpty {
                return configured
            }
            return NativeDependencyResolver.defaultBundleID(appName: manifest.package.name)
        }()

        let startedSession = try DebugSessionSupport.start(
            projectRoot: projectRoot,
            appName: manifest.package.name,
            targetAppIdentifier: bundleID,
            target: .macOS(arch: .arm64),
            statusHandler: { status in
                switch status.kind {
                case .compileFailed, .applyFailed, .rejected:
                    fputs("[KiraPatch] \(status.kind.rawValue) g\(status.generation): \(status.detail)\n", stderr)
                default:
                    print("[KiraPatch] \(status.kind.rawValue) g\(status.generation): \(status.detail)")
                }
            }
        )
        let server = startedSession.server
        let session = startedSession.runtimeSession
        print("[KiraPatch] Session \(session.sessionID) listening on port \(session.listeningPort)")
        return (server, session)
    }
}
