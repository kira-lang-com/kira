import XCTest
import KiraVM
@testable import KiraCompiler

final class ProtocolTests: XCTestCase {
    func testProtocolConformanceCheck() throws {
        let src = SourceText(file: "protocol_conformance.kira", text: """
        protocol Drawable {
            function draw(canvas: Int) -> Void
            function bounds() -> Int
        }

        type Circle: Drawable {
            function draw(canvas: Int) -> Void {
                print(canvas)
                return
            }

            function bounds() -> Int {
                return 42
            }
        }

        function main() -> Int {
            let shape: Drawable = Circle()
            shape.draw(canvas: 3)
            return shape.bounds()
        }
        """)

        let output = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        XCTAssertNotNil(output.bytecode)
    }

    func testProtocolDynamicDispatch() throws {
        let src = SourceText(file: "protocol_dynamic_dispatch.kira", text: """
        protocol Scene {
            function tick() -> Int
        }

        type CounterScene: Scene {
            function tick() -> Int {
                return 7
            }
        }

        function run(scene: Scene) -> Int {
            return scene.tick()
        }

        function main() -> Int {
            return run(scene: CounterScene())
        }
        """)

        let output = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let module = try BytecodeLoader().load(data: try XCTUnwrap(output.bytecode))
        let vm = VirtualMachine(module: module, output: { _ in })
        let result = try vm.run(function: "main")
        XCTAssertEqual(result, .int(7))
    }

    func testProtocolMissingMethodError() throws {
        let src = SourceText(file: "protocol_missing.kira", text: """
        protocol Drawable {
            function draw(canvas: Int) -> Void
            function bounds() -> Int
        }

        type Circle: Drawable {
            function bounds() -> Int {
                return 7
            }
        }
        """)

        XCTAssertThrowsError(try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))) { error in
            let description = String(describing: error)
            XCTAssertTrue(description.contains("type 'Circle' does not conform to protocol 'Drawable'"))
            XCTAssertTrue(description.contains("missing: function draw(canvas: Int) -> Void"))
        }
    }

    func testMultipleProtocolConformance() throws {
        let src = SourceText(file: "multiple_protocols.kira", text: """
        protocol Tickable {
            function tick() -> Int
        }

        protocol Resettable {
            function reset() -> Int
        }

        type Counter: Tickable, Resettable {
            function tick() -> Int {
                return 5
            }

            function reset() -> Int {
                return 0
            }
        }

        function main() -> Int {
            let tickable: Tickable = Counter()
            let resettable: Resettable = Counter()
            return tickable.tick() + resettable.reset()
        }
        """)

        let output = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let module = try BytecodeLoader().load(data: try XCTUnwrap(output.bytecode))
        let vm = VirtualMachine(module: module, output: { _ in })
        let result = try vm.run(function: "main")
        XCTAssertEqual(result, .int(5))
    }
}
