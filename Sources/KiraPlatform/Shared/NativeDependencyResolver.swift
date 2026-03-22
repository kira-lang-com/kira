import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public enum AppleBuildPlatform: String, Sendable {
    case iOS
    case macOS

    public var buildFolderName: String {
        switch self {
        case .iOS:
            return "ios"
        case .macOS:
            return "macos"
        }
    }

    public var defaultMinimumVersion: String {
        switch self {
        case .iOS:
            return "17.0"
        case .macOS:
            return "14.0"
        }
    }

    public var defaultFrameworks: [String] {
        switch self {
        case .iOS:
            return ["Metal", "MetalKit", "QuartzCore", "UIKit", "Foundation"]
        case .macOS:
            return ["Metal", "MetalKit", "Cocoa", "QuartzCore", "Foundation"]
        }
    }
}

public struct NativeFFILibrary: Sendable {
    public var name: String
    public var headerPath: String
    public var libraryPath: String
    public var bindingsOutputPath: String

    public init(name: String, headerPath: String, libraryPath: String, bindingsOutputPath: String) {
        self.name = name
        self.headerPath = headerPath
        self.libraryPath = libraryPath
        self.bindingsOutputPath = bindingsOutputPath
    }
}

public struct AppleBuildConfiguration: Sendable {
    public var projectRoot: URL
    public var kiraRoot: URL
    public var buildRoot: URL
    public var platform: AppleBuildPlatform
    public var appName: String
    public var title: String
    public var width: Int
    public var height: Int
    public var minimumVersion: String
    public var deviceFamily: [String]
    public var frameworks: [String]
    public var libraries: [String]
    public var headerSearchPaths: [String]
    public var pods: [String: String]
    public var ffiLibraries: [NativeFFILibrary]
    public var teamID: String
    public var bundleID: String
    public var release: Bool

    public init(
        projectRoot: URL,
        kiraRoot: URL,
        buildRoot: URL,
        platform: AppleBuildPlatform,
        appName: String,
        title: String,
        width: Int,
        height: Int,
        minimumVersion: String,
        deviceFamily: [String],
        frameworks: [String],
        libraries: [String],
        headerSearchPaths: [String],
        pods: [String: String],
        ffiLibraries: [NativeFFILibrary],
        teamID: String,
        bundleID: String,
        release: Bool
    ) {
        self.projectRoot = projectRoot
        self.kiraRoot = kiraRoot
        self.buildRoot = buildRoot
        self.platform = platform
        self.appName = appName
        self.title = title
        self.width = width
        self.height = height
        self.minimumVersion = minimumVersion
        self.deviceFamily = deviceFamily
        self.frameworks = frameworks
        self.libraries = libraries
        self.headerSearchPaths = headerSearchPaths
        self.pods = pods
        self.ffiLibraries = ffiLibraries
        self.teamID = teamID
        self.bundleID = bundleID
        self.release = release
    }
}

public struct AppMetadata: Sendable {
    public var title: String
    public var width: Int
    public var height: Int

    public init(title: String, width: Int, height: Int) {
        self.title = title
        self.width = width
        self.height = height
    }
}

public enum NativeDependencyResolver {
    private static let libffiVersion = "3.5.2"
    private static let libffiSourceURL = URL(string: "https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz")!
    private static let libffiSourceSHA256 = "f3a3082a23b37c293a4fcd1053147b371f2ff91fa7ea1b2a52e335676bac82dc"

