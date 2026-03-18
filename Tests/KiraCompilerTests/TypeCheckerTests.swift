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

    func testFixedArrayCanFlowIntoFfiPointer() throws {
        let src = SourceText(file: "t.kira", text: """
        @ffi(lib: "")
        extern function strlen(s: CPointer<CInt8>) -> CUInt64

        function main() -> CUInt64 {
            let text: CArray<CInt8, 6> = [72, 101, 108, 108, 111, 0,]
            return strlen(s: text)
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        XCTAssertNotNil(out.bytecode)
    }

    func testModuleScopeStringConstantIsVisibleInFunction() throws {
        let src = SourceText(file: "t.kira", text: """
        let METAL_VS: String = "vertex-main"

        function main() {
            print(METAL_VS)
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        XCTAssertNotNil(out.bytecode)
    }

    func testCIntegerComparisonAllowsIntLiteral() throws {
        let src = SourceText(file: "t.kira", text: """
        @ffi(lib: "")
        extern function f() -> CInt64

        function main() {
            let is_one = f() == 1
            print(is_one)
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        XCTAssertNotNil(out.bytecode)
    }

    func testCStructCallbackFieldAllowsDirectFunction() throws {
        let src = SourceText(file: "t.kira", text: """
        @CStruct
        type callback_holder {
            var cb: CPointer<CVoid>
        }

        function on_init() {
            return
        }

        function main() {
            let holder = callback_holder(cb: on_init)
            print(holder)
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        XCTAssertNotNil(out.bytecode)
    }
}
