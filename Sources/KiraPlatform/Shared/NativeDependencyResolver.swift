import Foundation

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
    public static func prepareRuntimePackage(from kiraRoot: URL, into buildRoot: URL) throws -> URL {
        let fileManager = FileManager.default
        let packageRoot = buildRoot.appendingPathComponent("KiraRuntimePackage", isDirectory: true)
        let sourcesRoot = packageRoot.appendingPathComponent("Sources", isDirectory: true)
        let clibffiRoot = sourcesRoot.appendingPathComponent("Clibffi", isDirectory: true)
        let kiraVMRoot = sourcesRoot.appendingPathComponent("KiraVM", isDirectory: true)

        try fileManager.createDirectory(at: clibffiRoot, withIntermediateDirectories: true, attributes: nil)
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
        let destinationDirectory = buildRoot
            .appendingPathComponent("vendor", isDirectory: true)
            .appendingPathComponent("libffi", isDirectory: true)
            .appendingPathComponent("iphoneos", isDirectory: true)
        let destinationStub = destinationDirectory.appendingPathComponent("libffi.tbd")

        if FileManager.default.fileExists(atPath: destinationStub.path) {
            return destinationDirectory
        }

        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true, attributes: nil)
        try makeIOSDeviceLibffiStub(minimumVersion: minimumVersion)
            .write(to: destinationStub, atomically: true, encoding: .utf8)
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
                    name: "KiraVM",
                    dependencies: ["Clibffi"],
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

    private static func makeIOSDeviceLibffiStub(minimumVersion: String) -> String {
        """
        --- !tapi-tbd
        tbd-version:     4
        targets:         [ arm64-ios, arm64e-ios ]
        install-name:    '/usr/lib/libffi.dylib'
        current-version: 40
        compat-version:  1
        swift-abi-version: 0
        parent-umbrella: ''
        exports:
          - targets:         [ arm64-ios, arm64e-ios ]
            symbols:         [ _ffi_call, _ffi_closure_alloc, _ffi_closure_free, _ffi_find_closure_for_code_np,
                               _ffi_get_struct_offsets, _ffi_java_ptrarray_to_raw, _ffi_java_raw_call,
                               _ffi_java_raw_size, _ffi_java_raw_to_ptrarray, _ffi_prep_cif,
                               _ffi_prep_cif_var, _ffi_prep_closure_loc, _ffi_prep_java_raw_closure,
                               _ffi_prep_java_raw_closure_loc, _ffi_prep_raw_closure, _ffi_prep_raw_closure_loc,
                               _ffi_ptrarray_to_raw, _ffi_raw_call, _ffi_raw_size, _ffi_raw_to_ptrarray,
                               _ffi_tramp_alloc, _ffi_tramp_free, _ffi_tramp_get_addr, _ffi_tramp_is_supported,
                               _ffi_tramp_set_parms, _ffi_type_complex_double, _ffi_type_complex_float,
                               _ffi_type_double, _ffi_type_float, _ffi_type_pointer, _ffi_type_sint16,
                               _ffi_type_sint32, _ffi_type_sint64, _ffi_type_sint8, _ffi_type_uint16,
                               _ffi_type_uint32, _ffi_type_uint64, _ffi_type_uint8, _ffi_type_void ]
        ...
        """
    }

    private static func generatedModuleMap() -> String {
        """
        module KiraVM {
            header "KiraVM-Swift.h"
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
