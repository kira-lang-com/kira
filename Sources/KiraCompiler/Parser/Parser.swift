import Foundation

public struct Parser {
    private var tokens: [Token]
    private var index: Int = 0
    private var disallowBareTrailingBlockCalls: Int = 0

    public init(tokens: [Token]) {
        self.tokens = tokens
    }

    public mutating func parseModule() throws -> ModuleAST {
        consumeSeparators()
        let start = current().range.start

        var imports: [ImportDecl] = []
        var decls: [Decl] = []

        while !at(.eof) {
            consumeSeparators()
            if at(.eof) { break }

            if matchKeyword(.import) {
                imports.append(try parseImport(startLoc: previous().range.start))
                continue
            }

            let annotations = try parseLeadingAnnotations()
            consumeSeparators()

            if matchKeyword(.construct) {
                decls.append(.construct(try parseConstructDecl(startLoc: previous().range.start)))
                continue
            }

            if matchKeyword(.typealias) {
                decls.append(.typealias(try parseTypealiasDecl(startLoc: previous().range.start)))
                continue
            }

            if matchKeyword(.type) {
                decls.append(.type(try parseTypeDecl(annotations: annotations, startLoc: previous().range.start)))
                continue
            }

            if matchKeyword(.protocol) {
                decls.append(.protocol(try parseProtocolDecl(annotations: annotations, startLoc: previous().range.start)))
                continue
            }

            if matchKeyword(.enum) {
                decls.append(.enum(try parseEnumDecl(annotations: annotations, startLoc: previous().range.start)))
                continue
            }

            if matchKeyword(.extern) {
                let startLoc = previous().range.start
                _ = try expectKeyword(.function)
                decls.append(.externFunction(try parseExternFunctionDecl(annotations: annotations, startLoc: startLoc)))
                continue
            }

            if matchKeyword(.let) || matchKeyword(.var) {
                let isVar = previous().kind == .keyword(.var)
                let startLoc = previous().range.start
                let (name, _) = try expectIdentifier("global variable name")
                var explicitType: TypeRef?
                if match(.colon) {
                    explicitType = try parseTypeRef()
                }
                _ = try expect(.equal, "=")
                let initExpr = try parseExpression()
                decls.append(.globalVar(.init(
                    isVar: isVar,
                    name: name,
                    explicitType: explicitType,
                    initializer: initExpr,
                    range: SourceRange(start: startLoc, end: initExpr.range.end)
                )))
                continue
            }

            let isAsync = matchKeyword(.async)
            if matchKeyword(.function) {
                decls.append(.function(try parseFunctionDecl(annotations: annotations, isAsync: isAsync, startLoc: previous().range.start)))
                continue
            }

            if case .identifier(let constructName) = current().kind,
               case .identifier = peek(1).kind {
                decls.append(.constructInstance(try parseConstructInstanceDecl(annotations: annotations, startLoc: current().range.start)))
                _ = constructName
                continue
            }

            throw ParseError.message("unexpected top-level token", current().range.start)
        }

        let end = current().range.end
        return ModuleAST(imports: imports, declarations: decls, range: SourceRange(start: start, end: end))
    }

    // MARK: - Imports

    private mutating func parseImport(startLoc: SourceLocation) throws -> ImportDecl {
        var parts: [String] = []
        parts.append(try expectIdentifier("module name").0)
        while match(.dot) {
            parts.append(try expectIdentifier("module name").0)
        }
        var alias: String?
        if matchKeyword(.as) {
            alias = try expectIdentifier("import alias").0
        }
        let end = previous().range.end
        consumeSeparators()
        return ImportDecl(modulePath: parts.joined(separator: "."), alias: alias, range: SourceRange(start: startLoc, end: end))
    }

    // MARK: - Typealias

    private mutating func parseTypealiasDecl(startLoc: SourceLocation) throws -> TypealiasDecl {
        let (name, _) = try expectIdentifier("typealias name")
        _ = try expect(.equal, "=")
        let target = try parseTypeRef()
        let end = target.range.end
        return TypealiasDecl(name: name, target: target, range: SourceRange(start: startLoc, end: end))
    }

    // MARK: - Annotations

