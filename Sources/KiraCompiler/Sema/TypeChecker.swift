import Foundation

public struct TypeInfo: Sendable {
    public var exprTypes: [SourceRange: KiraType]
    public var varTypes: [SourceRange: KiraType]

    public init(exprTypes: [SourceRange: KiraType] = [:], varTypes: [SourceRange: KiraType] = [:]) {
        self.exprTypes = exprTypes
        self.varTypes = varTypes
    }
}

public struct TypedModule: Sendable {
    public var ast: ModuleAST
    public var symbols: SymbolTable
    public var typeInfo: TypeInfo

    public init(ast: ModuleAST, symbols: SymbolTable, typeInfo: TypeInfo) {
        self.ast = ast
        self.symbols = symbols
        self.typeInfo = typeInfo
    }
}

public struct TypeChecker: Sendable {
    public var typeSystem = TypeSystem()

    public init() {}

    public func typeCheck(module: ModuleAST, registry: ConstructRegistry, target: PlatformTarget) throws -> TypedModule {
        var symbols = SymbolTable()
        var typeInfo = TypeInfo()
        let cHandleTypes = collectCHandleTypes(module: module)

        // Register types and constructs first.
        for decl in module.declarations {
            switch decl {
            case .type(let td):
                symbols.addType(td.name)
            case .enum(let ed):
                symbols.addType(ed.name)
            case .protocol(let pd):
                symbols.addType(pd.name)
            case .constructInstance(let ci):
                symbols.addType(ci.name)
            default:
                break
            }
        }

        // Register functions.
        for decl in module.declarations {
            if case .function(let fn) = decl {
                let params = fn.parameters.map { typeSystem.resolve($0.type) }
                let ret = fn.returnType.map(typeSystem.resolve) ?? .void
                let mode: FunctionSymbol.ExecutionMode = executionMode(from: fn.annotations)
                if target.isWasm, mode == .runtime {
                    throw SemanticError.runtimeNotSupportedOnWasm(fn.range.start)
                }
                try symbols.addFunction(.init(
                    name: fn.name,
                    type: .function(params: params, returns: ret),
                    executionMode: mode,
                    isExtern: false,
                    range: fn.range
                ))
            } else if case .externFunction(let fn) = decl {
                let params = fn.parameters.map { typeSystem.resolve($0.type) }
                let ret = fn.returnType.map(typeSystem.resolve) ?? .void

                let proto = try parseFFIPrototype(for: fn, cHandleTypes: cHandleTypes)
                symbols.addFFIPrototype(functionName: fn.name, proto: proto)

                try symbols.addFunction(.init(
                    name: fn.name,
                    type: .function(params: params, returns: ret),
                    executionMode: .auto,
                    isExtern: true,
                    range: fn.range
                ))
            }
        }

        // Add construct-derived methods (modifier chain).
        for decl in module.declarations {
            guard case .constructInstance(let ci) = decl else { continue }
            guard let def = registry.lookup(ci.constructName) else { continue }
            let gen = ModifierChainGen()
            for sig in gen.generate(for: def) {
                let paramType: KiraType
                if let tyRef = sig.parameterType {
                    paramType = typeSystem.resolve(tyRef)
                } else {
                    // Infer from modifier default value when absent.
                    if let dv = def.modifiers.first(where: { $0.name == sig.name })?.defaultValue {
                        paramType = inferLiteralType(expr: dv) ?? .bool
                    } else {
                        paramType = .bool
                    }
                }
                symbols.addMethod(typeName: ci.name, methodName: sig.name, methodType: .function(params: [paramType], returns: .named(ci.name)))
            }
        }

        // Type-check bodies.
        for decl in module.declarations {
            if case .function(let fn) = decl {
                let fnType = symbols.functions[fn.name]!.type
                let expectedReturn: KiraType
                if case .function(_, let r) = fnType { expectedReturn = r } else { expectedReturn = .void }
                let scope = LocalScope(parent: nil, symbols: symbols)
                for p in fn.parameters {
                    scope.define(p.name, type: typeSystem.resolve(p.type))
                }
                _ = try typeCheckBlock(fn.body, scope: scope, symbols: symbols, expectedReturn: expectedReturn, typeInfo: &typeInfo)
            }
        }

        return TypedModule(ast: module, symbols: symbols, typeInfo: typeInfo)
    }

