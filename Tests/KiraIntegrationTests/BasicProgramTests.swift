import XCTest
import KiraVM
@testable import KiraCompiler

final class BasicProgramTests: XCTestCase {
    func testSimpleProgramCompilesAndRuns() throws {
        let src = SourceText(file: "main.kira", text: """
        function main() {
            let a = 40
            let b = 2
            let c = a + b
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let module = try BytecodeLoader().load(data: try XCTUnwrap(out.bytecode))
        let vm = VirtualMachine(module: module)
        _ = try vm.run(function: "main")
    }
}