    private mutating func parseLeadingAnnotations() throws -> [Annotation] {
        var result: [Annotation] = []
        while at(.atSign) {
            let start = current().range.start
            _ = advance()
            let (name, _) = try expectIdentifier("annotation name")
            var args: [Annotation.Argument] = []
            if match(.lParen) {
                if !at(.rParen) {
                    repeat {
                        consumeSeparators()
                        let argStart = current().range.start
                        let label: String?
                        if case .identifier(let labelName) = current().kind, peek(1).kind == .colon {
                            _ = advance()
                            _ = try expect(.colon, ":")
                            label = labelName
                        } else {
                            label = nil
                        }
                        let value = try parseExpression()
                        let argEnd = value.range.end
                        args.append(.init(label: label, value: value))
                        _ = argStart
                        _ = argEnd
                    } while match(.comma)
                }
                _ = try expect(.rParen, ")")
            } else if match(.lBrace) {
                // @Doc { "line1" "line2" }
                // Parsed as implicit string concatenation with newlines.
                var lines: [String] = []
                while !at(.rBrace) && !at(.eof) {
                    consumeSeparators()
                    if case .stringLiteral(let s) = current().kind {
                        _ = advance()
                        lines.append(s)
                        continue
                    }
                    if at(.rBrace) { break }
                    throw ParseError.message("expected string literal in annotation block", current().range.start)
                }
                _ = try expect(.rBrace, "}")
                let joined = lines.joined(separator: "\n")
                let expr = Expr.stringLiteral(joined, SourceRange(start: start, end: previous().range.end))
                args.append(.init(label: nil, value: expr))
            }
            let end = previous().range.end
            result.append(Annotation(name: name, arguments: args, range: SourceRange(start: start, end: end)))
            consumeSeparators()
        }
        return result
    }

    // MARK: - Declarations

    private mutating func parseFunctionDecl(annotations: [Annotation], isAsync: Bool, startLoc: SourceLocation) throws -> FunctionDecl {
        let (name, _) = try expectIdentifier("function name")
        let (params, _) = try parseParameterList()
        var returnType: TypeRef?
        if match(.arrow) {
            returnType = try parseTypeRef()
        }
        let body = try parseBlock()
        let end = body.range.end
        return FunctionDecl(annotations: annotations, isAsync: isAsync, name: name, parameters: params, returnType: returnType, body: body, range: SourceRange(start: startLoc, end: end))
    }

    private mutating func parseExternFunctionDecl(annotations: [Annotation], startLoc: SourceLocation) throws -> ExternFunctionDecl {
        let (name, _) = try expectIdentifier("function name")
        let (params, _) = try parseParameterList()
        var returnType: TypeRef?
        if match(.arrow) {
            returnType = try parseTypeRef()
        }
        let end = previous().range.end
        consumeSeparators()
        return ExternFunctionDecl(annotations: annotations, name: name, parameters: params, returnType: returnType, range: SourceRange(start: startLoc, end: end))
    }

    private mutating func parseTypeDecl(annotations: [Annotation], startLoc: SourceLocation) throws -> TypeDecl {
        let (name, _) = try expectIdentifier("type name")
        var conformances: [String] = []
        if match(.colon) {
            repeat {
                conformances.append(try expectIdentifier("protocol name").0)
            } while match(.comma)
        }
        _ = try expect(.lBrace, "{")
        consumeSeparators()
        var fields: [TypeDecl.Field] = []
        var methods: [FunctionDecl] = []
        var statics: [FunctionDecl] = []
        while !at(.rBrace) && !at(.eof) {
            let memberStart = current().range.start
            let memberAnnotations = try parseLeadingAnnotations()
            consumeSeparators()
            let isStatic = matchKeyword(.static)
            if matchKeyword(.function) || matchKeyword(.async) {
                let isAsync = previous().kind == .keyword(.async)
                if isAsync {
                    _ = try expectKeyword(.function)
                }
                let method = try parseFunctionDecl(annotations: memberAnnotations, isAsync: isAsync, startLoc: memberStart)
                if isStatic {
                    statics.append(method)
                } else {
                    methods.append(method)
                }
                consumeSeparators()
                continue
            }
            let isVar: Bool
            if matchKeyword(.var) {
                isVar = true
            } else if matchKeyword(.let) {
                isVar = false
            } else {
                throw ParseError.message("expected 'var', 'let', or 'function' in type body", current().range.start)
            }
            let (fieldName, _) = try expectIdentifier("field name")
            var typeRef: TypeRef?
            if match(.colon) {
                typeRef = try parseTypeRef()
            }
            var initializer: Expr?
            if match(.equal) {
                initializer = try parseExpression()
            }
            let end = previous().range.end
            fields.append(TypeDecl.Field(annotations: memberAnnotations, isStatic: isStatic, isVar: isVar, name: fieldName, type: typeRef, initializer: initializer, range: SourceRange(start: startLoc, end: end)))
            consumeSeparators()
        }
        _ = try expect(.rBrace, "}")
        let end = previous().range.end
        return TypeDecl(annotations: annotations, name: name, conformances: conformances, fields: fields, methods: methods, statics: statics, range: SourceRange(start: startLoc, end: end))
    }

