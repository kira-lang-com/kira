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

    func testParsesFixedArrayAndTernary() throws {
        let text = """
        function main() {
            let verts: CArray<CFloat, 3> = [1.0, 2.0, 3.0,]
            let backend = true ? "d3d11" : "metal"
            let vsize = sizeOf(CArray<CFloat, 3>)
            return
        }
        """
        let src = SourceText(file: "test.kira", text: text)
        let toks = try Lexer().lex(src)
        var p = Parser(tokens: toks)
        let module = try p.parseModule()

        guard case .function(let fn) = try XCTUnwrap(module.declarations.first) else {
            return XCTFail("expected function declaration")
        }
        guard case .variable(let vertsDecl) = fn.body.statements[0] else {
            return XCTFail("expected fixed-array variable")
        }
        guard let explicitType = vertsDecl.explicitType else {
            return XCTFail("expected explicit array type")
        }
        guard case .fixedArray(_, let count) = explicitType.kind else {
            return XCTFail("expected fixed array type")
        }
        XCTAssertEqual(count, 3)

        guard case .variable(let backendDecl) = fn.body.statements[1] else {
            return XCTFail("expected ternary variable")
        }
        guard case .conditional = backendDecl.initializer else {
            return XCTFail("expected ternary expression")
        }

        guard case .variable(let sizeDecl) = fn.body.statements[2] else {
            return XCTFail("expected sizeOf variable")
        }
        guard case .sizeOf = sizeDecl.initializer else {
            return XCTFail("expected sizeOf expression")
        }
    }
}
