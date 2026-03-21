import Foundation
import KiraCompiler
import KiraPlatform

enum BuildCommand {
    static func run(args: [String]) throws {
        var a = Args(args)
        var target: String?
        var release = false
        while let tok = a.peek() {
            if tok == "--target" {
                _ = a.next()
                target = a.next()
            } else if tok == "--release" {
                _ = a.next()
                release = true
            } else if tok == "--help" || tok == "-h" {
                print("kira build [--target <t>] [--release]")
                return
            } else {
                throw CLIError.invalidOption(tok)
            }
        }
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let manifestURL = cwd.appendingPathComponent("Kira.toml")
        let pkg = try KiraPackage.load(from: manifestURL)

        let platform: PlatformTarget
        if let target {
            guard let parsed = parseTarget(target) else {
                throw CLIError.message("unknown target '\(target)'")
            }
            platform = parsed
        } else {
            platform = defaultTargetForHost()
        }
        if platform == .iOS(arch: .arm64) {
            try buildAppleProject(manifest: pkg, projectRoot: cwd, platform: .iOS, release: release)
            return
        }
        if platform == .macOS(arch: .arm64) {
            try buildAppleProject(manifest: pkg, projectRoot: cwd, platform: .macOS, release: release)
            return
        }

        try buildBytecodeProject(manifest: pkg, projectRoot: cwd, platform: platform, release: release)
    }