    private func executionMode(from annotations: [Annotation]) -> FunctionSymbol.ExecutionMode {
        if annotations.contains(where: { $0.name == "Native" }) { return .native }
        if annotations.contains(where: { $0.name == "Runtime" }) { return .runtime }
        return .auto
    }

    private func parseFFIPrototype(for fn: ExternFunctionDecl, cHandleTypes: Set<String>) throws -> FFIPrototype {
        guard let ffiAnn = fn.annotations.first(where: { $0.name == "ffi" }) else {
            return FFIPrototype(
                library: nil,
                symbol: fn.name,
                linkage: .dynamic,
                returnType: mapFFIType(fn.returnType, cHandleTypes: cHandleTypes),
                argumentTypes: fn.parameters.map { mapFFIType($0.type, cHandleTypes: cHandleTypes) }
            )
        }

        var lib: String?
        var linkage: FFILinkage = .dynamic
        for a in ffiAnn.arguments {
            guard let label = a.label else { continue }
            switch label {
            case "lib":
                if case .stringLiteral(let s, _) = a.value {
                    lib = s.isEmpty ? nil : s
                }
            case "linkage":
                if case .identifier(let s, _) = a.value {
                    if s == "static" { linkage = .static }
                    else if s == "dynamic" { linkage = .dynamic }
                }
            default:
                break
            }
        }

        return FFIPrototype(
            library: lib,
            symbol: fn.name,
            linkage: linkage,
            returnType: mapFFIType(fn.returnType, cHandleTypes: cHandleTypes),
            argumentTypes: fn.parameters.map { mapFFIType($0.type, cHandleTypes: cHandleTypes) }
        )
    }

    private func mapFFIType(_ ref: TypeRef?, cHandleTypes: Set<String>) -> FFIPrototype.TypeTag {
        guard let ref else { return .void }
        return mapFFIType(ref, cHandleTypes: cHandleTypes)
    }

    private func mapFFIType(_ ref: TypeRef, cHandleTypes: Set<String>) -> FFIPrototype.TypeTag {
        switch ref.kind {
        case .named(let n):
            if cHandleTypes.contains(n) { return .uint32 }
            switch n {
            case "Void", "CVoid": return .void
            case "Bool", "CBool": return .uint8
            case "Int": return .int64
            case "CInt8": return .int8
            case "CInt16": return .int16
            case "CInt32": return .int32
            case "CInt64": return .int64
            case "CUInt8": return .uint8
            case "CUInt16": return .uint16
            case "CUInt32": return .uint32
            case "CUInt64": return .uint64
            case "CFloat": return .float32
            case "Float": return .float64
            case "CDouble", "Double": return .float64
            default: return .pointer
            }
        case .applied(let base, let args):
            if base == "CPointer", let first = args.first {
                if case .named(let n) = first.kind, n == "CInt8" { return .cstring }
                return .pointer
            }
            return .pointer
        case .optional(let inner):
            return mapFFIType(inner, cHandleTypes: cHandleTypes)
        default:
            return .pointer
        }
    }

    private func collectCHandleTypes(module: ModuleAST) -> Set<String> {
        var result: Set<String> = []
        for decl in module.declarations {
            guard case .type(let td) = decl else { continue }
            guard td.annotations.contains(where: { $0.name == "CStruct" }) else { continue }
            guard td.fields.count == 1 else { continue }
            let f = td.fields[0]
            guard f.name == "id" else { continue }
            guard let ty = f.type else { continue }
            if case .named(let n) = ty.kind, n == "CUInt32" {
                result.insert(td.name)
            }
        }
        return result
    }

