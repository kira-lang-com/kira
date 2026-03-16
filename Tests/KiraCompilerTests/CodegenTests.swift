import XCTest
@testable import KiraCompiler

final class CodegenTests: XCTestCase {
    func testEmitsBytecode() throws {
        let src = SourceText(file: "t.kira", text: "function main() { let x = 1 + 2 return }")
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        XCTAssertNotNil(out.bytecode)
        XCTAssertGreaterThan(out.bytecode?.count ?? 0, 0)
    }
}

