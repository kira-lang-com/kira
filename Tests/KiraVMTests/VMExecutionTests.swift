import XCTest
import KiraVM
@testable import KiraCompiler

final class VMExecutionTests: XCTestCase {
    func testRunsMain() throws {
        let src = SourceText(file: "t.kira", text: "function main() { let x = 1 + 2 print(x) return }")
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let vm = VirtualMachine(module: module, output: { _ in })
        _ = try vm.run(function: "main")
    }
}
