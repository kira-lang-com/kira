import XCTest
@testable import KiraCompiler

final class LexerTests: XCTestCase {
    func testFuncIsLexerError() {
        let src = SourceText(file: "test.kira", text: "func main() { return }")
        XCTAssertThrowsError(try Lexer().lex(src)) { err in
            guard case LexerError.illegalKeyword(let kw, _) = err else {
                XCTFail("expected illegalKeyword, got \(err)")
                return
            }
            XCTAssertEqual(kw, "func")
        }
    }

    func testMultiLineStringLiteral() throws {
        let source = SourceText(file: "test.kira", text: """
        let x = "hello
        world"
        """)

        let tokens = try Lexer().lex(source)
        let stringToken = tokens.first {
            if case .stringLiteral = $0.kind { return true }
            return false
        }

        guard case .stringLiteral(let value) = stringToken?.kind else {
            return XCTFail("expected string literal token")
        }
        XCTAssertEqual(value, "hello\nworld")
    }

    func testMultiLineDocAnnotation() throws {
        let source = SourceText(file: "test.kira", text: """
        @Doc("First line.
        Second line.
        Third line.")
        type Foo { }
        """)

        let tokens = try Lexer().lex(source)
        XCTAssertFalse(tokens.isEmpty)
    }

    func testUnterminatedStringError() {
        let source = SourceText(file: "test.kira", text: "let x = \"unterminated")
        XCTAssertThrowsError(try Lexer().lex(source))
    }
}
