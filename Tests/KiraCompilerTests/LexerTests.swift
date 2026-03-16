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
}