    private mutating func parseProtocolDecl(annotations: [Annotation], startLoc: SourceLocation) throws -> ProtocolDecl {
        let (name, _) = try expectIdentifier("protocol name")
        _ = try expect(.lBrace, "{")
        consumeSeparators()
        var requirements: [ProtocolDecl.Requirement] = []
        while !at(.rBrace) && !at(.eof) {
            let reqAnnotations = try parseLeadingAnnotations()
            consumeSeparators()
            let isAsync = matchKeyword(.async)
            _ = isAsync
            _ = try expectKeyword(.function)
            let (reqName, _) = try expectIdentifier("requirement name")
            let (params, _) = try parseParameterList()
            var returnType: TypeRef?
            if match(.arrow) { returnType = try parseTypeRef() }
            let end = previous().range.end
            requirements.append(.init(annotations: reqAnnotations, name: reqName, parameters: params, returnType: returnType, range: SourceRange(start: startLoc, end: end)))
            consumeSeparators()
        }
        _ = try expect(.rBrace, "}")
        let end = previous().range.end
        return ProtocolDecl(annotations: annotations, name: name, requirements: requirements, range: SourceRange(start: startLoc, end: end))
    }

    private mutating func parseEnumDecl(annotations: [Annotation], startLoc: SourceLocation) throws -> EnumDecl {
        let (name, _) = try expectIdentifier("enum name")
        _ = try expect(.lBrace, "{")
        consumeSeparators()
        var cases: [EnumDecl.Case] = []
        while !at(.rBrace) && !at(.eof) {
            let caseAnnotations = try parseLeadingAnnotations()
            consumeSeparators()
            _ = matchKeyword(.case)
            let (caseName, _) = try expectIdentifier("case name")
            var associated: [EnumDecl.Case.AssociatedValue] = []
            if match(.lParen) {
                if !at(.rParen) {
                    repeat {
                        consumeSeparators()
                        let avStart = current().range.start
                        let label: String?
                        if case .identifier(let labelName) = current().kind, peek(1).kind == .colon {
                            _ = advance()
                            _ = try expect(.colon, ":")
                            label = labelName
                        } else {
                            label = nil
                        }
                        let ty = try parseTypeRef()
                        let avEnd = ty.range.end
                        associated.append(.init(label: label, type: ty, range: SourceRange(start: avStart, end: avEnd)))
                    } while match(.comma)
                }
                _ = try expect(.rParen, ")")
            }
            let end = previous().range.end
            cases.append(.init(annotations: caseAnnotations, name: caseName, associatedValues: associated, range: SourceRange(start: startLoc, end: end)))
            consumeSeparators()
        }
        _ = try expect(.rBrace, "}")
        let end = previous().range.end
        return EnumDecl(annotations: annotations, name: name, cases: cases, range: SourceRange(start: startLoc, end: end))
    }

    private mutating func parseConstructDecl(startLoc: SourceLocation) throws -> ConstructDecl {
        let (name, _) = try expectIdentifier("construct name")
        _ = try expect(.lBrace, "{")
        consumeSeparators()

        var allowedAnnotations: [String] = []
        var modifiers: [ConstructDecl.Modifier] = []
        var requiredBlocks: [String] = []

        while !at(.rBrace) && !at(.eof) {
            consumeSeparators()
            let (sectionName, _) = try expectIdentifier("construct section name")
            _ = try expect(.lBrace, "{")
            consumeSeparators()
            switch sectionName {
            case "annotations":
                while !at(.rBrace) {
                    consumeSeparators()
                    _ = try expect(.atSign, "@")
                    allowedAnnotations.append(try expectIdentifier("annotation").0)
                    consumeSeparators()
                }
            case "modifiers":
                while !at(.rBrace) {
                    consumeSeparators()
                    var isScoped = false
                    if at(.atSign) {
                        let anns = try parseLeadingAnnotations()
                        isScoped = anns.contains(where: { $0.name == "Scoped" })
                    }
                    let mStart = current().range.start
                    let (modName, _) = try expectIdentifier("modifier name")
                    var typeRef: TypeRef?
                    if match(.colon) {
                        typeRef = try parseTypeRef()
                    }
                    var defaultValue: Expr?
                    if match(.equal) {
                        defaultValue = try parseExpression()
                    }
                    let mEnd = previous().range.end
                    modifiers.append(.init(isScoped: isScoped, name: modName, type: typeRef, defaultValue: defaultValue, range: SourceRange(start: mStart, end: mEnd)))
                    consumeSeparators()
                }
            case "requires":
                while !at(.rBrace) {
                    consumeSeparators()
                    let (reqName, _) = try expectIdentifier("required block")
                    requiredBlocks.append(reqName)
                    // Optional type after colon is ignored by the construct pass; it remains for future expansion.
                    if match(.colon) { _ = try parseTypeRef() }
                    consumeSeparators()
                }
            default:
                // Parse-and-skip unknown sections.
                var depth = 1
                while depth > 0 && !at(.eof) {
                    if match(.lBrace) { depth += 1; continue }
                    if match(.rBrace) { depth -= 1; continue }
                    _ = advance()
                }
                continue
            }
            _ = try expect(.rBrace, "}")
            consumeSeparators()
        }

        _ = try expect(.rBrace, "}")
        let end = previous().range.end
        return ConstructDecl(name: name, allowedAnnotations: allowedAnnotations, modifiers: modifiers, requiredBlocks: requiredBlocks, range: SourceRange(start: startLoc, end: end))
    }

