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

        // Collect typealias declarations for simple alias expansion (used heavily by bindgen output).
        var typeAliases: [String: TypeRef] = [:]
        for decl in module.declarations {
            if case .typealias(let td) = decl {
                typeAliases[td.name] = td.target
            }
        }

        func resolve(_ ref: TypeRef) -> KiraType {
            typeSystem.resolve(expandTypeRefAliases(ref, typeAliases: typeAliases))
        }
        func resolve(_ ref: TypeRef?) -> KiraType {
            guard let ref else { return .void }
            return resolve(ref)
        }

        // Register types and constructs first.
        for decl in module.declarations {
            switch decl {
            case .typealias(let td):
                symbols.addType(td.name)
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

        // Record @CStruct field schemas (used for constructor and field access typing).
        for decl in module.declarations {
            guard case .type(let td) = decl else { continue }
            guard td.annotations.contains(where: { $0.name == "CStruct" }) else { continue }
            let fieldSchemas: [(name: String, type: KiraType)] = td.fields.map { f in
                let ty = f.type.map(resolve) ?? .unknown
                return (f.name, ty)
            }
            symbols.addCStruct(typeName: td.name, fields: fieldSchemas)
        }

        // Register functions.
        for decl in module.declarations {
            if case .function(let fn) = decl {
                let params = fn.parameters.map { resolve($0.type) }
                let ret = resolve(fn.returnType)
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
                let params = fn.parameters.map { resolve($0.type) }
                let ret = resolve(fn.returnType)

                let proto = try parseFFIPrototype(for: fn, cHandleTypes: cHandleTypes, symbols: symbols, typeAliases: typeAliases)
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

        // Register and type-check global variables (module scope).
        // Globals are available to all functions and can be used to hold long-lived state (e.g. FFI handles).
        let globalScope = LocalScope(parent: nil, symbols: symbols)
        for decl in module.declarations {
            guard case .globalVar(let gv) = decl else { continue }
            let initType = try typeCheckExpr(gv.initializer, scope: globalScope, symbols: symbols, expected: nil, typeInfo: &typeInfo)
            let finalType: KiraType
            if let explicit = gv.explicitType.map(resolve) {
                if explicit == .float, case .int = initType, isIntLiteral(gv.initializer) {
                    finalType = .float
                } else if explicit == initType {
                    finalType = explicit
                } else {
                    throw SemanticError.typeMismatch(expected: explicit, got: initType, gv.range.start, hint: coercionHint(expected: explicit, expr: gv.initializer))
                }
            } else {
                finalType = initType
            }
            try symbols.addGlobal(name: gv.name, type: finalType, range: gv.range)
            globalScope.define(gv.name, type: finalType)
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
                    scope.define(p.name, type: resolve(p.type))
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

    private func parseFFIPrototype(
        for fn: ExternFunctionDecl,
        cHandleTypes: Set<String>,
        symbols: SymbolTable,
        typeAliases: [String: TypeRef]
    ) throws -> FFIPrototype {
        let expandedReturnType = fn.returnType.map { expandTypeRefAliases($0, typeAliases: typeAliases) }
        let expandedParams: [TypeRef] = fn.parameters.map { expandTypeRefAliases($0.type, typeAliases: typeAliases) }

        guard let ffiAnn = fn.annotations.first(where: { $0.name == "ffi" }) else {
            var visiting: Set<String> = []
            return FFIPrototype(
                library: nil,
                symbol: fn.name,
                linkage: .dynamic,
                returnType: encodeFFIType(expandedReturnType, cHandleTypes: cHandleTypes, symbols: symbols, visiting: &visiting),
                argumentTypes: expandedParams.map { encodeFFIType($0, cHandleTypes: cHandleTypes, symbols: symbols, visiting: &visiting) }
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

        var visiting: Set<String> = []
        return FFIPrototype(
            library: lib,
            symbol: fn.name,
            linkage: linkage,
            returnType: encodeFFIType(expandedReturnType, cHandleTypes: cHandleTypes, symbols: symbols, visiting: &visiting),
            argumentTypes: expandedParams.map { encodeFFIType($0, cHandleTypes: cHandleTypes, symbols: symbols, visiting: &visiting) }
        )
    }

    private func expandTypeRefAliases(_ ref: TypeRef, typeAliases: [String: TypeRef]) -> TypeRef {
        var visiting: Set<String> = []
        return expandTypeRefAliases(ref, typeAliases: typeAliases, visiting: &visiting)
    }

    private func expandTypeRefAliases(
        _ ref: TypeRef,
        typeAliases: [String: TypeRef],
        visiting: inout Set<String>
    ) -> TypeRef {
        switch ref.kind {
        case .named(let name):
            guard let target = typeAliases[name] else { return ref }
            guard !visiting.contains(name) else { return ref }
            visiting.insert(name)
            let expanded = expandTypeRefAliases(target, typeAliases: typeAliases, visiting: &visiting)
            visiting.remove(name)
            return TypeRef(kind: expanded.kind, range: ref.range)
        case .applied(let base, let args):
            let expandedArgs = args.map { expandTypeRefAliases($0, typeAliases: typeAliases, visiting: &visiting) }
            return TypeRef(kind: .applied(base, expandedArgs), range: ref.range)
        case .array(let inner):
            let e = expandTypeRefAliases(inner, typeAliases: typeAliases, visiting: &visiting)
            return TypeRef(kind: .array(e), range: ref.range)
        case .dictionary(let k, let v):
            let ek = expandTypeRefAliases(k, typeAliases: typeAliases, visiting: &visiting)
            let ev = expandTypeRefAliases(v, typeAliases: typeAliases, visiting: &visiting)
            return TypeRef(kind: .dictionary(key: ek, value: ev), range: ref.range)
        case .optional(let inner):
            let e = expandTypeRefAliases(inner, typeAliases: typeAliases, visiting: &visiting)
            return TypeRef(kind: .optional(e), range: ref.range)
        case .function(let ps, let r):
            let eps = ps.map { expandTypeRefAliases($0, typeAliases: typeAliases, visiting: &visiting) }
            let er = expandTypeRefAliases(r, typeAliases: typeAliases, visiting: &visiting)
            return TypeRef(kind: .function(params: eps, returns: er), range: ref.range)
        }
    }

    private func encodeFFIType(
        _ ref: TypeRef?,
        cHandleTypes: Set<String>,
        symbols: SymbolTable,
        visiting: inout Set<String>
    ) -> FFIPrototype.TypeEncoding {
        guard let ref else { return .scalar(.void) }
        return encodeFFIType(ref, cHandleTypes: cHandleTypes, symbols: symbols, visiting: &visiting)
    }

    private func encodeFFIType(
        _ ref: TypeRef,
        cHandleTypes: Set<String>,
        symbols: SymbolTable,
        visiting: inout Set<String>
    ) -> FFIPrototype.TypeEncoding {
        switch ref.kind {
        case .named(let n):
            return encodeFFITypeName(n, cHandleTypes: cHandleTypes, symbols: symbols, visiting: &visiting)
        case .applied(let base, let args):
            if base == "CPointer", let first = args.first {
                if case .named(let n) = first.kind, n == "CInt8" { return .scalar(.cstring) }
                let pointee = encodeFFIType(first, cHandleTypes: cHandleTypes, symbols: symbols, visiting: &visiting)
                return .pointerTo(pointee)
            }
            return .scalar(.pointer)
        case .optional(let inner):
            return encodeFFIType(inner, cHandleTypes: cHandleTypes, symbols: symbols, visiting: &visiting)
        default:
            return .scalar(.pointer)
        }
    }

    private func encodeFFIType(_ t: KiraType, cHandleTypes: Set<String>, symbols: SymbolTable, visiting: inout Set<String>) -> FFIPrototype.TypeEncoding {
        switch t {
        case .named(let n):
            return encodeFFITypeName(n, cHandleTypes: cHandleTypes, symbols: symbols, visiting: &visiting)
        case .int:
            return .scalar(.int64)
        case .float:
            return .scalar(.float32)
        case .double:
            return .scalar(.float64)
        case .bool:
            return .scalar(.uint8)
        case .pointer(let inner):
            // Preserve C string encoding inside C structs so `CPointer<CInt8>` fields can accept `String`.
            if inner == .named("CInt8") { return .scalar(.cstring) }
            return .scalar(.pointer)
        case .optional(let inner):
            return encodeFFIType(inner, cHandleTypes: cHandleTypes, symbols: symbols, visiting: &visiting)
        default:
            return .scalar(.pointer)
        }
    }

    private func encodeFFITypeName(
        _ n: String,
        cHandleTypes: Set<String>,
        symbols: SymbolTable,
        visiting: inout Set<String>
    ) -> FFIPrototype.TypeEncoding {
        if cHandleTypes.contains(n) { return .scalar(.uint32) }
        if symbols.cStructTypes.contains(n) {
            // @CStruct by-value. Avoid infinite recursion by falling back to opaque pointer for self-referential structs.
            if visiting.contains(n) { return .scalar(.pointer) }
            visiting.insert(n)
            let fieldMap = symbols.fields[n] ?? [:]
            let ordered = fieldMap.values.sorted(by: { $0.index < $1.index }).map(\.type)
            let fields = ordered.map { encodeFFIType($0, cHandleTypes: cHandleTypes, symbols: symbols, visiting: &visiting) }
            visiting.remove(n)
            return .cStruct(fields)
        }
        switch n {
        case "Void", "CVoid": return .scalar(.void)
        case "Bool", "CBool": return .scalar(.uint8)
        case "Int": return .scalar(.int64)
        case "CInt8": return .scalar(.int8)
        case "CInt16": return .scalar(.int16)
        case "CInt32": return .scalar(.int32)
        case "CInt64": return .scalar(.int64)
        case "CUInt8": return .scalar(.uint8)
        case "CUInt16": return .scalar(.uint16)
        case "CUInt32": return .scalar(.uint32)
        case "CUInt64": return .scalar(.uint64)
        case "CFloat": return .scalar(.float32)
        case "Float": return .scalar(.float64)
        case "CDouble", "Double": return .scalar(.float64)
        default: return .scalar(.pointer)
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

        // CPointer<*> -> CPointer<*> (ABI-compatible; used heavily for FFI, e.g. void*).
        if case .pointer = got, case .pointer = expected { return true }

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
            } else if name == "ffi_callback1_i32" {
                // Built-in intrinsic. Creates a C-callable callback pointer for: void callback(CInt32)
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
                if let f = symbols.lookupField(typeName: typeName, name: m.name) {
                    result = f.type
                    typeInfo.exprTypes[expr.range] = result
                    return result
                }
                if let mt = symbols.lookupMethod(typeName: typeName, name: m.name) {
                    result = mt
                } else {
                    throw SemanticError.memberNotFound(base: baseTy, name: m.name, m.range.start)
                }
            default:
                throw SemanticError.memberNotFound(base: baseTy, name: m.name, m.range.start)
            }
        case .call(let c):
            // @CStruct constructor: TypeName(field1:..., field2:...)
            if case .identifier(let typeName, _) = c.callee, symbols.cStructTypes.contains(typeName) {
                let fieldMap = symbols.fields[typeName] ?? [:]
                let fieldCount = fieldMap.count
                if c.arguments.count > fieldCount {
                    throw SemanticError.typeMismatch(
                        expected: .named(typeName),
                        got: .void,
                        c.range.start,
                        hint: "\(typeName) expects at most \(fieldCount) arguments"
                    )
                }

                var argsByIndex: [Expr?] = Array(repeating: nil, count: fieldCount)
                var used: Set<Int> = []
                for (pos, a) in c.arguments.enumerated() {
                    if let label = a.label {
                        guard let f = fieldMap[label] else {
                            throw SemanticError.memberNotFound(base: .named(typeName), name: label, a.range.start)
                        }
                        if used.contains(f.index) {
                            throw SemanticError.typeMismatch(expected: .named(typeName), got: .void, a.range.start, hint: "duplicate argument '\(label)'")
                        }
                        used.insert(f.index)
                        argsByIndex[f.index] = a.value
                    } else {
                        // Positional.
                        guard pos < fieldCount else { continue }
                        if used.contains(pos) {
                            throw SemanticError.typeMismatch(expected: .named(typeName), got: .void, a.range.start, hint: "argument position \(pos) already filled by labeled argument")
                        }
                        used.insert(pos)
                        argsByIndex[pos] = a.value
                    }
                }

                // Type-check field values.
                let ordered = fieldMap
                    .map { (name: $0.key, index: $0.value.index, type: $0.value.type) }
                    .sorted(by: { $0.index < $1.index })
                for f in ordered {
                    let expectedType = f.type
                    guard let argExpr = argsByIndex[f.index] else { continue }
                    let got = try typeCheckExpr(argExpr, scope: scope, symbols: symbols, expected: expectedType == .unknown ? nil : expectedType, typeInfo: &typeInfo)
                    if expectedType != .unknown, got != expectedType {
                        // Reuse FFI convertibility rules for C types.
                        if !isFFIConvertible(got: got, expected: expectedType) {
                            throw SemanticError.typeMismatch(expected: expectedType, got: got, argExpr.range.start, hint: "field '\(f.name)' expects \(expectedType)")
                        }
                    }
                }

                result = .named(typeName)
                typeInfo.exprTypes[expr.range] = result
                return result
            }

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
                    let canBoxCStructPointer: Bool = {
                        guard isExternCallee else { return false }
                        guard case .named(let gotName) = got, symbols.cStructTypes.contains(gotName) else { return false }
                        guard case .pointer(let inner) = expectedType, case .named(let expectedName) = inner else { return false }
                        return gotName == expectedName
                    }()
                    if canBoxCStructPointer {
                        continue
                    }
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
