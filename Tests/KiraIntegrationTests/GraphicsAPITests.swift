import XCTest
import Foundation

final class GraphicsAPITests: XCTestCase {
    func testGraphicsPackageFilesExist() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let pkg = cwd.appendingPathComponent("KiraPackages/Kira.Graphics/Package.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pkg.path))
    }
}