    private mutating func parseConstructInstanceDecl(annotations: [Annotation], startLoc: SourceLocation) throws -> ConstructInstanceDecl {
        let (constructName, _) = try expectIdentifier("construct name")
        let (name, _) = try expectIdentifier("declaration name")
        let (params, _) = try parseParameterList(optional: true)
        _ = try expect(.lBrace, "{")
        consumeSeparators()

        var members: [ConstructInstanceDecl.Member] = []
        while !at(.rBrace) && !at(.eof) {
            consumeSeparators()
            let memberStart = current().range.start
            let memberAnnotations = try parseLeadingAnnotations()
            consumeSeparators()

            if matchKeyword(.function) || matchKeyword(.async) {
                // If we consumed async, expect function next.
                let isAsync = previous().kind == .keyword(.async)
                if isAsync { _ = try expectKeyword(.function) }
                let fn = try parseFunctionDecl(annotations: memberAnnotations, isAsync: isAsync, startLoc: memberStart)
                members.append(.init(kind: .function(fn), range: fn.range))
                consumeSeparators()
                continue
            }

            if matchKeyword(.var) || matchKeyword(.let) {
                let isVar = previous().kind == .keyword(.var)
                let (fieldName, _) = try expectIdentifier("field name")
                var typeRef: TypeRef?
                if match(.colon) { typeRef = try parseTypeRef() }
                var initializer: Expr?
                if match(.equal) { initializer = try parseExpression() }
                let end = previous().range.end
                let field = TypeDecl.Field(annotations: memberAnnotations, isStatic: false, isVar: isVar, name: fieldName, type: typeRef, initializer: initializer, range: SourceRange(start: memberStart, end: end))
                members.append(.init(kind: .field(field), range: field.range))
                consumeSeparators()
                continue
            }

            if case .identifier(let blockName) = current().kind, peek(1).kind == .lBrace {
                _ = advance()
                let body = try parseBlock()
                let end = body.range.end
                members.append(.init(kind: .block(name: blockName, body: body), range: SourceRange(start: memberStart, end: end)))
                consumeSeparators()
                continue
            }

            throw ParseError.message("unexpected construct member", current().range.start)
        }

        _ = try expect(.rBrace, "}")
        let end = previous().range.end
        return ConstructInstanceDecl(annotations: annotations, constructName: constructName, name: name, parameters: params, members: members, range: SourceRange(start: startLoc, end: end))
    }

    private mutating func parseParameterList(optional: Bool = false) throws -> ([Parameter], SourceLocation) {
        if optional && !at(.lParen) { return ([], current().range.start) }
        _ = try expect(.lParen, "(")
        consumeSeparators()
        var params: [Parameter] = []
        if !at(.rParen) {
            repeat {
                consumeSeparators()
                let start = current().range.start
                let (name, _) = try expectIdentifier("parameter name")
                _ = try expect(.colon, ":")
                let type = try parseTypeRef()
                let end = type.range.end
                params.append(Parameter(name: name, type: type, range: SourceRange(start: start, end: end)))
            } while match(.comma)
        }
        _ = try expect(.rParen, ")")
        let endLoc = previous().range.end
        return (params, endLoc)
    }

    // MARK: - Statements / Blocks

