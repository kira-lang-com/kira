import XCTest
@testable import KiraCompiler

final class ParserTests: XCTestCase {
    func testParsesFunction() throws {
        let src = SourceText(file: "test.kira", text: "function add(a: Int, b: Int) -> Int { return a + b }")
        let toks = try Lexer().lex(src)
        var p = Parser(tokens: toks)
        let m = try p.parseModule()
        XCTAssertEqual(m.declarations.count, 1)
    }

    func testParsesConstructAndInstance() throws {
        let text = """
        construct Widget {
            annotations { @State @Scoped }
            modifiers { @Scoped cornerRadius = 0.0 }
            requires { content: Block }
        }

        Widget Button(label: String) {
            @State var count: Int = 0
            content { return }
        }
        """
        let src = SourceText(file: "test.kira", text: text)
        let toks = try Lexer().lex(src)
        var p = Parser(tokens: toks)
        let m = try p.parseModule()
        XCTAssertEqual(m.declarations.count, 2)
    }
}