    public static func prepareRuntimePackage(from kiraRoot: URL, into buildRoot: URL) throws -> URL {
        let fileManager = FileManager.default
        let packageRoot = buildRoot.appendingPathComponent("KiraRuntimePackage", isDirectory: true)
        let sourcesRoot = packageRoot.appendingPathComponent("Sources", isDirectory: true)
        let clibffiRoot = sourcesRoot.appendingPathComponent("Clibffi", isDirectory: true)
        let kiraDebugRuntimeRoot = sourcesRoot.appendingPathComponent("KiraDebugRuntime", isDirectory: true)
        let kiraVMRoot = sourcesRoot.appendingPathComponent("KiraVM", isDirectory: true)

        try fileManager.createDirectory(at: clibffiRoot, withIntermediateDirectories: true, attributes: nil)
        try fileManager.copyItem(
            at: kiraRoot.appendingPathComponent("Sources/KiraDebugRuntime", isDirectory: true),
            to: kiraDebugRuntimeRoot
        )
        try fileManager.copyItem(
            at: kiraRoot.appendingPathComponent("Sources/KiraVM", isDirectory: true),
            to: kiraVMRoot
        )

        try runtimePackageManifest().write(
            to: packageRoot.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        try runtimeFFIModuleMap().write(
            to: clibffiRoot.appendingPathComponent("module.modulemap"),
            atomically: true,
            encoding: .utf8
        )

        let sdkHeaders = try resolveLibFFIHeadersDirectory()
        let ffiHeaders = try fileManager.contentsOfDirectory(at: sdkHeaders, includingPropertiesForKeys: nil)
        for header in ffiHeaders where header.pathExtension == "h" {
            try fileManager.copyItem(at: header, to: clibffiRoot.appendingPathComponent(header.lastPathComponent))
        }
        try sanitizeFFIHeader(at: clibffiRoot.appendingPathComponent("ffi.h"))

        return packageRoot
    }

    public static func prepareIOSDeviceLibffi(into buildRoot: URL, minimumVersion: String) throws -> URL {
        let fileManager = FileManager.default
        let destinationDirectory = buildRoot
            .appendingPathComponent("vendor", isDirectory: true)
            .appendingPathComponent("libffi", isDirectory: true)
            .appendingPathComponent("iphoneos", isDirectory: true)
        let destinationLibrary = destinationDirectory.appendingPathComponent("libffi.a")

        if fileManager.fileExists(atPath: destinationLibrary.path) {
            return destinationDirectory
        }

        let cachedLibrary = try ensureIOSDeviceLibffiBuilt(minimumVersion: minimumVersion)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true, attributes: nil)
        try fileManager.copyItem(at: cachedLibrary, to: destinationLibrary)
        return destinationDirectory
    }

    public static func inferAppMetadata(projectRoot: URL, fallbackName: String) -> AppMetadata {
        let sourcesDir = projectRoot.appendingPathComponent("Sources", isDirectory: true)
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: sourcesDir, includingPropertiesForKeys: nil) else {
            return AppMetadata(title: fallbackName, width: 1280, height: 720)
        }

        var title = fallbackName
        var width = 1280
        var height = 720

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "kira" else { continue }
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            if let match = firstMatch(in: text, pattern: #"title\s*=\s*"([^"]+)""#), !match.isEmpty {
                title = match
            }
            if let match = firstMatch(in: text, pattern: #"width\s*=\s*([0-9]+)"#), let parsed = Int(match) {
                width = parsed
            }
            if let match = firstMatch(in: text, pattern: #"height\s*=\s*([0-9]+)"#), let parsed = Int(match) {
                height = parsed
            }

