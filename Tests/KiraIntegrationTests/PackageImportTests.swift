import XCTest
import Foundation
import KiraVM
@testable import KiraCompiler

private final class PackageImportOutputBuffer: @unchecked Sendable {
    var lines: [String] = []
}

final class PackageImportTests: XCTestCase {
    func testImportKiraFoundation() throws {
        let project = try makeProject(
            manifest: """
            [package]
            name = "ImportFoundation"
            version = "0.1.0"
            kira = ">=1.0.0"
            license = "Apache-2.0"

            [targets]
            macos = true

            [dependencies]
            "Kira.Foundation" = "0.1.0"
            """,
            sources: [
                "Sources/main.kira": """
                import Kira.Foundation

                function main() {
                    let ui = UIFoundation()
                    let root = VStack(items: [Text(value: "Hello"), Text(value: "World")])
                    let drawList = ui.update(root: root, bounds: Rect(x: 0.0, y: 0.0, width: 300.0, height: 200.0), input: InputState.empty)
                    print(drawList.commands.count)
                    return
                }
                """
            ],
            packages: [
                "Kira.Foundation": existingPackageSource(named: "Kira.Foundation")
            ]
        )

        let bytecode = try compileProjectMain(at: project)
        let module = try BytecodeLoader().load(data: bytecode)
        let output = PackageImportOutputBuffer()
        let vm = VirtualMachine(module: module, output: { output.lines.append($0) })
        _ = try vm.run(function: "__kira_init_globals")
        _ = try vm.run(function: "main")
        XCTAssertEqual(output.lines, ["2"])
    }

    func testImportKiraGraphics() throws {
        let project = try makeProject(
            manifest: """
            [package]
            name = "ImportGraphics"
            version = "0.1.0"
            kira = ">=1.0.0"
            license = "Apache-2.0"

            [targets]
            macos = true

            [dependencies]
            "Kira.Graphics" = "0.1.0"
            """,
            sources: [
                "Sources/main.kira": """
                import Kira.Graphics

                function main() {
                    let app = Application() {
                        title = "Test"
                        width = 800
                        height = 600
                    }
                    print(app.title)
                    return
                }
                """
            ],
            packages: [
                "Kira.Graphics": existingPackageSource(named: "Kira.Graphics")
            ]
        )

        let bytecode = try compileProjectMain(at: project)
        let module = try BytecodeLoader().load(data: bytecode)
        let output = PackageImportOutputBuffer()
        let vm = VirtualMachine(module: module, output: { output.lines.append($0) })
        _ = try vm.run(function: "__kira_init_globals")
        _ = try vm.run(function: "main")
        XCTAssertEqual(output.lines, ["Test"])
    }

    func testImportedSymbolsResolved() throws {
        let project = try makeProject(
            manifest: """
            [package]
            name = "ImportLocalPackage"
            version = "0.1.0"
            kira = ">=1.0.0"
            license = "Apache-2.0"

            [targets]
            macos = true

            [dependencies]
            "Demo.Core" = "0.1.0"
            """,
            sources: [
                "Sources/main.kira": """
                import Demo.Core

                function main() {
                    print(greeting())
                    return
                }
                """
            ],
            packages: [
                "Demo.Core": .copy([
                    "Sources/Core.kira": """
                    type DemoWidget {
                        var label: String
                    }

                    function greeting() -> String {
                        return "Hello from package"
                    }
                    """
                ])
            ]
        )

        let compileOutput = try compileProject(at: project)
        XCTAssertTrue(compileOutput.typed.symbols.types.contains("DemoWidget"))
        XCTAssertNotNil(compileOutput.typed.symbols.functions["greeting"])

        XCTAssertNotNil(compileOutput.bytecode)
    }

    func testCircularImportError() throws {
        let project = try makeProject(
            manifest: """
            [package]
            name = "CircularImports"
            version = "0.1.0"
            kira = ">=1.0.0"
            license = "Apache-2.0"

            [targets]
            macos = true

            [dependencies]
            "PackageA" = "0.1.0"
            "PackageB" = "0.1.0"
            """,
            sources: [
                "Sources/main.kira": """
                import PackageA

                function main() {
                    return
                }
                """
            ],
            packages: [
                "PackageA": .copy([
                    "Sources/PackageA.kira": """
                    import PackageB

                    function fromA() -> Int {
                        return 1
                    }
                    """
                ]),
                "PackageB": .copy([
                    "Sources/PackageB.kira": """
                    import PackageA

                    function fromB() -> Int {
                        return 2
                    }
                    """
                ])
            ]
        )

        let sourceURL = project.appendingPathComponent("Sources/main.kira")
        let source = SourceText(file: sourceURL.path, text: try String(contentsOf: sourceURL, encoding: .utf8))
        XCTAssertThrowsError(try CompilerDriver().compile(source: source, target: .macOS(arch: .arm64))) { error in
            guard let driverError = error as? CompilerDriverError else {
                XCTFail("Expected CompilerDriverError, got \(error)")
                return
            }
            switch driverError {
            case .circularImport(let chain):
                XCTAssertEqual(chain, ["PackageA", "PackageB", "PackageA"])
            }
        }
    }

    private func compileProjectMain(at root: URL) throws -> Data {
        let output = try compileProject(at: root)
        return try XCTUnwrap(output.bytecode)
    }

    private func compileProject(at root: URL) throws -> CompilerOutput {
        let sourceURL = root.appendingPathComponent("Sources/main.kira")
        let source = SourceText(file: sourceURL.path, text: try String(contentsOf: sourceURL, encoding: .utf8))
        return try CompilerDriver().compile(source: source, target: .macOS(arch: .arm64))
    }

    private func makeProject(
        manifest: String,
        sources: [String: String],
        packages: [String: PackageContents]
    ) throws -> URL {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kirac-package-tests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)

        try manifest.write(to: root.appendingPathComponent("Kira.toml"), atomically: true, encoding: .utf8)

        for (relativePath, contents) in sources {
            let fileURL = root.appendingPathComponent(relativePath)
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        for (packageName, packageContents) in packages {
            let packageRoot = root
                .appendingPathComponent("KiraPackages", isDirectory: true)
                .appendingPathComponent(packageName, isDirectory: true)
            switch packageContents {
            case .copy(let files):
                for (relativePath, contents) in files {
                    let fileURL = packageRoot.appendingPathComponent(relativePath)
                    try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                    try contents.write(to: fileURL, atomically: true, encoding: .utf8)
                }
            case .existing(let sourceRoot):
                try fm.createDirectory(at: packageRoot.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                try fm.createSymbolicLink(at: packageRoot, withDestinationURL: sourceRoot)
            }
        }

        return root
    }

    private func existingPackageSource(named name: String) -> PackageContents {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("KiraPackages", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        return .existing(root)
    }
}

private enum PackageContents {
    case copy([String: String])
    case existing(URL)
}