    private mutating func parseBlock() throws -> BlockStmt {
        let start = previous().kind == .lBrace ? previous().range.start : current().range.start
        if previous().kind != .lBrace {
            _ = try expect(.lBrace, "{")
        }
        consumeSeparators()
        var stmts: [Stmt] = []
        while !at(.rBrace) && !at(.eof) {
            consumeSeparators()
            if at(.rBrace) { break }
            stmts.append(try parseStatement())
            consumeSeparators()
        }
        _ = try expect(.rBrace, "}")
        let end = previous().range.end
        return BlockStmt(statements: stmts, range: SourceRange(start: start, end: end))
    }

    private mutating func parseStatement() throws -> Stmt {
        if matchKeyword(.let) || matchKeyword(.var) {
            let isVar = previous().kind == .keyword(.var)
            let start = previous().range.start
            let (name, _) = try expectIdentifier("variable name")
            var explicitType: TypeRef?
            if match(.colon) {
                explicitType = try parseTypeRef()
            }
            _ = try expect(.equal, "=")
            let initExpr = try parseExpression()
            let end = initExpr.range.end
            return .variable(.init(isVar: isVar, name: name, explicitType: explicitType, initializer: initExpr, range: SourceRange(start: start, end: end)))
        }
        if matchKeyword(.return) {
            let start = previous().range.start
            if at(.newline) || at(.semicolon) || at(.rBrace) {
                let end = previous().range.end
                return .return(.init(value: nil, range: SourceRange(start: start, end: end)))
            }
            let value = try parseExpression()
            let end = value.range.end
            return .return(.init(value: value, range: SourceRange(start: start, end: end)))
        }
        if matchKeyword(.if) {
            let start = previous().range.start
            disallowBareTrailingBlockCalls += 1
            defer { disallowBareTrailingBlockCalls -= 1 }
            let cond = try parseExpression()
            let thenBlock = try parseBlock()
            var elseBlock: BlockStmt?
            if matchKeyword(.else) {
                elseBlock = try parseBlock()
            }
            let end = (elseBlock ?? thenBlock).range.end
            return .if(.init(condition: cond, thenBlock: thenBlock, elseBlock: elseBlock, range: SourceRange(start: start, end: end)))
        }
        if matchKeyword(.while) {
            let start = previous().range.start
            disallowBareTrailingBlockCalls += 1
            defer { disallowBareTrailingBlockCalls -= 1 }
            let condition = try parseExpression()
            let body = try parseBlock()
            return .while(.init(condition: condition, body: body, range: SourceRange(start: start, end: body.range.end)))
        }
        if matchKeyword(.match) {
            let start = previous().range.start
            disallowBareTrailingBlockCalls += 1
            defer { disallowBareTrailingBlockCalls -= 1 }
            let value = try parseExpression()
            _ = try expect(.lBrace, "{")
            consumeSeparators()
            var cases: [MatchStmt.Case] = []
            while !at(.rBrace) && !at(.eof) {
                consumeSeparators()
                if at(.rBrace) { break }
                let patternStart = current().range.start
                let (variantName, _) = try expectIdentifier("enum variant name")
                var bindings: [String] = []
                if match(.lParen) {
                    consumeSeparators()
                    if !at(.rParen) {
                        repeat {
                            consumeSeparators()
                            _ = matchKeyword(.let)
                            let (binding, _) = try expectIdentifier("pattern binding")
                            bindings.append(binding)
                            consumeSeparators()
                        } while match(.comma)
                    }
                    _ = try expect(.rParen, ")")
                }
                let patternEnd = previous().range.end
                _ = try expect(.colon, ":")
                consumeSeparators()
                let body: BlockStmt
                if at(.lBrace) {
                    body = try parseBlock()
                } else {
                    let statement = try parseStatement()
                    body = BlockStmt(statements: [statement], range: statement.range)
                }
                let pattern = MatchStmt.Pattern(
                    variantName: variantName,
                    bindings: bindings,
                    range: SourceRange(start: patternStart, end: patternEnd)
                )
                cases.append(.init(pattern: pattern, body: body, range: SourceRange(start: patternStart, end: body.range.end)))
                consumeSeparators()
            }
            _ = try expect(.rBrace, "}")
            return .match(.init(value: value, cases: cases, range: SourceRange(start: start, end: previous().range.end)))
        }
        let expr = try parseExpression()
        return .expr(expr)
    }

    // MARK: - Expressions

    private mutating func parseExpression() throws -> Expr {
        try parseAssignment()
    }

    private mutating func parseAssignment() throws -> Expr {
        var expr = try parseConditional()
        if match(.equal) {
            let value = try parseAssignment()
            let range = SourceRange(start: expr.range.start, end: value.range.end)
            expr = .assign(.init(target: expr, value: value, range: range))
        }
        return expr
    }

