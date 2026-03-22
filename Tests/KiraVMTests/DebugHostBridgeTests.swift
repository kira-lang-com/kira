import XCTest
@testable import KiraCompiler
@testable import KiraVM
import KiraDebugRuntime

final class DebugHostBridgeTests: XCTestCase {
    func testHostBridgeReloadsPatchAndAdvancesGeneration() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("Sources/main.kira")
        let initialSource = """
        function helper() -> Int {
            return 1
        }

        function main() -> Int {
            return helper()
        }
        """
        try initialSource.write(to: sourceURL, atomically: true, encoding: .utf8)

        let patchCompiler = PatchCompiler(config: .init(
            sessionID: "session-2",
            sessionToken: "token-2",
            projectName: "BridgeTest",
            targetAppIdentifier: "com.example.bridgetest",
            target: .macOS(arch: .arm64)
        ))

        let initialBundle = try patchCompiler.buildPatch(
            from: [SourceText(file: sourceURL.path, text: initialSource)],
            sourceFiles: [sourceURL],
            generation: 0
        )

        let bytecodeURL = root.appendingPathComponent("BridgeTest.kirbc")
        let manifestURL = root.appendingPathComponent("BridgeTest.kirpatch.json")
        try initialBundle.bytecode.write(to: bytecodeURL, options: .atomic)
        try JSONEncoder().encode(initialBundle.manifest).write(to: manifestURL, options: .atomic)

        let bridge = KiraBytecodeHostBridge()
        try bridge.boot(runtimeConfig: .init(
            appName: "BridgeTest",
            projectName: "BridgeTest",
            targetAppIdentifier: "com.example.bridgetest",
            initialBytecodeURL: bytecodeURL,
            initialManifestURL: manifestURL,
            debugModeEnabled: false
        ))

        XCTAssertEqual(bridge.currentGeneration(), 0)

        let updatedSource = """
        function helper() -> Int {
            return 2
        }

        function main() -> Int {
            return helper()
        }
        """
        try updatedSource.write(to: sourceURL, atomically: true, encoding: .utf8)
        let updatedBundle = try patchCompiler.buildPatch(
            from: [SourceText(file: sourceURL.path, text: updatedSource)],
            sourceFiles: [sourceURL],
            generation: 1
        )

        try bridge.reloadApp(patchBundle: updatedBundle)

