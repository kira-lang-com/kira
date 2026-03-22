import XCTest
import Foundation

final class ExampleAppTests: XCTestCase {
    func testUIDemoSampleBuildsForMacOS() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sample = root.appendingPathComponent("UIDemoSample", isDirectory: true)
        let buildRoot = sample.appendingPathComponent(".kira-build/macos", isDirectory: true)
        if FileManager.default.fileExists(atPath: buildRoot.path) {
            try FileManager.default.removeItem(at: buildRoot)
        }

        let process = Process()
        process.executableURL = root.appendingPathComponent(".build/debug/kira")
        process.arguments = ["build", "--target", "macos"]
        process.currentDirectoryURL = sample

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let stdoutURL = tempDirectory.appendingPathComponent("stdout.txt")
        let stderrURL = tempDirectory.appendingPathComponent("stderr.txt")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: Data())
        FileManager.default.createFile(atPath: stderrURL.path, contents: Data())
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()
        process.waitUntilExit()
        try stdoutHandle.close()
        try stderrHandle.close()

        let output = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let error = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""

        XCTAssertEqual(process.terminationStatus, 0, "UIDemoSample macOS build failed.\nstdout:\n\(output)\nstderr:\n\(error)")
        XCTAssertTrue(output.contains("✓ macOS build complete"), "Expected successful macOS build output.\nstdout:\n\(output)")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: buildRoot.appendingPathComponent("UIDemoSample.xcodeproj").path),
            "Expected generated Xcode project at \(buildRoot.appendingPathComponent("UIDemoSample.xcodeproj").path)"
        )

        let bytecodeURL = buildRoot.appendingPathComponent("Sources/UIDemoSample.kirbc")
        let bytecodeText = try String(decoding: Data(contentsOf: bytecodeURL), as: UTF8.self)
        XCTAssertFalse(
            bytecodeText.contains("libsokol.dylib"),
            "Expected staged macOS build bytecode to bind Sokol from the current process instead of loading libsokol.dylib.\nEmbedded strings:\n\(bytecodeText)"
        )
    }
}
