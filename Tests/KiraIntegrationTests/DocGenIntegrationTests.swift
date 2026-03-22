import XCTest
import Foundation

final class DocGenIntegrationTests: XCTestCase {
    func testKiraGraphicsDocGeneration() throws {
        let out = tempDirectory(named: "kira-docs-graphics")
        try runKira(args: ["doc", "--package", "Kira.Graphics", "--out", out.path])

        let colorDoc = out.appendingPathComponent("types/Color.md")
        let deviceDoc = out.appendingPathComponent("types/GraphicsDevice.md")
        let frameDoc = out.appendingPathComponent("types/Frame.md")

        XCTAssertTrue(FileManager.default.fileExists(atPath: colorDoc.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: deviceDoc.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: frameDoc.path))

        let colorText = try String(contentsOf: colorDoc, encoding: .utf8)
        XCTAssertTrue(colorText.contains("RGBA color value used throughout the graphics package."))
        XCTAssertTrue(colorText.contains("### red"))
    }

    func testKiraFoundationDocGeneration() throws {
        let out = tempDirectory(named: "kira-docs-foundation")
        try runKira(args: ["doc", "--package", "Kira.Foundation", "--out", out.path])

        let foundationDoc = out.appendingPathComponent("types/UIFoundation.md")
        let textDoc = out.appendingPathComponent("types/Text.md")
        let sizeModeDoc = out.appendingPathComponent("types/SizeMode.md")

        XCTAssertTrue(FileManager.default.fileExists(atPath: foundationDoc.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: textDoc.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sizeModeDoc.path))

        let foundationText = try String(contentsOf: foundationDoc, encoding: .utf8)
        XCTAssertTrue(foundationText.contains("Primary entry point for the Kira Foundation UI layer."))
        XCTAssertTrue(foundationText.contains("### update"))
        XCTAssertTrue(foundationText.contains("### hitTest"))

        let sizeModeText = try String(contentsOf: sizeModeDoc, encoding: .utf8)
        XCTAssertTrue(sizeModeText.contains("### Fixed"))
        XCTAssertTrue(sizeModeText.contains("Consume all available space offered by the parent on this axis."))
    }

    func testDocCommandAllIncludesStdlibSurface() throws {
        let out = tempDirectory(named: "kira-docs-all")
        try runKira(args: ["doc", "--all", "--out", out.path])

        let coreDoc = out.appendingPathComponent("App/types/Core.md")
        let optionalDoc = out.appendingPathComponent("App/types/OptionalHelpers.md")

        XCTAssertTrue(FileManager.default.fileExists(atPath: coreDoc.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: optionalDoc.path))

        let optionalText = try String(contentsOf: optionalDoc, encoding: .utf8)
        XCTAssertTrue(optionalText.contains("Return whether a `Bool?` contains no value."))
    }

    func testFenceSafetyPreservation() throws {
        let out = tempDirectory(named: "kira-docs-fence")
        try runKira(args: ["doc", "--package", "Kira.Graphics", "--out", out.path])

        let deviceDoc = out.appendingPathComponent("types/GraphicsDevice.md")
        var text = try String(contentsOf: deviceDoc, encoding: .utf8)
        text = "Intro outside fences.\n\n" + text + "\n\nNotes outside fences.\n"
        try text.write(to: deviceDoc, atomically: true, encoding: .utf8)

        try runKira(args: ["doc", "--package", "Kira.Graphics", "--out", out.path])

        let rerendered = try String(contentsOf: deviceDoc, encoding: .utf8)
        XCTAssertTrue(rerendered.contains("Intro outside fences."))
        XCTAssertTrue(rerendered.contains("Notes outside fences."))
        XCTAssertTrue(rerendered.contains("### makeRenderPipeline"))
    }

    private func runKira(args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/kira")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let outputText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTFail("kira \(args.joined(separator: " ")) failed.\nstdout:\n\(outputText)\nstderr:\n\(errorText)")
        }
    }

    private func tempDirectory(named prefix: String) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }
}