            if title != fallbackName && width != 1280 && height != 720 {
                return AppMetadata(title: title, width: width, height: height)
            }
        }

        return AppMetadata(title: title, width: width, height: height)
    }

    public static func prepareGeneratedModuleMaps(into buildRoot: URL, variants: [String]) throws {
        let fileManager = FileManager.default
        for variant in variants {
            let directory = buildRoot
                .appendingPathComponent("build", isDirectory: true)
                .appendingPathComponent(variant, isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            try generatedModuleMap().write(
                to: directory.appendingPathComponent("KiraVM.modulemap"),
                atomically: true,
                encoding: .utf8
            )
            try generatedSwiftHeader().write(
                to: directory.appendingPathComponent("KiraVM-Swift.h"),
                atomically: true,
                encoding: .utf8
            )
            try generatedDebugRuntimeModuleMap().write(
                to: directory.appendingPathComponent("KiraDebugRuntime.modulemap"),
                atomically: true,
                encoding: .utf8
            )
            try generatedSwiftHeader().write(
                to: directory.appendingPathComponent("KiraDebugRuntime-Swift.h"),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    public static func defaultBundleID(appName: String) -> String {
        let cleaned = appName
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
        return "com.kira.\(cleaned)"
    }

    public static func resolvePaths(_ paths: [String], relativeTo projectRoot: URL) -> [String] {
        paths.map { resolvePath($0, relativeTo: projectRoot).path }
    }

    public static func resolveFFILibraries(
        _ entries: [String: (header: String, lib: String, bindingsOut: String?)],
        relativeTo projectRoot: URL
    ) -> [NativeFFILibrary] {
        entries.keys.sorted().map { name in
            let entry = entries[name]!
            let bindingsOut = entry.bindingsOut ?? ".kira-cache/bindings/\(name).kira"
            return NativeFFILibrary(
                name: name,
                headerPath: resolvePath(entry.header, relativeTo: projectRoot).path,
                libraryPath: resolvePath(entry.lib, relativeTo: projectRoot).path,
                bindingsOutputPath: resolvePath(bindingsOut, relativeTo: projectRoot).path
            )
        }
    }

    public static func resolvePath(_ path: String, relativeTo projectRoot: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return projectRoot.appendingPathComponent(path, isDirectory: false).standardizedFileURL
    }

    public static func relativePath(from base: URL, to target: URL) -> String {
        let baseComponents = base.standardizedFileURL.pathComponents
        let targetComponents = target.standardizedFileURL.pathComponents

        var sharedIndex = 0
        while sharedIndex < baseComponents.count &&
                sharedIndex < targetComponents.count &&
                baseComponents[sharedIndex] == targetComponents[sharedIndex] {
            sharedIndex += 1
        }

        let upward = Array(repeating: "..", count: max(baseComponents.count - sharedIndex, 0))
        let downward = Array(targetComponents.dropFirst(sharedIndex))
        let joined = (upward + downward).joined(separator: "/")
        if joined.isEmpty {
            return "."
        }
        return joined
    }

    public static func loadTemplate(_ relativePath: String) throws -> String {
        let templateURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Platform", isDirectory: true)
            .appendingPathComponent(relativePath, isDirectory: false)
        return try String(contentsOf: templateURL, encoding: .utf8)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        guard match.numberOfRanges > 1, let capture = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[capture])
    }

    private static func runtimePackageManifest() -> String {
        """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "KiraRuntimeSupport",
            platforms: [
                .macOS(.v13),
                .iOS(.v17),
            ],
            products: [
                .library(name: "KiraVM", targets: ["KiraVM"]),
            ],
            targets: [
                .systemLibrary(
                    name: "Clibffi",
                    path: "Sources/Clibffi"
                ),
                .target(
                    name: "KiraDebugRuntime",
                    path: "Sources/KiraDebugRuntime"
                ),
                .target(
                    name: "KiraVM",
                    dependencies: ["Clibffi", "KiraDebugRuntime"],
                    path: "Sources/KiraVM"
                ),
            ]
        )
        """
    }

    private static func runtimeFFIModuleMap() -> String {
        """
        module Clibffi [system] {
            header "ffi.h"
            link "ffi"
            export *
        }
        """
    }

    private static func resolveLibFFIHeadersDirectory() throws -> URL {
        let candidates = [
            "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/ffi",
            "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/ffi",
        ]

        for candidate in candidates {
            let url = URL(fileURLWithPath: candidate, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        throw NSError(
            domain: "KiraPlatform",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate libffi SDK headers"]
        )
    }

    private static func sanitizeFFIHeader(at headerURL: URL) throws {
        var text = try String(contentsOf: headerURL, encoding: .utf8)
        let replacements = [
            (#"#define FFI_AVAILABLE_APPLE\s+.+$"#, "#define FFI_AVAILABLE_APPLE"),
            (#"#define FFI_AVAILABLE_APPLE_2019\s+.+$"#, "#define FFI_AVAILABLE_APPLE_2019"),
            (#"#define FFI_AVAILABLE_APPLE_2019_DEPRECATED_2020\s+.+$"#, "#define FFI_AVAILABLE_APPLE_2019_DEPRECATED_2020"),
        ]

        for (pattern, replacement) in replacements {
            let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
        }

        try text.write(to: headerURL, atomically: true, encoding: .utf8)
    }

    private static func ensureIOSDeviceLibffiBuilt(minimumVersion: String) throws -> URL {
        let fileManager = FileManager.default
        let cacheRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("kira", isDirectory: true)
            .appendingPathComponent("libffi", isDirectory: true)
        let installRoot = cacheRoot
            .appendingPathComponent("ios-arm64-\(libffiVersion)-\(minimumVersion)", isDirectory: true)
        let installLibrary = installRoot.appendingPathComponent("lib/libffi.a")

        if fileManager.fileExists(atPath: installLibrary.path) {
            return installLibrary
        }

        let archiveURL = try ensureLibffiSourceArchive(in: cacheRoot)
        let buildRoot = cacheRoot.appendingPathComponent("build-\(libffiVersion)-\(minimumVersion)", isDirectory: true)
        if fileManager.fileExists(atPath: buildRoot.path) {
            try fileManager.removeItem(at: buildRoot)
        }
        if fileManager.fileExists(atPath: installRoot.path) {
            try fileManager.removeItem(at: installRoot)
        }

        try fileManager.createDirectory(at: buildRoot, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: installRoot, withIntermediateDirectories: true, attributes: nil)

        try runProcess("/usr/bin/tar", args: ["-xf", archiveURL.path, "-C", buildRoot.path])

        let sourceRoot = buildRoot.appendingPathComponent("libffi-\(libffiVersion)", isDirectory: true)
        let sdkPath = try captureProcess(
            "/usr/bin/xcrun",
            args: ["--sdk", "iphoneos", "--show-sdk-path"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let clangPath = try captureProcess(
            "/usr/bin/xcrun",
            args: ["--sdk", "iphoneos", "-f", "clang"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let compiler = "\(clangPath) -arch arm64 -isysroot \(sdkPath) -miphoneos-version-min=\(minimumVersion)"
        let buildTriplet = "aarch64-apple-darwin"

        try runProcess(
            "/bin/sh",
            args: [
                "-lc",
                """
                export CC='\(compiler)'
                export CFLAGS='-O2'
                export LDFLAGS='-arch arm64 -isysroot \(sdkPath) -miphoneos-version-min=\(minimumVersion)'
                ./configure --host=\(buildTriplet) --disable-shared --enable-static --prefix='\(installRoot.path)'
                """
            ],
            currentDirectoryURL: sourceRoot
        )

        let configuredBuildRoot = sourceRoot.appendingPathComponent(buildTriplet, isDirectory: true)
        try runProcess("/usr/bin/make", args: ["-j\(ProcessInfo.processInfo.activeProcessorCount)"], currentDirectoryURL: configuredBuildRoot)
        try runProcess("/usr/bin/make", args: ["install"], currentDirectoryURL: configuredBuildRoot)

        guard fileManager.fileExists(atPath: installLibrary.path) else {
            throw NSError(
                domain: "KiraPlatform",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "Failed to build iPhoneOS libffi static library at \(installLibrary.path)"]
            )
        }
        return installLibrary
    }

    private static func ensureLibffiSourceArchive(in cacheRoot: URL) throws -> URL {
        let fileManager = FileManager.default
        let archiveURL = cacheRoot.appendingPathComponent("libffi-\(libffiVersion).tar.gz")
        if fileManager.fileExists(atPath: archiveURL.path) {
            try verifyLibffiArchiveIfPossible(at: archiveURL)
            return archiveURL
        }

        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true, attributes: nil)
        let data = try Data(contentsOf: libffiSourceURL)
        try verifyLibffiArchiveDataIfPossible(data)
        try data.write(to: archiveURL, options: .atomic)
        return archiveURL
    }

    private static func verifyLibffiArchiveIfPossible(at archiveURL: URL) throws {
        #if canImport(CryptoKit)
        let data = try Data(contentsOf: archiveURL)
        try verifyLibffiArchiveDataIfPossible(data)
        #else
        _ = archiveURL
        #endif
    }

    private static func verifyLibffiArchiveDataIfPossible(_ data: Data) throws {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == libffiSourceSHA256 else {
            throw NSError(
                domain: "KiraPlatform",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: "Downloaded libffi source archive failed SHA-256 verification"]
            )
        }
        #else
        _ = data
        #endif
    }

    private static func runProcess(
        _ executable: String,
        args: [String],
        currentDirectoryURL: URL? = nil
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = currentDirectoryURL

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errors = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "KiraPlatform",
                code: 9,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Command failed: \(executable) \(args.joined(separator: " "))\n\(output)\n\(errors)"
                ]
            )
        }
    }

    private static func captureProcess(
        _ executable: String,
        args: [String]
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let errors = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "KiraPlatform",
                code: 10,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Command failed: \(executable) \(args.joined(separator: " "))\n\(errors)"
                ]
            )
        }
        return output
    }

    private static func generatedModuleMap() -> String {
        """
        module KiraVM {
            header "KiraVM-Swift.h"
            requires objc
        }
        """
    }

    private static func generatedDebugRuntimeModuleMap() -> String {
        """
        module KiraDebugRuntime {
            header "KiraDebugRuntime-Swift.h"
            requires objc
        }
        """
    }

    private static func generatedSwiftHeader() -> String {
        """
        #pragma once
        """
    }
}
