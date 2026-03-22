import XCTest
@testable import KiraCompiler
import KiraDebugRuntime

final class PatchCompilerTests: XCTestCase {
    func testBuildPatchEmitsSignedManifestAndChangedModule() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("Sources/main.kira")
        try """
        function main() -> Int {
            return 1
        }
        """.write(to: sourceURL, atomically: true, encoding: .utf8)

        let compiler = PatchCompiler(config: .init(
            sessionID: "session-1",
            sessionToken: "token-1",
            projectName: "PatchTest",
            targetAppIdentifier: "com.example.patchtest",
            target: .macOS(arch: .arm64)
        ))

        let sources = [
            SourceText(file: sourceURL.path, text: try String(contentsOf: sourceURL, encoding: .utf8))
        ]
        let bundle = try compiler.buildPatch(from: sources, sourceFiles: [sourceURL], generation: 1)

        XCTAssertEqual(bundle.manifest.sessionID, "session-1")
        XCTAssertEqual(bundle.manifest.generation, 1)
        XCTAssertEqual(bundle.manifest.targetAppIdentifier, "com.example.patchtest")
        XCTAssertEqual(bundle.manifest.changedModules, ["PatchTest::main"])
        XCTAssertEqual(bundle.manifest.dependencyClosure, ["PatchTest::main"])
        XCTAssertTrue(KiraPatchAuthenticator.validate(bundle: bundle, sessionToken: "token-1"))
    }

    func testBuildPatchUsesPathStableModuleIdentifiers() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileManager = FileManager.default
        let projectColorDir = root.appendingPathComponent("Sources/UI", isDirectory: true)
        let packageColorDir = root
            .appendingPathComponent("KiraPackages", isDirectory: true)
            .appendingPathComponent("Kira.Graphics", isDirectory: true)
            .appendingPathComponent("Sources/Types", isDirectory: true)
        try fileManager.createDirectory(at: projectColorDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: packageColorDir, withIntermediateDirectories: true)

        let projectColorURL = projectColorDir.appendingPathComponent("Color.kira")
        let packageColorURL = packageColorDir.appendingPathComponent("Color.kira")

        try """
        function uiColor() -> Int {
            return 1
        }
        """.write(to: projectColorURL, atomically: true, encoding: .utf8)

        try """
        function graphicsColor() -> Int {
            return 2
        }
        """.write(to: packageColorURL, atomically: true, encoding: .utf8)

        let compiler = PatchCompiler(config: .init(
            sessionID: "session-dup",
            sessionToken: "token-dup",
            projectName: "PatchTest",
            targetAppIdentifier: "com.example.patchtest",
            target: .macOS(arch: .arm64)
        ))

        let sources = [
            SourceText(file: projectColorURL.path, text: try String(contentsOf: projectColorURL, encoding: .utf8)),
            SourceText(file: packageColorURL.path, text: try String(contentsOf: packageColorURL, encoding: .utf8)),
        ]
        let bundle = try compiler.buildPatch(
            from: sources,
            sourceFiles: [projectColorURL, packageColorURL],
            generation: 1
        )

        XCTAssertEqual(bundle.manifest.changedModules, ["Kira.Graphics::Types::Color", "PatchTest::UI::Color"])
        XCTAssertEqual(
            bundle.manifest.dependencyClosure,
            ["Kira.Graphics::Types::Color", "PatchTest::UI::Color"]
        )
        XCTAssertNoThrow(KiraRuntimeCompatibilitySnapshot(manifest: bundle.manifest))
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
