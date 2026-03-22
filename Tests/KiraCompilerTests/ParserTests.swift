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

    func testParsesTypeMethod() throws {
        let text = """
        @CStruct
        type Counter {
            var value: Int

            function add(delta: Int) -> Int {
                return self.value + delta
            }
        }
        """
        let src = SourceText(file: "test.kira", text: text)
        let toks = try Lexer().lex(src)
        var p = Parser(tokens: toks)
        let module = try p.parseModule()

        guard case .type(let td) = try XCTUnwrap(module.declarations.first) else {
            return XCTFail("expected type declaration")
        }
        XCTAssertEqual(td.fields.count, 1)
        XCTAssertEqual(td.methods.count, 1)
        XCTAssertEqual(td.statics.count, 0)
        XCTAssertEqual(td.methods[0].name, "add")
    }

    func testParsesStaticTypeMethod() throws {
        let text = """
        type Rectangle {
            static function unit() -> Rectangle {
                return Rectangle()
            }
        }
        """
        let src = SourceText(file: "test.kira", text: text)
        let toks = try Lexer().lex(src)
        var p = Parser(tokens: toks)
        let module = try p.parseModule()

        guard case .type(let td) = try XCTUnwrap(module.declarations.first) else {
            return XCTFail("expected type declaration")
        }
        XCTAssertEqual(td.methods.count, 0)
        XCTAssertEqual(td.statics.count, 1)
        XCTAssertEqual(td.statics[0].name, "unit")
    }

    func testParsesCallWithTrailingBlockWithoutParens() throws {
        let text = """
        function main() {
            makeThing {
                value = 1
            }
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
        guard case .expr(let expr) = fn.body.statements[0] else {
            return XCTFail("expected expression statement")
        }
        guard case .call(let call) = expr else {
            return XCTFail("expected call expression")
        }
        XCTAssertEqual(call.arguments.count, 0)
        XCTAssertNotNil(call.trailingBlock)
    }

    func testParsesEnumDeclaration() throws {
        let text = """
        enum PixelFormat {
            case rgba8Unorm
            case bgra8Unorm
        }
        """
        let src = SourceText(file: "test.kira", text: text)
        let toks = try Lexer().lex(src)
        var p = Parser(tokens: toks)
        let module = try p.parseModule()

        guard case .enum(let enumDecl) = try XCTUnwrap(module.declarations.first) else {
            return XCTFail("expected enum declaration")
        }
        XCTAssertEqual(enumDecl.name, "PixelFormat")
        XCTAssertEqual(enumDecl.cases.map(\.name), ["rgba8Unorm", "bgra8Unorm"])
    }

    func testParsesLeadingDotMemberExpression() throws {
        let text = """
        function main() {
            let format: PixelFormat = .bgra8Unorm
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
        guard case .variable(let decl) = fn.body.statements[0] else {
            return XCTFail("expected variable declaration")
        }
        guard case .leadingMember(let name, _) = decl.initializer else {
            return XCTFail("expected leading dot member expression")
        }
        XCTAssertEqual(name, "bgra8Unorm")
    }

    func testParsesTypeProtocolConformance() throws {
        let text = """
        protocol Scene {
            function tick() -> Int
        }

        type CounterScene: Scene {
            function tick() -> Int {
                return 7
            }
        }
        """
        let src = SourceText(file: "test.kira", text: text)
        let toks = try Lexer().lex(src)
        var p = Parser(tokens: toks)
        let module = try p.parseModule()

        guard case .type(let typeDecl) = module.declarations[1] else {
            return XCTFail("expected type declaration")
        }
        XCTAssertEqual(typeDecl.conformances, ["Scene"])
    }

    func testParsesStaticTypeField() throws {
        let text = """
        type Color {
            static let black: Color = Color()
        }
        """
        let src = SourceText(file: "test.kira", text: text)
        let toks = try Lexer().lex(src)
        var p = Parser(tokens: toks)
        let module = try p.parseModule()

        guard case .type(let typeDecl) = try XCTUnwrap(module.declarations.first) else {
            return XCTFail("expected type declaration")
        }
        XCTAssertEqual(typeDecl.fields.count, 1)
        XCTAssertTrue(typeDecl.fields[0].isStatic)
    }

    func testParsesIfStatementWithoutEatingThenBlockAsTrailingCall() throws {
        let text = """
        function main() {
            let shouldQuit = true
            if shouldQuit {
                print(1)
            }
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
        guard case .if = fn.body.statements[1] else {
            return XCTFail("expected if statement")
        }
    }

    func testParsesWhileStatement() throws {
        let text = """
        function main() {
            var value = 0
            while value < 3 {
                value = value + 1
            }
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
        guard case .while = fn.body.statements[1] else {
            return XCTFail("expected while statement")
        }
    }

    func testParsesArrayIndexExpression() throws {
        let text = """
        function main() {
            let values: [Int] = [1, 2, 3]
            let first = values[0]
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
        guard case .variable(let decl) = fn.body.statements[1] else {
            return XCTFail("expected variable declaration")
        }
        guard case .index(let indexExpr) = decl.initializer else {
            return XCTFail("expected index expression")
        }
        guard case .identifier(let name, _) = indexExpr.base else {
            return XCTFail("expected identifier base")
        }
        guard case .intLiteral(let value, _) = indexExpr.index else {
            return XCTFail("expected int literal index")
        }
        XCTAssertEqual(name, "values")
        XCTAssertEqual(value, 0)
    }
}
