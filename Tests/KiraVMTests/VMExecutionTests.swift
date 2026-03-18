import XCTest
import KiraVM
@testable import KiraCompiler

private final class OutputBuffer: @unchecked Sendable {
    var lines: [String] = []
}

final class VMExecutionTests: XCTestCase {
    func testRunsMain() throws {
        let src = SourceText(file: "t.kira", text: "function main() { let x = 1 + 2 print(x) return }")
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let vm = VirtualMachine(module: module, output: { _ in })
        _ = try vm.run(function: "main")
    }

    func testFixedArrayPassesToFfiAsPointer() throws {
        let src = SourceText(file: "t.kira", text: """
        @ffi(lib: "")
        extern function strlen(s: CPointer<CInt8>) -> CUInt64

        function main() -> CUInt64 {
            let text: CArray<CInt8, 6> = [72, 101, 108, 108, 111, 0,]
            return strlen(s: text)
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let vm = VirtualMachine(module: module, output: { _ in })
        let result = try vm.run(function: "main")
        XCTAssertEqual(result, .int(5))
    }

    func testTernaryAndModuleScopeStringConstantWorkTogether() throws {
        let src = SourceText(file: "t.kira", text: """
        let METAL: String = "metal"
        let D3D11: String = "d3d11"

        function main() {
            let backend = true ? D3D11 : METAL
            print(backend)
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let output = OutputBuffer()
        let vm = VirtualMachine(module: module, output: { output.lines.append($0) })
        _ = try vm.run(function: "__kira_init_globals")
        _ = try vm.run(function: "main")
        XCTAssertEqual(output.lines, ["d3d11"])
    }

    func testDirectFunctionCallbackPassesToFfi() throws {
        let libPath = FileManager.default.currentDirectoryPath + "/HelloKira/FFI/libhello_ffi.dylib"
        let src = SourceText(file: "t.kira", text: """
        @ffi(lib: "\(libPath)")
        extern function hk_invoke_callback(cb: CPointer<CVoid>, value: CInt32) -> CVoid

        function on_cb(value: Int) {
            print(value)
            return
        }

        function main() {
            hk_invoke_callback(cb: on_cb, value: 42)
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let output = OutputBuffer()
        let vm = VirtualMachine(module: module, output: { output.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(output.lines, ["42"])
    }

    func testSizeOfFixedArrayLowersToConstant() throws {
        let src = SourceText(file: "t.kira", text: """
        function main() {
            print(sizeOf(CArray<CFloat, 21>))
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let output = OutputBuffer()
        let vm = VirtualMachine(module: module, output: { output.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(output.lines, ["84"])
    }
}