    private func isFFIConvertible(got: KiraType, expected: KiraType) -> Bool {
        // String -> CPointer<CInt8>
        if expected == .pointer(.named("CInt8")), got == .string { return true }

        // Int -> C integer types
        if got == .int {
            switch expected {
            case .named("CInt8"), .named("CInt16"), .named("CInt32"), .named("CInt64"),
                 .named("CUInt8"), .named("CUInt16"), .named("CUInt32"), .named("CUInt64"):
                return true
            default:
                break
            }
        }

        // Bool -> CBool
        if got == .bool, expected == .named("CBool") { return true }

        // Float/Double -> C float types
        if got == .float, expected == .named("CFloat") { return true }
        if got == .double, expected == .named("CDouble") { return true }

        // nil -> pointer
        if case .optional = got, case .pointer = expected { return true }

        return false
    }

    private func typeCheckBlock(_ block: BlockStmt, scope: LocalScope, symbols: SymbolTable, expectedReturn: KiraType, typeInfo: inout TypeInfo) throws -> KiraType {
        var lastType: KiraType = .void
        for stmt in block.statements {
            lastType = try typeCheckStmt(stmt, scope: scope, symbols: symbols, expectedReturn: expectedReturn, typeInfo: &typeInfo)
        }
        return lastType
    }

    private func typeCheckStmt(_ stmt: Stmt, scope: LocalScope, symbols: SymbolTable, expectedReturn: KiraType, typeInfo: inout TypeInfo) throws -> KiraType {
        switch stmt {
        case .variable(let vd):
            // Initializer is checked without expected-type coercion; explicit type is handled here.
            let initType = try typeCheckExpr(vd.initializer, scope: scope, symbols: symbols, expected: nil, typeInfo: &typeInfo)
            let finalType: KiraType
            if let explicit = vd.explicitType.map(typeSystem.resolve) {
                // Coercion only when explicit target type declared, and only from int literal to float.
                if explicit == .float, case .int = initType, isIntLiteral(vd.initializer) {
                    finalType = .float
                } else if explicit == initType {
                    finalType = explicit
                } else {
                    throw SemanticError.typeMismatch(expected: explicit, got: initType, vd.range.start, hint: coercionHint(expected: explicit, expr: vd.initializer))
                }
            } else {
                finalType = initType
            }
            scope.define(vd.name, type: finalType)
            typeInfo.varTypes[vd.range] = finalType
            return .void
        case .return(let rs):
            if let value = rs.value {
                let got = try typeCheckExpr(value, scope: scope, symbols: symbols, expected: expectedReturn, typeInfo: &typeInfo)
                if expectedReturn == .float, got == .int, isIntLiteral(value) {
                    // Not allowed unless target type was explicitly declared; return type counts as explicit, so allow.
                    return expectedReturn
                }
                if got != expectedReturn {
                    throw SemanticError.typeMismatch(expected: expectedReturn, got: got, rs.range.start, hint: coercionHint(expected: expectedReturn, expr: value))
                }
            } else {
                if expectedReturn != .void {
                    throw SemanticError.typeMismatch(expected: expectedReturn, got: .void, rs.range.start, hint: nil)
                }
            }
            return .void
        case .expr(let e):
            _ = try typeCheckExpr(e, scope: scope, symbols: symbols, expected: nil, typeInfo: &typeInfo)
            return .void
        case .if(let ifs):
            let cond = try typeCheckExpr(ifs.condition, scope: scope, symbols: symbols, expected: .bool, typeInfo: &typeInfo)
            if cond != .bool {
                throw SemanticError.typeMismatch(expected: .bool, got: cond, ifs.range.start, hint: nil)
            }
            let thenScope = scope.push()
            _ = try typeCheckBlock(ifs.thenBlock, scope: thenScope, symbols: symbols, expectedReturn: expectedReturn, typeInfo: &typeInfo)
            if let eb = ifs.elseBlock {
                let elseScope = scope.push()
                _ = try typeCheckBlock(eb, scope: elseScope, symbols: symbols, expectedReturn: expectedReturn, typeInfo: &typeInfo)
            }
            return .void
        }
    }