    private mutating func parseConditional() throws -> Expr {
        var expr = try parseLogicalOr()
        if match(.question) {
            let thenExpr = try parseExpression()
            _ = try expect(.colon, ":")
            let elseExpr = try parseConditional()
            expr = .conditional(.init(
                condition: expr,
                thenExpr: thenExpr,
                elseExpr: elseExpr,
                range: SourceRange(start: expr.range.start, end: elseExpr.range.end)
            ))
        }
        return expr
    }

    private mutating func parseLogicalOr() throws -> Expr {
        var expr = try parseLogicalAnd()
        while match(.pipePipe) {
            let rhs = try parseLogicalAnd()
            expr = .binary(.init(op: .or, lhs: expr, rhs: rhs, range: SourceRange(start: expr.range.start, end: rhs.range.end)))
        }
        return expr
    }

    private mutating func parseLogicalAnd() throws -> Expr {
        var expr = try parseEquality()
        while match(.ampAmp) {
            let rhs = try parseEquality()
            expr = .binary(.init(op: .and, lhs: expr, rhs: rhs, range: SourceRange(start: expr.range.start, end: rhs.range.end)))
        }
        return expr
    }

    private mutating func parseEquality() throws -> Expr {
        var expr = try parseComparison()
        while true {
            if match(.equalEqual) {
                let rhs = try parseComparison()
                expr = .binary(.init(op: .eq, lhs: expr, rhs: rhs, range: SourceRange(start: expr.range.start, end: rhs.range.end)))
                continue
            }
            if match(.bangEqual) {
                let rhs = try parseComparison()
                expr = .binary(.init(op: .neq, lhs: expr, rhs: rhs, range: SourceRange(start: expr.range.start, end: rhs.range.end)))
                continue
            }
            break
        }
        return expr
    }

    private mutating func parseComparison() throws -> Expr {
        var expr = try parseTerm()
        while true {
            let op: BinaryOp?
            if match(.lt) { op = .lt }
            else if match(.gt) { op = .gt }
            else if match(.ltEqual) { op = .lte }
            else if match(.gtEqual) { op = .gte }
            else { op = nil }
            guard let op else { break }
            let rhs = try parseTerm()
            expr = .binary(.init(op: op, lhs: expr, rhs: rhs, range: SourceRange(start: expr.range.start, end: rhs.range.end)))
        }
        return expr
    }

    private mutating func parseTerm() throws -> Expr {
        var expr = try parseFactor()
        while true {
            if match(.plus) {
                let rhs = try parseFactor()
                expr = .binary(.init(op: .add, lhs: expr, rhs: rhs, range: SourceRange(start: expr.range.start, end: rhs.range.end)))
                continue
            }
            if match(.minus) {
                let rhs = try parseFactor()
                expr = .binary(.init(op: .sub, lhs: expr, rhs: rhs, range: SourceRange(start: expr.range.start, end: rhs.range.end)))
                continue
            }
            break
        }
        return expr
    }

    private mutating func parseFactor() throws -> Expr {
        var expr = try parseUnary()
        while true {
            if match(.star) {
                let rhs = try parseUnary()
                expr = .binary(.init(op: .mul, lhs: expr, rhs: rhs, range: SourceRange(start: expr.range.start, end: rhs.range.end)))
                continue
            }
            if match(.slash) {
                let rhs = try parseUnary()
                expr = .binary(.init(op: .div, lhs: expr, rhs: rhs, range: SourceRange(start: expr.range.start, end: rhs.range.end)))
                continue
            }
            if match(.percent) {
                let rhs = try parseUnary()
                expr = .binary(.init(op: .mod, lhs: expr, rhs: rhs, range: SourceRange(start: expr.range.start, end: rhs.range.end)))
                continue
            }
            break
        }
        return expr
    }

    private mutating func parseUnary() throws -> Expr {
        if match(.minus) {
            let inner = try parseUnary()
            return .unary(.init(op: .negate, expr: inner, range: SourceRange(start: previous().range.start, end: inner.range.end)))
        }
        if match(.bang) {
            let inner = try parseUnary()
            return .unary(.init(op: .not, expr: inner, range: SourceRange(start: previous().range.start, end: inner.range.end)))
        }
        return try parsePostfix()
    }

