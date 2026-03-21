import Foundation
import KiraCompiler

public struct macOSPlatformBuilder {
    public init() {}

    public func build(config: AppleBuildConfiguration) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: config.buildRoot.path) {
            try fileManager.removeItem(at: config.buildRoot)
        }

        let sourcesDir = config.buildRoot.appendingPathComponent("Sources", isDirectory: true)
        let stagingRoot = config.buildRoot.appendingPathComponent("Staging", isDirectory: true)
        try fileManager.createDirectory(at: sourcesDir, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true, attributes: nil)
        let runtimePackageRoot = try NativeDependencyResolver.prepareRuntimePackage(from: config.kiraRoot, into: config.buildRoot)

        _ = try SokolVendor.resolve(into: sourcesDir.appendingPathComponent("vendor/sokol", isDirectory: true).path)
        try stageSources(for: config, into: stagingRoot)
        try runBindgen(for: config)

        let bytecode = try compileProject(at: stagingRoot, target: .macOS(arch: .arm64))
        let bytecodeURL = sourcesDir.appendingPathComponent("\(config.appName).kirbc")
        try bytecode.write(to: bytecodeURL, options: .atomic)

        try macOSAppTemplate.generate(
            appName: config.appName,
            title: config.title,
            width: config.width,
            height: config.height
        ).write(to: sourcesDir.appendingPathComponent("AppDelegate.swift"), atomically: true, encoding: .utf8)

        try BridgingHeaderTemplate.generate(platform: .macOS)
            .write(to: sourcesDir.appendingPathComponent("KiraBridging.h"), atomically: true, encoding: .utf8)

        try makeSokolImplementation()
            .write(to: sourcesDir.appendingPathComponent("sokol_impl.m"), atomically: true, encoding: .utf8)

        try makeInfoPlist(for: config)
            .write(to: config.buildRoot.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        let projectPath = config.buildRoot.appendingPathComponent("\(config.appName).xcodeproj")
        try XcodeProjGenerator().generate(config: .init(
            appName: config.appName,
            bundleID: config.bundleID,
            teamID: config.teamID,
            minimumVersion: config.minimumVersion,
            targetPlatform: .macOS,
            frameworks: config.frameworks,
            staticLibs: config.libraries,
            headerSearchPaths: config.headerSearchPaths,
            bytecodePath: bytecodeURL.path,
            kiraPackagePath: runtimePackageRoot.path,
            outputPath: projectPath.path
        ))
        try NativeDependencyResolver.prepareGeneratedModuleMaps(
            into: config.buildRoot,
            variants: ["GeneratedModuleMaps"]
        )

        try runProcess("/usr/bin/xcodebuild", args: [
            "-project", projectPath.path,
            "-target", config.appName,
            "-configuration", config.release ? "Release" : "Debug",
            "-sdk", "macosx",
            "CODE_SIGNING_ALLOWED=NO",
            "build",
        ])
    }

    private func stageSources(for config: AppleBuildConfiguration, into stagingRoot: URL) throws {
        let fileManager = FileManager.default
        try fileManager.copyItem(at: config.projectRoot.appendingPathComponent("Sources", isDirectory: true), to: stagingRoot.appendingPathComponent("Sources", isDirectory: true))
        try fileManager.copyItem(at: config.kiraRoot.appendingPathComponent("KiraPackages", isDirectory: true), to: stagingRoot.appendingPathComponent("KiraPackages", isDirectory: true))

        let sokolBindings = stagingRoot
            .appendingPathComponent("KiraPackages", isDirectory: true)
            .appendingPathComponent("Kira.Graphics", isDirectory: true)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("Platform", isDirectory: true)
            .appendingPathComponent("sokol.kira")
        var text = try String(contentsOf: sokolBindings, encoding: .utf8)
        text = text.replacingOccurrences(of: #"@ffi(lib: "FFI/libsokol.dylib")"#, with: #"@ffi(lib: "")"#)
        text = text.replacingOccurrences(of: #"// Library: FFI/libsokol.dylib"#, with: #"// Library: current process"#)
        try text.write(to: sokolBindings, atomically: true, encoding: .utf8)

        let graphicsApplication = stagingRoot
            .appendingPathComponent("KiraPackages", isDirectory: true)
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
            let bindings = engine.generate(headerPath: ffi.headerPath, libraryName: "", platform: .macOS)
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

    private func makeSokolImplementation() -> String {
        """
        // sokol_impl.m — AUTO-GENERATED by kira build
        // Do not edit.
        #define SOKOL_IMPL
        #define SOKOL_NO_ENTRY
        #define SOKOL_METAL
        #define SOKOL_METAL_MACOS

        #import <Metal/Metal.h>
        #import <MetalKit/MetalKit.h>
        #import <QuartzCore/QuartzCore.h>

        #include "vendor/sokol/sokol_app.h"
        #include "vendor/sokol/sokol_gfx.h"
        #include "vendor/sokol/sokol_glue.h"
        #include "vendor/sokol/sokol_log.h"
        """
    }

    private func makeInfoPlist(for config: AppleBuildConfiguration) throws -> String {
        var template = try NativeDependencyResolver.loadTemplate("macOS/Info.plist.template")
        template = template.replacingOccurrences(of: "{{APP_NAME}}", with: config.appName)
        template = template.replacingOccurrences(of: "{{BUNDLE_ID}}", with: config.bundleID)
        template = template.replacingOccurrences(of: "{{MINIMUM_VERSION}}", with: config.minimumVersion)
        return template
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