        XCTAssertEqual(bridge.currentGeneration(), 1)
        XCTAssertEqual(bridge.debugStatus().generation, 1)
        XCTAssertEqual(bridge.debugStatus().lastCompatibilityLevel, .hotPatch)
    }

    func testHostBridgeRestoresReloadStableStateAcrossReload() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("Sources/main.kira")
        let initialSource = """
        function main() -> Int {
            print("mount-v1")
            return 0
        }

        function __kira_debug_snapshot_state() -> String {
            return "selected-tab=settings"
        }

        function __kira_debug_restore_state(snapshot: String) {
            print(snapshot)
            return
        }
        """
        try initialSource.write(to: sourceURL, atomically: true, encoding: .utf8)

        let patchCompiler = PatchCompiler(config: .init(
            sessionID: "session-restore",
            sessionToken: "token-restore",
            projectName: "BridgeRestoreTest",
            targetAppIdentifier: "com.example.bridgerestoretest",
            target: .macOS(arch: .arm64)
        ))

        let initialBundle = try patchCompiler.buildPatch(
            from: [SourceText(file: sourceURL.path, text: initialSource)],
            sourceFiles: [sourceURL],
            generation: 0
        )

        let bytecodeURL = root.appendingPathComponent("BridgeRestoreTest.kirbc")
        let manifestURL = root.appendingPathComponent("BridgeRestoreTest.kirpatch.json")
        try initialBundle.bytecode.write(to: bytecodeURL, options: .atomic)
        try JSONEncoder().encode(initialBundle.manifest).write(to: manifestURL, options: .atomic)

        final class OutputBuffer: @unchecked Sendable {
            var lines: [String] = []
        }
        let buffer = OutputBuffer()
        let bridge = KiraBytecodeHostBridge(output: { buffer.lines.append($0) })
        try bridge.boot(runtimeConfig: .init(
            appName: "BridgeRestoreTest",
            projectName: "BridgeRestoreTest",
            targetAppIdentifier: "com.example.bridgerestoretest",
            initialBytecodeURL: bytecodeURL,
            initialManifestURL: manifestURL,
            debugModeEnabled: false
        ))

        let updatedSource = """
        function main() -> Int {
            print("mount-v2")
            return 0
        }

        function __kira_debug_snapshot_state() -> String {
            return "selected-tab=settings"
        }

        function __kira_debug_restore_state(snapshot: String) {
            print("restored")
            print(snapshot)
            return
        }
        """
        try updatedSource.write(to: sourceURL, atomically: true, encoding: .utf8)
        let updatedBundle = try patchCompiler.buildPatch(
            from: [SourceText(file: sourceURL.path, text: updatedSource)],
            sourceFiles: [sourceURL],
            generation: 1
        )

        try bridge.reloadApp(patchBundle: updatedBundle)

        XCTAssertTrue(buffer.lines.contains("mount-v1"))
        XCTAssertTrue(buffer.lines.contains("mount-v2"))
        XCTAssertTrue(buffer.lines.contains("restored"))
        XCTAssertTrue(buffer.lines.contains("selected-tab=settings"))
    }

    func testHostBridgeInvokesPostReloadHookAfterReload() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("Sources/main.kira")
        let initialSource = """
        function main() -> Int {
            print("mount-v1")
            return 0
        }
        """
        try initialSource.write(to: sourceURL, atomically: true, encoding: .utf8)

        let patchCompiler = PatchCompiler(config: .init(
            sessionID: "session-post-reload",
            sessionToken: "token-post-reload",
            projectName: "BridgePostReloadTest",
            targetAppIdentifier: "com.example.bridgepostreloadtest",
            target: .macOS(arch: .arm64)
        ))

        let initialBundle = try patchCompiler.buildPatch(
            from: [SourceText(file: sourceURL.path, text: initialSource)],
            sourceFiles: [sourceURL],
            generation: 0
        )

        let bytecodeURL = root.appendingPathComponent("BridgePostReloadTest.kirbc")
        let manifestURL = root.appendingPathComponent("BridgePostReloadTest.kirpatch.json")
        try initialBundle.bytecode.write(to: bytecodeURL, options: .atomic)
        try JSONEncoder().encode(initialBundle.manifest).write(to: manifestURL, options: .atomic)

        final class OutputBuffer: @unchecked Sendable {
            var lines: [String] = []
        }
        let buffer = OutputBuffer()
        let bridge = KiraBytecodeHostBridge(output: { buffer.lines.append($0) })
        try bridge.boot(runtimeConfig: .init(
            appName: "BridgePostReloadTest",
            projectName: "BridgePostReloadTest",
            targetAppIdentifier: "com.example.bridgepostreloadtest",
            initialBytecodeURL: bytecodeURL,
            initialManifestURL: manifestURL,
            debugModeEnabled: false,
            postReloadFunction: "graphics_on_reload"
        ))

        let updatedSource = """
        function main() -> Int {
            print("mount-v2")
            return 0
        }

        function graphics_on_reload() {
            print("graphics-rebound")
            return
        }
        """
        try updatedSource.write(to: sourceURL, atomically: true, encoding: .utf8)
        let updatedBundle = try patchCompiler.buildPatch(
            from: [SourceText(file: sourceURL.path, text: updatedSource)],
            sourceFiles: [sourceURL],
            generation: 1
        )

        try bridge.reloadApp(patchBundle: updatedBundle)

        XCTAssertTrue(buffer.lines.contains("mount-v2"))
        XCTAssertTrue(buffer.lines.contains("graphics-rebound"))
    }

    private func makeTempProject() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true
        )
        return root
    }
}
