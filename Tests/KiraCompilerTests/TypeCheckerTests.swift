import XCTest
@testable import KiraCompiler

final class TypeCheckerTests: XCTestCase {
    func testExplicitFloatAllowsIntLiteralCoercion() throws {
        let src = SourceText(file: "t.kira", text: "function main() { let x: Float = 12 return }")
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        XCTAssertNotNil(out.bytecode)
    }

    func testImplicitFloatDoesNotAllowIntLiteral() throws {
        let src = SourceText(file: "t.kira", text: "function f(a: Float) -> Void { return }\nfunction main() { f(a: 12) return }")
        XCTAssertThrowsError(try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64)))
    }
}

