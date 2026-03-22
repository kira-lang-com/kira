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

    func testTypeMethodCallExecutes() throws {
        let src = SourceText(file: "t.kira", text: """
        type Counter {
            var value: Int

            function add(delta: Int) -> Int {
                return self.value + delta
            }
        }

        function main() -> Int {
            let counter = Counter(value: 7)
            return counter.add(delta: 5)
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let vm = VirtualMachine(module: module, output: { _ in })
        let result = try vm.run(function: "main")
        XCTAssertEqual(result, .int(12))
    }

    func testWhileLoopExecutes() throws {
        let src = SourceText(file: "t.kira", text: """
        function main() {
            var value = 0
            while value < 4 {
                value = value + 1
            }
            print(value)
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let output = OutputBuffer()
        let vm = VirtualMachine(module: module, output: { output.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(output.lines, ["4"])
    }

    func testBuilderBlockUsesImplicitSelfForFieldsAndMethods() throws {
        let src = SourceText(file: "t.kira", text: """
        type App {
            var title: String

            function setDefault() {
                self.title = "Kira"
                return
            }
        }

        function main() {
            let app = App() {
                title = "Draft"
                setDefault()
            }
            print(app.title)
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let output = OutputBuffer()
        let vm = VirtualMachine(module: module, output: { output.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(output.lines, ["Kira"])
    }

    func testMethodsCanUseImplicitSelfWithoutPrefixAtRuntime() throws {
        let src = SourceText(file: "t.kira", text: """
        type Counter {
            var value: Int = 0

            function bump(delta: Int) -> Int {
                value = value + delta
                return value
            }
        }

        function main() {
            let counter = Counter()
            print(counter.bump(delta: 3))
            print(counter.bump(delta: 4))
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let output = OutputBuffer()
        let vm = VirtualMachine(module: module, output: { output.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(output.lines, ["3", "7"])
    }

    func testTrailingBlockCanSynthesizeBuilderArgumentWithoutParens() throws {
        let src = SourceText(file: "t.kira", text: """
        type TextureDescriptor {
            var label: String
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
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let output = OutputBuffer()
        let vm = VirtualMachine(module: module, output: { output.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(output.lines, ["shadow-map"])
    }

    func testDirectConstructorWithTrailingBuilderBlockExecutes() throws {
        let src = SourceText(file: "t.kira", text: """
        type App {
            var title: String = "Draft"
            var width: Int = 640
        }

        function main() {
            let app = App {
                title = "Kira"
            }
            print(app.title)
            print(app.width)
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let output = OutputBuffer()
        let vm = VirtualMachine(module: module, output: { output.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(output.lines, ["Kira", "640"])
    }

    func testSynthesizedBuilderArgumentKeepsFieldInitializersAtRuntime() throws {
        let src = SourceText(file: "t.kira", text: """
        enum Primitive {
            case triangles
            case lines
        }

        type PipelineDescriptor {
            var primitive: Primitive = .triangles
            var label: String = "default"
        }

        type Device {
            function makePipeline(desc: PipelineDescriptor) -> Primitive {
                return desc.primitive
            }
        }

        function main() {
            let device = Device()
            let primitive = device.makePipeline {
                label = "triangle"
            }
            print(primitive == .triangles)
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let output = OutputBuffer()
        let vm = VirtualMachine(module: module, output: { output.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(output.lines, ["true"])
    }

    func testEnumCaseComparisonExecutes() throws {
        let src = SourceText(file: "t.kira", text: """
        enum PixelFormat {
            case rgba8Unorm
            case bgra8Unorm
        }

        function main() {
            let format = PixelFormat.bgra8Unorm
            print(format == PixelFormat.bgra8Unorm)
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let output = OutputBuffer()
        let vm = VirtualMachine(module: module, output: { output.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(output.lines, ["true"])
    }

    func testLeadingDotEnumCaseExecutes() throws {
        let src = SourceText(file: "t.kira", text: """
        enum PixelFormat {
            case rgba8Unorm
            case bgra8Unorm
        }

        function takesFormat(format: PixelFormat) {
            print(format == .rgba8Unorm)
            return
        }

        function main() {
            let format: PixelFormat = .bgra8Unorm
            takesFormat(format: .rgba8Unorm)
            print(format == .bgra8Unorm)
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let output = OutputBuffer()
        let vm = VirtualMachine(module: module, output: { output.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(output.lines, ["true", "true"])
    }

    func testProtocolDispatchExecutes() throws {
        let src = SourceText(file: "t.kira", text: """
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
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let vm = VirtualMachine(module: module, output: { _ in })
        let result = try vm.run(function: "main")
        XCTAssertEqual(result, .int(7))
    }

    func testStaticTypeFieldExecutes() throws {
        let src = SourceText(file: "t.kira", text: """
        type Palette {
            var code: Int
            static let black: Palette = Palette(code: 7)
        }

        function main() {
            let color = Palette.black
            print(color.code)
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
        XCTAssertEqual(output.lines, ["7"])
    }

    func testStaticMethodExecutes() throws {
        let src = SourceText(file: "t.kira", text: """
        type Rectangle {
            var width: Int = 1

            static function unit() -> Rectangle {
                return Rectangle(width: 9)
            }
        }

        function main() {
            let rect = Rectangle.unit()
            print(rect.width)
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let output = OutputBuffer()
        let vm = VirtualMachine(module: module, output: { output.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(output.lines, ["9"])
    }

    func testFixedArrayCanFlowIntoOrdinaryPointerParameterAtRuntime() throws {
        let src = SourceText(file: "t.kira", text: """
        type Device {
            function makeBuffer(data: CPointer<CVoid>, size: Int) -> Int {
                return size
            }
        }

        function main() -> Int {
            let verts: CArray<CFloat, 3> = [1.0, 2.0, 3.0,]
            let device = Device()
            return device.makeBuffer(data: verts, size: sizeOf(CArray<CFloat, 3>))
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let vm = VirtualMachine(module: module, output: { _ in })
        let result = try vm.run(function: "main")
        XCTAssertEqual(result, .int(12))
    }

    func testIfStatementExecutesWhenConditionIsLocalBinding() throws {
        let src = SourceText(file: "t.kira", text: """
        function main() {
            let shouldQuit = true
            if shouldQuit {
                print(1)
            }
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let output = OutputBuffer()
        let vm = VirtualMachine(module: module, output: { output.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(output.lines, ["1"])
    }

    func testTypeConstructorUsesInstanceFieldInitializersAtRuntime() throws {
        let src = SourceText(file: "t.kira", text: """
        type Counter {
            var value: Int = 7
        }

        function main() {
            let counter = Counter()
            print(counter.value)
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let output = OutputBuffer()
        let vm = VirtualMachine(module: module, output: { output.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(output.lines, ["7"])
    }

    func testDynamicArrayOperationsExecute() throws {
        let src = SourceText(file: "t.kira", text: """
        function main() {
            var values: [Int] = []
            values.append(7)
            values.append(9)
            print(values.count)
            print(values[1])
            values[0] = 3
            print(values[0])
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let output = OutputBuffer()
        let vm = VirtualMachine(module: module, output: { output.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(output.lines, ["2", "9", "3"])
    }

    func testStringCountExecutes() throws {
        let src = SourceText(file: "t.kira", text: """
        function main() {
            let title = "Kira"
            print(title.count)
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        let bc = try XCTUnwrap(out.bytecode)
        let module = try BytecodeLoader().load(data: bc)
        let output = OutputBuffer()
        let vm = VirtualMachine(module: module, output: { output.lines.append($0) })
        _ = try vm.run(function: "main")
        XCTAssertEqual(output.lines, ["4"])
    }
}