    private mutating func parsePostfix() throws -> Expr {
        var expr = try parsePrimary()
        while true {
            if match(.dot) {
                let (name, _) = try expectIdentifier("member name")
                expr = .member(.init(base: expr, name: name, range: SourceRange(start: expr.range.start, end: previous().range.end)))
                continue
            }
            if match(.lBracket) {
                let index = try parseExpression()
                let end = try expect(.rBracket, "]").range.end
                expr = .index(.init(base: expr, index: index, range: SourceRange(start: expr.range.start, end: end)))
                continue
            }
            if match(.lParen) {
                var args: [CallArgument] = []
                consumeSeparators()
                if !at(.rParen) {
                    repeat {
                        consumeSeparators()
                        let argStart = current().range.start
                        let label: String?
                        if case .identifier(let labelName) = current().kind, peek(1).kind == .colon {
                            _ = advance()
                            _ = try expect(.colon, ":")
                            label = labelName
                        } else { label = nil }
                        let value = try parseExpression()
                        let argEnd = value.range.end
                        args.append(.init(label: label, value: value, range: SourceRange(start: argStart, end: argEnd)))
                    } while match(.comma)
                }
                _ = try expect(.rParen, ")")
                var trailing: BlockStmt?
                if at(.lBrace) {
                    trailing = try parseBlock()
                }
                let end = (trailing?.range.end) ?? previous().range.end
                expr = .call(.init(callee: expr, arguments: args, trailingBlock: trailing, range: SourceRange(start: expr.range.start, end: end)))
                continue
            }
            if at(.lBrace), disallowBareTrailingBlockCalls == 0 {
                let trailing = try parseBlock()
                expr = .call(.init(callee: expr, arguments: [], trailingBlock: trailing, range: SourceRange(start: expr.range.start, end: trailing.range.end)))
                continue
            }
            break
        }
        return expr
    }

    private mutating func parsePrimary() throws -> Expr {
        let tok = current()
        switch tok.kind {
        case .dot:
            let start = tok.range.start
            _ = advance()
            let (name, _) = try expectIdentifier("member name")
            let end = previous().range.end
            return .leadingMember(name, SourceRange(start: start, end: end))
        case .identifier(let name):
            _ = advance()
            if name == "true" { return .boolLiteral(true, tok.range) }
            if name == "false" { return .boolLiteral(false, tok.range) }
            if name == "nil" { return .nilLiteral(tok.range) }
            if name == "sizeOf", match(.lParen) {
                let targetType = try parseTypeRef()
                let end = try expect(.rParen, ")").range.end
                return .sizeOf(.init(type: targetType, range: SourceRange(start: tok.range.start, end: end)))
            }
            return .identifier(name, tok.range)
        case .intLiteral(let v):
            _ = advance()
            return .intLiteral(v, tok.range)
        case .floatLiteral(let v):
            _ = advance()
            return .floatLiteral(v, tok.range)
        case .stringLiteral(let v):
            _ = advance()
            return .stringLiteral(v, tok.range)
        case .keyword:
            if matchKeyword(.await) {
                // await expr  (parsed but handled as normal call for now)
                let inner = try parsePrimary()
                return inner
            }
            if matchKeyword(.async) {
                let inner = try parsePrimary()
                return inner
            }
            if matchKeyword(.return) {
                throw ParseError.message("'return' is a statement", tok.range.start)
            }
            throw ParseError.message("unexpected keyword in expression", tok.range.start)
        case .lParen:
            _ = advance()
            let expr = try parseExpression()
            _ = try expect(.rParen, ")")
            return expr
        case .lBracket:
            let start = tok.range.start
            _ = advance()
            var elements: [Expr] = []
            consumeSeparators()
            while !at(.rBracket) {
                consumeSeparators()
                elements.append(try parseExpression())
                consumeSeparators()
                if !match(.comma) {
                    break
                }
                consumeSeparators()
                if at(.rBracket) {
                    break
                }
            }
            let end = try expect(.rBracket, "]").range.end
            return .arrayLiteral(.init(elements: elements, range: SourceRange(start: start, end: end)))
        case .hash:
            _ = advance()
            let start = tok.range.start
            let (macroName, _) = try expectIdentifier("macro name")
            guard macroName == "shader" else {
                throw ParseError.message("unknown macro #\(macroName)", tok.range.start)
            }
            _ = try expect(.lParen, "(")
            let (fnName, _) = try expectIdentifier("function name")
            _ = try expect(.rParen, ")")
            let end = previous().range.end
            return .shaderMacro(.init(functionName: fnName, range: SourceRange(start: start, end: end)))
        default:
            throw ParseError.unexpectedToken(expected: "expression", got: tok.kind, at: tok.range.start)
        }
    }

    // MARK: - Types

