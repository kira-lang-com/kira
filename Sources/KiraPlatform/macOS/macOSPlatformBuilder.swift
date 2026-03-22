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

        let artifacts = try compileProject(
            at: stagingRoot,
            target: .macOS(arch: .arm64),
            projectName: config.appName,
            targetAppIdentifier: config.bundleID
        )
        let bytecodeURL = sourcesDir.appendingPathComponent("\(config.appName).kirbc")
        let manifestURL = sourcesDir.appendingPathComponent("\(config.appName).kirpatch.json")
        try artifacts.bytecode.write(to: bytecodeURL, options: .atomic)
        try artifacts.manifest.write(to: manifestURL, options: .atomic)

        try macOSAppTemplate.generate(
            appName: config.appName,
            projectName: config.appName,
            targetAppIdentifier: config.bundleID,
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
            manifestPath: manifestURL.path,
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
        if !text.contains("extern function kira_sg_setup() -> CVoid") {
            text.append("\n@ffi(lib: \"\")\nextern function kira_sg_setup() -> CVoid\n")
        }
        if !text.contains("extern function kira_sg_begin_default_pass(") {
            text.append(
                """

                @ffi(lib: "")
                extern function kira_sg_begin_default_pass(clearEnabled: CBool, r: CFloat, g: CFloat, b: CFloat, a: CFloat, label: CPointer<CInt8>) -> CVoid

                @ffi(lib: "")
                extern function kira_sg_apply_vertex_buffer(buffer: sg_buffer) -> CVoid
                """
            )
        }
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
        applicationText = updatedApplicationText.replacingOccurrences(
            of: "    sg_setup(desc: sg_desc(environment: sglue_environment()))",
            with: "    kira_sg_setup()"
        )
        if !applicationText.contains("function graphics_on_reload() {") {
            applicationText.append(
                """

                @Doc("Reload hook invoked after the hosted Kira VM has been recreated inside an already-running native app.
                Rebinds the active scene to the live graphics backend without restarting the native shell.
                This keeps hot reload deterministic while preserving host-owned graphics state.")
                function graphics_on_reload() {
                    graphicsDevice = GraphicsDevice(backend: sg_query_backend())
                    graphicsScene.onLoad(device: graphicsDevice)
                    return
                }
                """
            )
        }
        try applicationText.write(to: graphicsApplication, atomically: true, encoding: .utf8)

        let commandBufferURL = stagingRoot
            .appendingPathComponent("KiraPackages", isDirectory: true)
            .appendingPathComponent("Kira.Graphics", isDirectory: true)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("Core", isDirectory: true)
            .appendingPathComponent("CommandBuffer.kira")
        var commandBufferText = try String(contentsOf: commandBufferURL, encoding: .utf8)
        let hostedRender = [
            "    function render(descriptor: RenderPassDescriptor) -> RenderEncoder {",
            "        let load_action = descriptor.clearEnabled ? SG_LOADACTION_CLEAR : SG_LOADACTION_LOAD",
            "        let clear = sg_color(",
            "            r: descriptor.clearColor.r,",
            "            g: descriptor.clearColor.g,",
            "            b: descriptor.clearColor.b,",
            "            a: descriptor.clearColor.a)",
            "        let color_action = sg_color_attachment_action(",
            "            load_action: load_action,",
            "            store_action: SG_STOREACTION_STORE,",
            "            clear_value: clear)",
            "        let pass_action = sg_pass_action(",
            "            colors: CArray8_sg_color_attachment_action(_0: color_action),",
            "            depth: sg_depth_attachment_action(),",
            "            stencil: sg_stencil_attachment_action())",
            "        let pass = sg_pass(",
            "            _start_canary: 0,",
            "            compute: false,",
            "            action: pass_action,",
            "            attachments: sg_attachments(),",
            "            swapchain: sglue_swapchain(),",
            "            label: descriptor.label,",
            "            _end_canary: 0)",
            "        sg_begin_pass(pass: pass)",
            "        return RenderEncoder()",
            "    }",
        ].joined(separator: "\n")
        let nativeRender = [
            "    function render(descriptor: RenderPassDescriptor) -> RenderEncoder {",
            "        kira_sg_begin_default_pass(",
            "            clearEnabled: descriptor.clearEnabled,",
            "            r: descriptor.clearColor.r,",
            "            g: descriptor.clearColor.g,",
            "            b: descriptor.clearColor.b,",
            "            a: descriptor.clearColor.a,",
            "            label: descriptor.label)",
            "        return RenderEncoder()",
            "    }",
        ].joined(separator: "\n")
        commandBufferText = commandBufferText.replacingOccurrences(of: hostedRender, with: nativeRender)
        try commandBufferText.write(to: commandBufferURL, atomically: true, encoding: .utf8)

        let renderEncoderURL = stagingRoot
            .appendingPathComponent("KiraPackages", isDirectory: true)
            .appendingPathComponent("Kira.Graphics", isDirectory: true)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("Core", isDirectory: true)
            .appendingPathComponent("RenderEncoder.kira")
        var renderEncoderText = try String(contentsOf: renderEncoderURL, encoding: .utf8)
        let hostedDraw = [
            "    function draw(primitive: Primitive, count: Int) {",
            "        sg_apply_pipeline(pip: pipeline.handle)",
            "        let bindings = sg_bindings(",
            "            _start_canary: 0,",
            "            vertex_buffers: CArray8_sg_buffer(_0: vertex0.handle),",
            "            vertex_buffer_offsets: CArray8_CInt32(),",
            "            index_buffer: sg_buffer(),",
            "            index_buffer_offset: 0,",
            "            views: CArray32_sg_view(),",
            "            samplers: CArray12_sg_sampler(),",
            "            _end_canary: 0)",
            "        sg_apply_bindings(bindings: bindings)",
            "        sg_draw(base_element: 0, num_elements: count, num_instances: 1)",
            "        return",
            "    }",
        ].joined(separator: "\n")
        let nativeDraw = [
            "    function draw(primitive: Primitive, count: Int) {",
            "        sg_apply_pipeline(pip: pipeline.handle)",
            "        kira_sg_apply_vertex_buffer(buffer: vertex0.handle)",
            "        sg_draw(base_element: 0, num_elements: count, num_instances: 1)",
            "        return",
            "    }",
        ].joined(separator: "\n")
        renderEncoderText = renderEncoderText.replacingOccurrences(of: hostedDraw, with: nativeDraw)
        try renderEncoderText.write(to: renderEncoderURL, atomically: true, encoding: .utf8)
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

    private func compileProject(
        at root: URL,
        target: PlatformTarget,
        projectName: String,
        targetAppIdentifier: String
    ) throws -> (bytecode: Data, manifest: Data) {
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
        let patchCompiler = PatchCompiler(config: .init(
            sessionID: "bootstrap",
            sessionToken: "bootstrap",
            projectName: projectName,
            targetAppIdentifier: targetAppIdentifier,
            target: target
        ))
        let bundle = try patchCompiler.buildPatch(from: sources, sourceFiles: sourceFiles, generation: 0)
        let manifest = try JSONEncoder().encode(bundle.manifest)
        return (bundle.bytecode, manifest)
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
        #define SOKOL_API_IMPL __attribute__((visibility("default")))
        #define SOKOL_API_DECL extern __attribute__((visibility("default")))
        #define SOKOL_APP_API_DECL extern __attribute__((visibility("default")))
        #define SOKOL_GLUE_API_DECL extern __attribute__((visibility("default")))

        #import <Metal/Metal.h>
        #import <MetalKit/MetalKit.h>
        #import <QuartzCore/QuartzCore.h>
        #include <stdbool.h>

        #include "vendor/sokol/sokol_app.h"
        #include "vendor/sokol/sokol_gfx.h"
        #include "vendor/sokol/sokol_glue.h"
        #include "vendor/sokol/sokol_log.h"

        __attribute__((visibility("default"))) void kira_sg_setup(void) {
            sg_desc desc = {0};
            desc.environment = sglue_environment();
            desc.logger.func = slog_func;
            sg_setup(&desc);
        }

        __attribute__((visibility("default"))) void kira_sg_begin_default_pass(bool clearEnabled, float r, float g, float b, float a, const char* label) {
            sg_pass pass = {0};
            pass.swapchain = sglue_swapchain();
            pass.label = label;
            pass.action.colors[0].load_action = clearEnabled ? SG_LOADACTION_CLEAR : SG_LOADACTION_LOAD;
            pass.action.colors[0].store_action = SG_STOREACTION_STORE;
            pass.action.colors[0].clear_value = (sg_color){ .r = r, .g = g, .b = b, .a = a };
            sg_begin_pass(&pass);
        }

        __attribute__((visibility("default"))) void kira_sg_apply_vertex_buffer(sg_buffer buffer) {
            sg_bindings bindings = {0};
            bindings.vertex_buffers[0] = buffer;
            sg_apply_bindings(&bindings);
        }
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
