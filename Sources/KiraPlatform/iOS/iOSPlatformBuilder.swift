import Foundation
import KiraCompiler

public struct iOSPlatformBuilder {
    public init() {}

    public func build(config: AppleBuildConfiguration) throws {
        let fileManager = FileManager.default
        print("  Preparing build directory...")
        if fileManager.fileExists(atPath: config.buildRoot.path) {
            try fileManager.removeItem(at: config.buildRoot)
        }

        let sourcesDir = config.buildRoot.appendingPathComponent("Sources", isDirectory: true)
        let stagingRoot = config.buildRoot.appendingPathComponent("Staging", isDirectory: true)
        try fileManager.createDirectory(at: sourcesDir, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true, attributes: nil)
        print("  Preparing runtime package...")
        let runtimePackageRoot = try NativeDependencyResolver.prepareRuntimePackage(from: config.kiraRoot, into: config.buildRoot)
        print("  Building iPhoneOS libffi...")
        let deviceLibFFIDirectory = try NativeDependencyResolver.prepareIOSDeviceLibffi(into: config.buildRoot, minimumVersion: config.minimumVersion)

        print("  Staging Sokol...")
        _ = try SokolVendor.resolve(into: sourcesDir.appendingPathComponent("vendor/sokol", isDirectory: true).path)
        print("  Staging Kira sources...")
        try stageSources(for: config, into: stagingRoot)
        print("  Running bindgen...")
        try runBindgen(for: config)

        print("  Compiling Kira bytecode...")
        let bytecode = try compileProject(at: stagingRoot, target: .iOS(arch: .arm64))
        let bytecodeURL = sourcesDir.appendingPathComponent("\(config.appName).kirbc")
        try bytecode.write(to: bytecodeURL, options: .atomic)

        print("  Writing platform sources...")
        try AppDelegateTemplate.generate(
            appName: config.appName,
            title: config.title,
            width: config.width,
            height: config.height
        ).write(to: sourcesDir.appendingPathComponent("AppDelegate.swift"), atomically: true, encoding: .utf8)

        try BridgingHeaderTemplate.generate(platform: .iOS)
            .write(to: sourcesDir.appendingPathComponent("KiraBridging.h"), atomically: true, encoding: .utf8)

        try makeSokolImplementation(for: .iOS)
            .write(to: sourcesDir.appendingPathComponent("sokol_impl.m"), atomically: true, encoding: .utf8)

        try makeInfoPlist(for: config, platform: .iOS)
            .write(to: config.buildRoot.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        let targetedFamily = makeTargetedDeviceFamily(from: config)
        let projectPath = config.buildRoot.appendingPathComponent("\(config.appName).xcodeproj")
        print("  Generating Xcode project...")
        try XcodeProjGenerator().generate(config: .init(
            appName: config.appName,
            bundleID: config.bundleID,
            teamID: config.teamID,
            minimumVersion: config.minimumVersion,
            targetPlatform: .iOS,
            frameworks: config.frameworks,
            staticLibs: config.libraries,
            headerSearchPaths: config.headerSearchPaths,
            deviceOnlyLibrarySearchPaths: [deviceLibFFIDirectory.path],
            bytecodePath: bytecodeURL.path,
            kiraPackagePath: runtimePackageRoot.path,
            outputPath: projectPath.path,
            targetedDeviceFamily: targetedFamily
        ))
        try NativeDependencyResolver.prepareGeneratedModuleMaps(
            into: config.buildRoot,
            variants: ["GeneratedModuleMaps", "GeneratedModuleMaps-iphoneos", "GeneratedModuleMaps-iphonesimulator"]
        )

        if !config.pods.isEmpty {
            let podfile = PodfileTemplate.generate(
                appName: config.appName,
                pods: config.pods,
                minimumVersion: config.minimumVersion
            )
            let podfileURL = config.buildRoot.appendingPathComponent("Podfile")
            try podfile.write(to: podfileURL, atomically: true, encoding: .utf8)
            try runProcess("/usr/bin/env", args: ["pod", "install", "--project-directory=\(config.buildRoot.path)"])
        }
    }

    private func stageSources(for config: AppleBuildConfiguration, into stagingRoot: URL) throws {
        let fileManager = FileManager.default
        let stagedSources = stagingRoot.appendingPathComponent("Sources", isDirectory: true)
        let stagedPackages = stagingRoot.appendingPathComponent("KiraPackages", isDirectory: true)
        try fileManager.copyItem(at: config.projectRoot.appendingPathComponent("Sources", isDirectory: true), to: stagedSources)
        try fileManager.copyItem(at: config.kiraRoot.appendingPathComponent("KiraPackages", isDirectory: true), to: stagedPackages)

        let sokolBindings = stagedPackages
            .appendingPathComponent("Kira.Graphics", isDirectory: true)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("Platform", isDirectory: true)
            .appendingPathComponent("sokol.kira")
        var text = try String(contentsOf: sokolBindings, encoding: .utf8)
        text = text.replacingOccurrences(of: #"@ffi(lib: "FFI/libsokol.dylib")"#, with: #"@ffi(lib: "")"#)
        text = text.replacingOccurrences(of: #"// Library: FFI/libsokol.dylib"#, with: #"// Library: current process"#)
        try text.write(to: sokolBindings, atomically: true, encoding: .utf8)

        let graphicsApplication = stagedPackages
            .appendingPathComponent("Kira.Graphics", isDirectory: true)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("Frame", isDirectory: true)
            .appendingPathComponent("Application.kira")
        var applicationText = try String(contentsOf: graphicsApplication, encoding: .utf8)
        let embeddedRun = [
            "function run(scene: Scene) {",
            "        graphicsScene = scene",
            "        graphicsDevice = GraphicsDevice()",
            "        graphicsFrameIndex = 0",
            "        return",
            "    }",
            "}",
        ].joined(separator: "\n")
        let hostedRun = [
            "function run(scene: Scene) {",
            "        graphicsScene = scene",
            "        graphicsDevice = GraphicsDevice()",
            "        graphicsFrameIndex = 0",
            "",
            "        sapp_run(desc: sapp_desc(",
            "            init_cb: graphics_on_init,",
            "            frame_cb: graphics_on_frame,",
            "            cleanup_cb: graphics_on_cleanup,",
            "            width: width,",
            "            height: height,",
            "            sample_count: sampleCount,",
            "            high_dpi: highDPI,",
            "            window_title: title))",
            "        return",
            "    }",
            "}",
        ].joined(separator: "\n")
        let updatedApplicationText = applicationText.replacingOccurrences(of: hostedRun, with: embeddedRun)
        guard updatedApplicationText != applicationText else {
            throw NSError(
                domain: "KiraPlatform",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to patch Kira.Graphics Application.run for embedded Apple runtime"]
            )
        }
        applicationText = updatedApplicationText
        try applicationText.write(to: graphicsApplication, atomically: true, encoding: .utf8)
    }

    private func runBindgen(for config: AppleBuildConfiguration) throws {
        guard !config.ffiLibraries.isEmpty else {
            return
        }

        let engine = BindgenEngine()
        for ffi in config.ffiLibraries {
            let bindings = engine.generate(headerPath: ffi.headerPath, libraryName: "", platform: .iOS)
            let outputURL = URL(fileURLWithPath: ffi.bindingsOutputPath)
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try bindings.write(to: outputURL, atomically: true, encoding: .utf8)
        }
    }

    private func compileProject(at root: URL, target: PlatformTarget) throws -> Data {
        let fileManager = FileManager.default
        let previousDirectory = fileManager.currentDirectoryPath
        guard fileManager.changeCurrentDirectoryPath(root.path) else {
            throw NSError(
                domain: "KiraPlatform",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to switch into staged project root at \(root.path)"]
            )
        }
        defer {
            _ = fileManager.changeCurrentDirectoryPath(previousDirectory)
        }

        let sourceFiles = try collectKiraSources(in: root.appendingPathComponent("Sources", isDirectory: true))
        let sources = try sourceFiles.map { url in
            SourceText(file: url.path, text: try String(contentsOf: url, encoding: .utf8))
        }
        let output = try CompilerDriver().compile(sources: sources, target: target)
        guard let bytecode = output.bytecode else {
            throw NSError(domain: "KiraPlatform", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing bytecode output"])
        }
        return bytecode
    }

    private func collectKiraSources(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }

        var sources: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "kira" {
            sources.append(url)
        }
        return sources.sorted { $0.path < $1.path }
    }

    private func makeSokolImplementation(for platform: AppleBuildPlatform) -> String {
        let platformDefine = platform == .iOS ? "SOKOL_METAL_IOS" : "SOKOL_METAL_MACOS"
        return """
        // sokol_impl.m — AUTO-GENERATED by kira build
        // Do not edit.
        #define SOKOL_IMPL
        #define SOKOL_NO_ENTRY
        #define SOKOL_METAL
        #define \(platformDefine)

        #import <Metal/Metal.h>
        #import <MetalKit/MetalKit.h>
        #import <QuartzCore/QuartzCore.h>

        #include "vendor/sokol/sokol_app.h"
        #include "vendor/sokol/sokol_gfx.h"
        #include "vendor/sokol/sokol_glue.h"
        #include "vendor/sokol/sokol_log.h"
        """
    }

    private func makeInfoPlist(for config: AppleBuildConfiguration, platform: AppleBuildPlatform) throws -> String {
        let relativePath = platform == .iOS ? "iOS/Info.plist.template" : "macOS/Info.plist.template"
        var template = try NativeDependencyResolver.loadTemplate(relativePath)
        template = template.replacingOccurrences(of: "{{APP_NAME}}", with: config.appName)
        template = template.replacingOccurrences(of: "{{BUNDLE_ID}}", with: config.bundleID)
        template = template.replacingOccurrences(of: "{{MINIMUM_VERSION}}", with: config.minimumVersion)
        return template
    }

    private func makeTargetedDeviceFamily(from config: AppleBuildConfiguration) -> String {
        let desired = config.deviceFamily
        let fallback = desired.isEmpty ? "1,2" : desired.map(deviceFamilyValue(for:)).joined(separator: ",")
        return fallback.isEmpty ? "1,2" : fallback
    }

    private func deviceFamilyValue(for family: String) -> String {
        switch family {
        case "ipad":
            return "2"
        case "mac":
            return "6"
        default:
            return "1"
        }
    }

    private func runProcess(_ executable: String, args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "KiraPlatform",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Process failed: \(executable) \(args.joined(separator: " "))"]
            )
        }
    }
}
