import XCTest
import Foundation
import KiraVM
@testable import KiraCompiler

private final class GraphicsOutputBuffer: @unchecked Sendable {
    var lines: [String] = []
}

final class GraphicsAPITests: XCTestCase {
    func testGraphicsPackageFilesExist() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let pkg = cwd.appendingPathComponent("KiraPackages/Kira.Graphics/Package.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pkg.path))
    }

    func testGraphicsPackageOwnsSokolBindings() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let exampleFFI = cwd.appendingPathComponent("SokolGfxKira/FFI")
        let packageFFI = cwd.appendingPathComponent("KiraPackages/Kira.Graphics/FFI")

        XCTAssertFalse(FileManager.default.fileExists(atPath: exampleFFI.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageFFI.appendingPathComponent("libsokol.dylib").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageFFI.appendingPathComponent("sokol_all.h").path))
    }

    func testCompilerCanImportLocalGraphicsPackage() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = SourceText(file: cwd.appendingPathComponent("Scratch/main.kira").path, text: """
        import Kira.Graphics

        type EmptyScene: Scene {
            function onLoad(device: GraphicsDevice) {
                return
            }

            function onFrame(frame: Frame) {
                return
            }

            function onResize(width: Int, height: Int) {
                return
            }

            function onUnload() {
                return
            }
        }

        function main() {
            let app = Application() {
                title = "Compile Only"
                width = 640
                height = 480
            }
            let scene = EmptyScene()
            print(app.title)
            print(scene)
            return
        }
        """)

        let output = try CompilerDriver().compile(source: source, target: .macOS(arch: .arm64))
        let bytecode = try XCTUnwrap(output.bytecode)
        let module = try BytecodeLoader().load(data: bytecode)
        let vm = VirtualMachine(module: module, output: { _ in })
        _ = try vm.run(function: "main")
    }

    func testImportedGraphicsPackageResolvesFfiLibrariesInsidePackage() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = SourceText(file: cwd.appendingPathComponent("Scratch/ffi_resolution.kira").path, text: """
        import Kira.Graphics

        function main() {
            return
        }
        """)

        let output = try CompilerDriver().compile(source: source, target: .macOS(arch: .arm64))
        let libraries = Set(output.typed.symbols.ffi.values.compactMap(\.library))
        let expected = cwd.appendingPathComponent("KiraPackages/Kira.Graphics/FFI/libsokol.dylib").path

        XCTAssertTrue(libraries.contains(expected))
        XCTAssertFalse(libraries.contains(cwd.appendingPathComponent("SokolGfxKira/FFI/libsokol.dylib").path))
    }

    func testCompilerCanUseGraphicsValueTypes() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = SourceText(file: cwd.appendingPathComponent("Scratch/value_types.kira").path, text: """
        import Kira.Graphics

        function main() {
            let clear = Color.clear
            let format: PixelFormat = .bgra8Unorm
            let primitive: Primitive = .triangles
            let vertex: VertexFormat = .float3
            print(clear.a)
            print(format == .bgra8Unorm)
            print(primitive == .triangles)
            print(vertex == .float3)
            return
        }
        """)

        let output = try CompilerDriver().compile(source: source, target: .macOS(arch: .arm64))
        let bytecode = try XCTUnwrap(output.bytecode)
        let module = try BytecodeLoader().load(data: bytecode)
        let outputBuffer = GraphicsOutputBuffer()
        let vm = VirtualMachine(module: module, output: { outputBuffer.lines.append($0) })
        _ = try vm.run(function: "__kira_init_globals")
        _ = try vm.run(function: "main")
        XCTAssertEqual(outputBuffer.lines, ["0.0", "true", "true", "true"])
    }
}