    private mutating func parseTypeRef() throws -> TypeRef {
        let start = current().range.start

        if match(.lParen) {
            var params: [TypeRef] = []
            if !at(.rParen) {
                repeat {
                    params.append(try parseTypeRef())
                } while match(.comma)
            }
            _ = try expect(.rParen, ")")
            _ = try expect(.arrow, "->")
            let ret = try parseTypeRef()
            let end = ret.range.end
            var ty = TypeRef(kind: .function(params: params, returns: ret), range: SourceRange(start: start, end: end))
            if match(.question) {
                ty = TypeRef(kind: .optional(ty), range: SourceRange(start: start, end: previous().range.end))
            }
            return ty
        }

        if match(.lBracket) {
            let innerStart = current().range.start
            let keyType = try parseTypeRef()
            if match(.colon) {
                let valueType = try parseTypeRef()
                _ = try expect(.rBracket, "]")
                let end = previous().range.end
                var ty = TypeRef(kind: .dictionary(key: keyType, value: valueType), range: SourceRange(start: start, end: end))
                if match(.question) {
                    ty = TypeRef(kind: .optional(ty), range: SourceRange(start: start, end: previous().range.end))
                }
                _ = innerStart
                return ty
            } else {
                _ = try expect(.rBracket, "]")
                let end = previous().range.end
                var ty = TypeRef(kind: .array(keyType), range: SourceRange(start: start, end: end))
                if match(.question) {
                    ty = TypeRef(kind: .optional(ty), range: SourceRange(start: start, end: previous().range.end))
                }
                return ty
            }
        }

        let (name, nameRange) = try expectIdentifier("type name")
        var base = TypeRef(kind: .named(name), range: nameRange)
        if match(.lt) {
            if name == "CArray" {
                let elementType = try parseTypeRef()
                _ = try expect(.comma, ",")
                let count: Int
                switch current().kind {
                case .intLiteral(let value):
                    guard value >= 0 else {
                        throw ParseError.message("CArray element count must be non-negative", current().range.start)
                    }
                    guard let parsed = Int(exactly: value) else {
                        throw ParseError.message("CArray element count is too large", current().range.start)
                    }
                    count = parsed
                    _ = advance()
                default:
                    throw ParseError.unexpectedToken(expected: "array length", got: current().kind, at: current().range.start)
                }
                let end = try expect(.gt, ">").range.end
                base = TypeRef(kind: .fixedArray(element: elementType, count: count), range: SourceRange(start: start, end: end))
            } else {
                var args: [TypeRef] = []
                if !at(.gt) {
                    repeat {
                        args.append(try parseTypeRef())
                    } while match(.comma)
                }
                _ = try expect(.gt, ">")
                let end = previous().range.end
                base = TypeRef(kind: .applied(name, args), range: SourceRange(start: start, end: end))
            }
        }
        var ty = base
        if match(.question) {
            ty = TypeRef(kind: .optional(ty), range: SourceRange(start: start, end: previous().range.end))
        }
        return ty
    }

    // MARK: - Helpers

    private func current() -> Token { tokens[index] }
    private func peek(_ n: Int) -> Token { tokens[min(index + n, tokens.count - 1)] }

    private mutating func advance() -> Token {
        let t = tokens[index]
        index = min(index + 1, tokens.count - 1)
        return t
    }

    private func at(_ kind: TokenKind) -> Bool { current().kind == kind }

    private mutating func match(_ kind: TokenKind) -> Bool {
        if at(kind) {
            _ = advance()
            return true
        }
        return false
    }

    private mutating func matchKeyword(_ kw: Keyword) -> Bool {
        if current().kind == .keyword(kw) {
            _ = advance()
            return true
        }
        return false
    }

    private mutating func expect(_ kind: TokenKind, _ expected: String) throws -> Token {
        if at(kind) { return advance() }
        throw ParseError.unexpectedToken(expected: expected, got: current().kind, at: current().range.start)
    }

    private mutating func expectKeyword(_ kw: Keyword) throws -> Token {
        if current().kind == .keyword(kw) { return advance() }
        throw ParseError.unexpectedToken(expected: kw.rawValue, got: current().kind, at: current().range.start)
    }

    private mutating func expectIdentifier(_ expected: String) throws -> (String, SourceRange) {
        if case .identifier(let s) = current().kind {
            let r = current().range
            _ = advance()
            return (s, r)
        }
        throw ParseError.unexpectedToken(expected: expected, got: current().kind, at: current().range.start)
    }

    private mutating func consumeSeparators() {
        while at(.newline) || at(.semicolon) {
            _ = advance()
        }
    }

    private func previous() -> Token {
        tokens[max(0, index - 1)]
    }
}
