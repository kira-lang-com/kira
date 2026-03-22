import XCTest
import KiraVM
@testable import KiraCompiler

private final class EnumOutputBuffer: @unchecked Sendable {
    var lines: [String] = []
}

final class EnumTests: XCTestCase {
    func testEnumConstruction() throws {
        let src = SourceText(file: "enum_test.kira", text: """
        enum Direction {
            North
            South
        }

        function main() {
            let dir = Direction.North
            print(dir == Direction.North)
            return
        }
        """)
        let output = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bytecode = try XCTUnwrap(output.bytecode)
        let module = try BytecodeLoader().load(data: bytecode)
        let buffer = EnumOutputBuffer()
        let vm = VirtualMachine(module: module, output: { buffer.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(buffer.lines, ["true"])
    }

    func testEnumPatternMatching() throws {
        let src = SourceText(file: "enum_match.kira", text: """
        enum Direction {
            North
            South
        }

        function main() {
            let dir = Direction.North
            match dir {
                North: print("north")
                South: print("south")
            }
            return
        }
        """)
        let output = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bytecode = try XCTUnwrap(output.bytecode)
        let module = try BytecodeLoader().load(data: bytecode)
        let buffer = EnumOutputBuffer()
        let vm = VirtualMachine(module: module, output: { buffer.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(buffer.lines, ["north"])
    }

    func testEnumAssociatedValues() throws {
        let src = SourceText(file: "enum_payloads.kira", text: """
        enum Shape {
            Circle(radius: Float)
            Rect(width: Float, height: Float)
            Point
        }

        function main() {
            let shape = Shape.Circle(radius: 5.0)
            let rect = Shape.Rect(width: 10.0, height: 20.0)
            match shape {
                Circle(let radius): print(radius)
                Rect(let width, let height): print(width)
                Point: print("point")
            }
            match rect {
                Circle(let radius): print(radius)
                Rect(let width, let height): print(height)
                Point: print("point")
            }
            return
        }
        """)
        let output = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bytecode = try XCTUnwrap(output.bytecode)
        let module = try BytecodeLoader().load(data: bytecode)
        let buffer = EnumOutputBuffer()
        let vm = VirtualMachine(module: module, output: { buffer.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(buffer.lines, ["5.0", "20.0"])
    }

    func testEnumInFunction() throws {
        let src = SourceText(file: "enum_function.kira", text: """
        enum Shape {
            Circle(radius: Float)
            Point
        }

        function render(shape: Shape) {
            match shape {
                Circle(let radius): print(radius)
                Point: print("point")
            }
            return
        }

        function main() {
            render(shape: Shape.Circle(radius: 9.0))
            return
        }
        """)
        let output = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bytecode = try XCTUnwrap(output.bytecode)
        let module = try BytecodeLoader().load(data: bytecode)
        let buffer = EnumOutputBuffer()
        let vm = VirtualMachine(module: module, output: { buffer.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(buffer.lines, ["9.0"])
    }
}
