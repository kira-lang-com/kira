import XCTest
import KiraVM
@testable import KiraCompiler

final class BuilderBlockTests: XCTestCase {
    func testImplicitSelfInBuilderBlock() throws {
        let src = SourceText(file: "builder_implicit_self.kira", text: """
        type PipelineDescriptor {
            var label: String = "Draft"
        }

        type Device {
            function makePipeline(desc: PipelineDescriptor) -> String {
                return desc.label
            }
        }

        function main() {
            let device = Device()
            let label = device.makePipeline {
                label = "My Pipeline"
            }
            print(label)
            return
        }
        """)

        let output = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let module = try BytecodeLoader().load(data: try XCTUnwrap(output.bytecode))
        let buffer = BuilderBlockOutputBuffer()
        let vm = VirtualMachine(module: module, output: { buffer.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(buffer.lines, ["My Pipeline"])
    }

    func testNestedBuilderBlocks() throws {
        let src = SourceText(file: "builder_nested.kira", text: """
        type InnerDescriptor {
            var label: String = "inner"
        }

        type OuterDescriptor {
            var title: String = "outer"
            var nestedLabel: String = "none"
        }

        type Device {
            function makeInner(desc: InnerDescriptor) -> String {
                return desc.label
            }

            function makeOuter(desc: OuterDescriptor) -> String {
                return desc.nestedLabel
            }
        }

        function main() {
            let device = Device()
            let value = device.makeOuter {
                title = "frame"
                nestedLabel = device.makeInner {
                    label = "pass"
                }
            }
            print(value)
            return
        }
        """)

        let output = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let module = try BytecodeLoader().load(data: try XCTUnwrap(output.bytecode))
        let buffer = BuilderBlockOutputBuffer()
        let vm = VirtualMachine(module: module, output: { buffer.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(buffer.lines, ["pass"])
    }

    func testNamedParamBuilderBlock() throws {
        let src = SourceText(file: "builder_named_param.kira", text: """
        type TextureDescriptor {
            var label: String = "unset"
        }

        type Device {
            function makeTexture(desc: TextureDescriptor) -> String {
                return desc.label
            }
        }

        function main() {
            let device = Device()
            let label = device.makeTexture {
                label = "shadow-map"
            }
            print(label)
            return
        }
        """)

        let output = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let module = try BytecodeLoader().load(data: try XCTUnwrap(output.bytecode))
        let buffer = BuilderBlockOutputBuffer()
        let vm = VirtualMachine(module: module, output: { buffer.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(buffer.lines, ["shadow-map"])
    }

    func testBuilderBlockWithControlFlow() throws {
        let src = SourceText(file: "builder_control_flow.kira", text: """
        type TextureDescriptor {
            var label: String = "default"
        }

        type Device {
            function makeTexture(desc: TextureDescriptor) -> String {
                return desc.label
            }
        }

        function main() {
            let highlighted = true
            let device = Device()
            let label = device.makeTexture {
                if highlighted {
                    label = "selected"
                }
            }
            print(label)
            return
        }
        """)

        let output = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let module = try BytecodeLoader().load(data: try XCTUnwrap(output.bytecode))
        let buffer = BuilderBlockOutputBuffer()
        let vm = VirtualMachine(module: module, output: { buffer.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(buffer.lines, ["selected"])
    }
}

private final class BuilderBlockOutputBuffer: @unchecked Sendable {
    var lines: [String] = []
}
