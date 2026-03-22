import XCTest
import KiraVM
@testable import KiraCompiler

final class TypeMethodTests: XCTestCase {
    func testInstanceMethod() throws {
        let src = SourceText(file: "type_method_instance.kira", text: """
        type Rectangle {
            var width: Int
            var height: Int

            function area() -> Int {
                return width * height
            }
        }

        function main() -> Int {
            let rect = Rectangle(width: 10, height: 5)
            return rect.area()
        }
        """)

        let output = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let module = try BytecodeLoader().load(data: try XCTUnwrap(output.bytecode))
        let vm = VirtualMachine(module: module, output: { _ in })
        let result = try vm.run(function: "main")
        XCTAssertEqual(result, .int(50))
    }

    func testStaticMethod() throws {
        let src = SourceText(file: "type_method_static.kira", text: """
        type Rectangle {
            var width: Int
            var height: Int

            static function unit() -> Rectangle {
                return Rectangle(width: 1, height: 1)
            }
        }

        function main() -> Int {
            let rect = Rectangle.unit()
            return rect.width + rect.height
        }
        """)

        let output = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let module = try BytecodeLoader().load(data: try XCTUnwrap(output.bytecode))
        let vm = VirtualMachine(module: module, output: { _ in })
        let result = try vm.run(function: "main")
        XCTAssertEqual(result, .int(2))
    }

    func testMethodSelfAccess() throws {
        let src = SourceText(file: "type_method_self_access.kira", text: """
        type Counter {
            var value: Int = 0

            function bump(delta: Int) -> Int {
                value = value + delta
                return self.value
            }
        }

        function main() -> Int {
            let counter = Counter()
            return counter.bump(delta: 3)
        }
        """)

        let output = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let module = try BytecodeLoader().load(data: try XCTUnwrap(output.bytecode))
        let vm = VirtualMachine(module: module, output: { _ in })
        let result = try vm.run(function: "main")
        XCTAssertEqual(result, .int(3))
    }

    func testMethodChaining() throws {
        let src = SourceText(file: "type_method_chaining.kira", text: """
        type Counter {
            var value: Int = 0

            function add(delta: Int) -> Counter {
                return Counter(value: value + delta)
            }
        }

        function main() -> Int {
            let counter = Counter(value: 1)
            return counter.add(delta: 2).add(delta: 3).value
        }
        """)

        let output = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let module = try BytecodeLoader().load(data: try XCTUnwrap(output.bytecode))
        let vm = VirtualMachine(module: module, output: { _ in })
        let result = try vm.run(function: "main")
        XCTAssertEqual(result, .int(6))
    }
}
