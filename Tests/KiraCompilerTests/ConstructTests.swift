import XCTest
@testable import KiraCompiler

final class ConstructTests: XCTestCase {
    func testMissingRequiredBlockErrors() throws {
        let text = """
        construct Widget {
            annotations { @State }
            requires { content: Block }
        }
        Widget Button(label: String) { @State var x: Int = 0 }
        """
        let src = SourceText(file: "t.kira", text: text)
        XCTAssertThrowsError(try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64))) { err in
            XCTAssertTrue(String(describing: err).contains("requires a content {} block"))
        }
    }

    func testInvalidAnnotationErrors() throws {
        let text = """
        construct Widget { annotations { @State } requires { content: Block } }
        Widget Button(label: String) { @Binding var x: Int = 0 content { return } }
        """
        let src = SourceText(file: "t.kira", text: text)
        XCTAssertThrowsError(try CompilerDriver().compile(source: src, target: .macOS(arch: .arm64)))
    }
}

