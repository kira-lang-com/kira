import Foundation
import Dispatch
import KiraCompiler
import KiraPlatform

enum WatchCommand {
    static func run(args: [String]) throws {
        var parsed = Args(args)
        var target: String?
        var localhostOnly = false
        var port: UInt16?

        while let token = parsed.peek() {
            if token == "--target" {
                _ = parsed.next()
                target = parsed.next()
            } else if token == "--localhost" {
                _ = parsed.next()
                localhostOnly = true
            } else if token == "--port" {
                _ = parsed.next()
                guard let raw = parsed.next(), let parsedPort = UInt16(raw) else {
                    throw CLIError.missingArgument("--port <number>")
                }
                port = parsedPort
            } else if token == "--help" || token == "-h" {
                print("kira watch [--target macos|ios] [--localhost] [--port <number>]")
                return
            } else {
                throw CLIError.invalidOption(token)
            }
        }

        let fm = FileManager.default
        let projectRoot = URL(fileURLWithPath: fm.currentDirectoryPath)
        let manifest = try KiraPackage.load(from: projectRoot.appendingPathComponent("Kira.toml"))
        let targetPlatform = resolvedTarget(from: target)
        let bundleID = resolvedBundleID(for: manifest, target: targetPlatform)

        let startedSession = try DebugSessionSupport.start(
            projectRoot: projectRoot,
            appName: manifest.package.name,
            targetAppIdentifier: bundleID,
            target: targetPlatform,
            localhostOnly: localhostOnly,
            port: port,
            statusHandler: { status in
                switch status.kind {
                case .compileFailed, .applyFailed, .rejected:
                    fputs("[KiraPatch] \(status.kind.rawValue) g\(status.generation): \(status.detail)\n", stderr)
                default:
                    print("[KiraPatch] \(status.kind.rawValue) g\(status.generation): \(status.detail)")
                }
            }
        )

        _ = startedSession.server
        let session = startedSession.runtimeSession
        print("Patch server listening")
        print("  session: \(session.sessionID)")
        print("  token: \(session.sessionToken)")
        print("  port: \(session.listeningPort)")
        print("  scope: \(localhostOnly ? "localhost-only requested" : "local network + localhost")")
        dispatchMain()
    }

    private static func resolvedTarget(from target: String?) -> PlatformTarget {
        switch (target ?? "macos").lowercased() {
        case "ios":
            return .iOS(arch: .arm64)
        default:
            return .macOS(arch: .arm64)
        }
    }

    private static func resolvedBundleID(for manifest: KiraPackage, target: PlatformTarget) -> String {
        switch target {
        case .iOS:
            if let configured = manifest.native?.ios?.signing?.bundleID, !configured.isEmpty {
                return configured
            }
        case .macOS:
            if let configured = manifest.native?.macos?.signing?.bundleID, !configured.isEmpty {
                return configured
            }
        default:
            break
        }
        return NativeDependencyResolver.defaultBundleID(appName: manifest.package.name)
    }
}