    private func typeCheckExpr(_ expr: Expr, scope: LocalScope, symbols: SymbolTable, expected: KiraType?, typeInfo: inout TypeInfo) throws -> KiraType {
        let result: KiraType
        switch expr {
        case .identifier(let name, let r):
            if let t = scope.lookup(name) ?? symbols.lookupValue(name) {
                result = t
            } else if name == "print" {
                // Built-in intrinsic. Accepts any single value and returns Void.
                result = .function(params: [.unknown], returns: .void)
            } else if name == "ffi_callback0" {
                // Built-in intrinsic. Creates a C-callable callback pointer for a Kira function name.
                result = .function(params: [.string], returns: .pointer(.named("CVoid")))
            } else {
                throw SemanticError.unknownIdentifier(name, r.start)
            }
        case .intLiteral:
            result = .int
        case .floatLiteral:
            result = .float
        case .stringLiteral:
            result = .string
        case .boolLiteral:
            result = .bool
        case .nilLiteral:
            result = .optional(.unknown)
        case .unary(let u):
            let t = try typeCheckExpr(u.expr, scope: scope, symbols: symbols, expected: nil, typeInfo: &typeInfo)
            switch u.op {
            case .negate:
                if t == .int || t == .float || t == .double { result = t }
                else { throw SemanticError.typeMismatch(expected: .int, got: t, u.range.start, hint: "unary '-' expects numeric") }
            case .not:
                if t == .bool { result = .bool }
                else { throw SemanticError.typeMismatch(expected: .bool, got: t, u.range.start, hint: "use a Bool condition") }
            }
        case .binary(let b):
            let lt = try typeCheckExpr(b.lhs, scope: scope, symbols: symbols, expected: nil, typeInfo: &typeInfo)
            let rt = try typeCheckExpr(b.rhs, scope: scope, symbols: symbols, expected: nil, typeInfo: &typeInfo)
            switch b.op {
            case .add, .sub, .mul, .div, .mod:
                if lt == .int && rt == .int { result = .int }
                else if (lt == .float || lt == .double) && lt == rt { result = lt }
                else { throw SemanticError.typeMismatch(expected: lt, got: rt, b.range.start, hint: "operands must have the same numeric type") }
            case .eq, .neq, .lt, .gt, .lte, .gte:
                if lt == rt { result = .bool }
                else { throw SemanticError.typeMismatch(expected: lt, got: rt, b.range.start, hint: "operands must have the same type") }
            case .and, .or:
                if lt == .bool && rt == .bool { result = .bool }
                else { throw SemanticError.typeMismatch(expected: .bool, got: lt, b.range.start, hint: "logical operators require Bool") }
            }
        case .member(let m):
            let baseTy = try typeCheckExpr(m.base, scope: scope, symbols: symbols, expected: nil, typeInfo: &typeInfo)
            switch baseTy {
            case .named(let typeName):
                if let mt = symbols.lookupMethod(typeName: typeName, name: m.name) {
                    result = mt
                } else {
                    throw SemanticError.memberNotFound(base: baseTy, name: m.name, m.range.start)
                }
            default:
                throw SemanticError.memberNotFound(base: baseTy, name: m.name, m.range.start)
            }
        case .call(let c):
            // Constructor-like intrinsics (resolved via imported stdlib types).
            if case .identifier(let name, _) = c.callee, name == "Color", symbols.types.contains("Color") {
                if c.arguments.count != 4 {
                    throw SemanticError.typeMismatch(expected: .named("Color"), got: .void, c.range.start, hint: "Color expects 4 arguments: r, g, b, a")
                }
                for arg in c.arguments {
                    let got = try typeCheckExpr(arg.value, scope: scope, symbols: symbols, expected: .float, typeInfo: &typeInfo)
                    if got != .float {
                        throw SemanticError.typeMismatch(expected: .float, got: got, arg.range.start, hint: coercionHint(expected: .float, expr: arg.value))
                    }
                }
                result = .named("Color")
                typeInfo.exprTypes[expr.range] = result
                return result
            }

            let calleeType = try typeCheckExpr(c.callee, scope: scope, symbols: symbols, expected: nil, typeInfo: &typeInfo)
            guard case .function(let params, let returns) = calleeType else { throw SemanticError.notCallable(c.range.start) }
            let isExternCallee: Bool = {
                if case .identifier(let name, _) = c.callee {
                    return symbols.functions[name]?.isExtern == true
                }
                return false
            }()
            if c.arguments.count != params.count {
                throw SemanticError.typeMismatch(expected: .function(params: params, returns: returns), got: calleeType, c.range.start, hint: "argument count mismatch")
            }
            for (i, arg) in c.arguments.enumerated() {
                let expectedType = params[i]
                let got = try typeCheckExpr(arg.value, scope: scope, symbols: symbols, expected: expectedType == .unknown ? nil : expectedType, typeInfo: &typeInfo)
                if expectedType == .unknown {
                    continue
                }
                if expectedType == .float, got == .int, isIntLiteral(arg.value) {
                    throw SemanticError.typeMismatch(
                        expected: .float,
                        got: .int,
                        arg.range.start,
                        hint: "use 12.0 or declare the target type explicitly"
                    )
                }
                if got != expectedType, !(isExternCallee && isFFIConvertible(got: got, expected: expectedType)) {
                    throw SemanticError.typeMismatch(expected: expectedType, got: got, arg.range.start, hint: coercionHint(expected: expectedType, expr: arg.value))
                }
            }
            if let trailing = c.trailingBlock {
                // Builder blocks are type-checked as normal blocks in their own scope.
                let s = scope.push()
                _ = try typeCheckBlock(trailing, scope: s, symbols: symbols, expectedReturn: .void, typeInfo: &typeInfo)
            }
            result = returns
        case .assign(let a):
            let tt = try typeCheckExpr(a.target, scope: scope, symbols: symbols, expected: nil, typeInfo: &typeInfo)
            let vt = try typeCheckExpr(a.value, scope: scope, symbols: symbols, expected: tt, typeInfo: &typeInfo)
            if tt != vt {
                throw SemanticError.typeMismatch(expected: tt, got: vt, a.range.start, hint: coercionHint(expected: tt, expr: a.value))
            }
            result = tt
        case .shaderMacro(_):
            // Treated as an opaque, compiler-managed blob type.
            result = .named("ShaderBlob")
        }

        if let expected, expected == .float, result == .int, isIntLiteral(expr) {
            // This is the strict inference rule: int literal cannot implicitly become Float.
            throw SemanticError.typeMismatch(
                expected: expected,
                got: result,
                expr.range.start,
                hint: "use 12.0 or declare the target type explicitly"
            )
        }

        typeInfo.exprTypes[expr.range] = result
        return result
    }

    private func isIntLiteral(_ expr: Expr) -> Bool {
        if case .intLiteral = expr { return true }
        return false
    }

    private func inferLiteralType(expr: Expr) -> KiraType? {
        switch expr {
        case .intLiteral: return .int
        case .floatLiteral: return .float
        case .stringLiteral: return .string
        case .boolLiteral: return .bool
        default: return nil
        }
    }

    private func coercionHint(expected: KiraType, expr: Expr) -> String? {
        if expected == .float, isIntLiteral(expr) {
            return "use 12.0 or declare the target type explicitly"
        }
        return nil
    }
}

private final class LocalScope {
    private var values: [String: KiraType] = [:]
    private let parent: LocalScope?
    private let symbols: SymbolTable

    init(parent: LocalScope?, symbols: SymbolTable) {
        self.parent = parent
        self.symbols = symbols
    }

    func define(_ name: String, type: KiraType) {
        values[name] = type
    }

    func lookup(_ name: String) -> KiraType? {
        if let t = values[name] { return t }
        return parent?.lookup(name)
    }

    func push() -> LocalScope {
        LocalScope(parent: self, symbols: symbols)
    }
}