    private static func parseTarget(_ s: String?) -> PlatformTarget? {
        guard let s else { return nil }
        switch s.lowercased() {
        case "ios": return .iOS(arch: .arm64)
        case "android": return .android(arch: .arm64)
        case "macos": return .macOS(arch: .arm64)
        case "linux": return .linux(arch: .x86_64)
        case "windows": return .windows(arch: .x86_64)
        case "wasm": return .wasm32
        default: return nil
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

    private static func platformName(_ t: PlatformTarget) -> String {
        t.platformName
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

    private static func buildAppleProject(
        manifest: KiraPackage,
        projectRoot: URL,
        platform: AppleBuildPlatform,
        release: Bool
    ) throws {
        try validateTargetEnabled(manifest: manifest, platform: platform)
        print("Building for \(platform.buildFolderName)...")

        let metadata = NativeDependencyResolver.inferAppMetadata(
            projectRoot: projectRoot,
            fallbackName: manifest.package.name
        )
        let kiraRoot = kiraRepositoryRoot()
        let buildRoot = projectRoot
            .appendingPathComponent(".kira-build", isDirectory: true)
            .appendingPathComponent(platform.buildFolderName, isDirectory: true)
        let native = platformConfig(for: platform, in: manifest.native)
        let ffiLibraries = NativeDependencyResolver.resolveFFILibraries(
            ffiEntries(for: native),
            relativeTo: projectRoot
        )
        let linkedLibraries = NativeDependencyResolver.resolvePaths(native?.libs ?? [], relativeTo: projectRoot)
            + ffiLibraries.map(\.libraryPath)
        let config = AppleBuildConfiguration(
            projectRoot: projectRoot,
            kiraRoot: kiraRoot,
            buildRoot: buildRoot,
            platform: platform,
            appName: manifest.package.name,
            title: metadata.title,
            width: metadata.width,
            height: metadata.height,
            minimumVersion: native?.minimumVersion ?? platform.defaultMinimumVersion,
            deviceFamily: normalizedDeviceFamily(for: platform, native: native),
            frameworks: native?.frameworks.isEmpty == false ? native!.frameworks : platform.defaultFrameworks,
            libraries: linkedLibraries,
            headerSearchPaths: NativeDependencyResolver.resolvePaths(native?.headerSearchPaths ?? [], relativeTo: projectRoot),
            pods: native?.pods ?? [:],
            ffiLibraries: ffiLibraries,
            teamID: native?.signing?.teamID ?? "",
            bundleID: resolvedBundleID(for: manifest.package.name, native: native),
            release: release || manifest.build.optimization == .release
        )

        switch platform {
        case .iOS:
            try iOSPlatformBuilder().build(config: config)
            print("✓ iOS build complete")
            print("  Open: \(buildRoot.appendingPathComponent("\(manifest.package.name).xcodeproj").path)")
        case .macOS:
            try macOSPlatformBuilder().build(config: config)
            print("✓ macOS build complete")
            print("  Open: \(buildRoot.appendingPathComponent("\(manifest.package.name).xcodeproj").path)")
        }
    }

    private static func buildBytecodeProject(
        manifest: KiraPackage,
        projectRoot: URL,
        platform: PlatformTarget,
        release: Bool
    ) throws {
        let sourcesDir = projectRoot.appendingPathComponent("Sources", isDirectory: true)
        let sourceFiles = try collectKiraSources(in: sourcesDir)
        guard !sourceFiles.isEmpty else {
            throw CLIError.message("No .kira sources found in Sources/")
        }

        let sources: [SourceText] = try sourceFiles.map { url in
            let text = try String(contentsOf: url, encoding: .utf8)
            return SourceText(file: url.path, text: text)
        }
        let driver = CompilerDriver()
        let output = try driver.compile(sources: sources, target: platform)

        let outDir = projectRoot.appendingPathComponent(
            ".kira-build/\(manifest.package.name)/\(platformName(platform))",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true, attributes: nil)

        if platform.isWasm {
            let wasmURL = outDir.appendingPathComponent("\(manifest.package.name).wasm")
            try (output.wasm ?? Data()).write(to: wasmURL, options: .atomic)
            print("Wrote \(wasmURL.path)")
            return
        }

        let bcURL = outDir.appendingPathComponent("\(manifest.package.name).kirbc")
        try (output.bytecode ?? Data()).write(to: bcURL, options: .atomic)
        print("Wrote \(bcURL.path)")

        if release || manifest.build.optimization == .release || manifest.build.executionMode == .native {
            print("note: native codegen requires llvm-c integration; bytecode output is still produced for tooling.")
        }
    }

    private static func validateTargetEnabled(manifest: KiraPackage, platform: AppleBuildPlatform) throws {
        switch platform {
        case .iOS:
            guard manifest.targets.ios else {
                throw CLIError.message("iOS target is disabled in Kira.toml")
            }
        case .macOS:
            guard manifest.targets.macos else {
                throw CLIError.message("macOS target is disabled in Kira.toml")
            }
        }
    }

    private static func platformConfig(
        for platform: AppleBuildPlatform,
        in native: KiraPackage.Native?
    ) -> KiraPackage.ApplePlatform? {
        switch platform {
        case .iOS:
            return native?.ios
        case .macOS:
            return native?.macos
        }
    }

    private static func ffiEntries(
        for platform: KiraPackage.ApplePlatform?
    ) -> [String: (header: String, lib: String, bindingsOut: String?)] {
        guard let platform else {
            return [:]
        }
        var entries: [String: (header: String, lib: String, bindingsOut: String?)] = [:]
        for (name, entry) in platform.ffi {
            entries[name] = (header: entry.header, lib: entry.lib, bindingsOut: entry.bindingsOut)
        }
        return entries
    }

    private static func resolvedBundleID(
        for appName: String,
        native: KiraPackage.ApplePlatform?
    ) -> String {
        if let bundleID = native?.signing?.bundleID, !bundleID.isEmpty {
            return bundleID
        }
        return NativeDependencyResolver.defaultBundleID(appName: appName)
    }

    private static func normalizedDeviceFamily(
        for platform: AppleBuildPlatform,
        native: KiraPackage.ApplePlatform?
    ) -> [String] {
        if platform == .macOS {
            return []
        }
        let configured = native?.deviceFamily ?? []
        if configured.isEmpty {
            return ["iphone", "ipad"]
        }
        return configured
    }

    private static func kiraRepositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
