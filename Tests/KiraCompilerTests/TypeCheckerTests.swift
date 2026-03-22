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

    func testTypeMethodCallCompiles() throws {
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
        XCTAssertNotNil(out.bytecode)
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
        XCTAssertNotNil(out.bytecode)
    }

    func testMethodsCanUseImplicitSelfWithoutPrefix() throws {
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
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        XCTAssertNotNil(out.bytecode)
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
        XCTAssertNotNil(out.bytecode)
    }

    func testDirectConstructorWithTrailingBuilderBlockCompiles() throws {
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
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        XCTAssertNotNil(out.bytecode)
    }

    func testSynthesizedBuilderArgumentKeepsFieldInitializers() throws {
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
        XCTAssertNotNil(out.bytecode)
    }

    func testEnumCaseMemberExpressionCompiles() throws {
        let src = SourceText(file: "t.kira", text: """
        enum PixelFormat {
            case rgba8Unorm
            case bgra8Unorm
        }

        function main() {
            let format = PixelFormat.bgra8Unorm
            let matches = format == PixelFormat.bgra8Unorm
            print(matches)
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        XCTAssertNotNil(out.bytecode)
    }

    func testLeadingDotEnumCaseCompilesWithExpectedType() throws {
        let src = SourceText(file: "t.kira", text: """
        enum PixelFormat {
            case rgba8Unorm
            case bgra8Unorm
        }

        function takesFormat(format: PixelFormat) {
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
        XCTAssertNotNil(out.bytecode)
    }

    func testProtocolConformanceAndDispatchCompile() throws {
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
        XCTAssertNotNil(out.bytecode)
    }

    func testStaticTypeFieldCompiles() throws {
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
        XCTAssertNotNil(out.bytecode)
    }

    func testFixedArrayCanFlowIntoOrdinaryPointerParameter() throws {
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
        XCTAssertNotNil(out.bytecode)
    }

    func testStaticMethodCompiles() throws {
        let src = SourceText(file: "t.kira", text: """
        type Rectangle {
            var width: Int = 1

            static function unit() -> Rectangle {
                return Rectangle(width: 1)
            }
        }

        function main() {
            let rect = Rectangle.unit()
            print(rect.width)
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        XCTAssertNotNil(out.bytecode)
    }

    func testIfStatementCompilesWhenConditionIsLocalBinding() throws {
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
        XCTAssertNotNil(out.bytecode)
    }

    func testTypeConstructorUsesInstanceFieldInitializers() throws {
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
        XCTAssertNotNil(out.bytecode)
    }

    func testWhileLoopCompiles() throws {
        let src = SourceText(file: "t.kira", text: """
        function main() {
            var value = 0
            while value < 3 {
                value = value + 1
            }
            print(value)
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        XCTAssertNotNil(out.bytecode)
    }

    func testDynamicArrayOperationsCompile() throws {
        let src = SourceText(file: "t.kira", text: """
        function main() {
            var values: [Int] = []
            values.append(7)
            values.append(9)
            values[0] = values[1]
            print(values.count)
            print(values[0])
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        XCTAssertNotNil(out.bytecode)
    }

    func testStringCountCompiles() throws {
        let src = SourceText(file: "t.kira", text: """
        function main() {
            let title = "Kira"
            print(title.count)
            return
        }
        """)
        let out = try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))
        XCTAssertNotNil(out.bytecode)
    }
}
