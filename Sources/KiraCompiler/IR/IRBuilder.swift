import Foundation

public struct IRBuilder {
    public init() {}

    public func build(from typed: TypedModule) throws -> KiraIRModule {
        let instanceFieldInitializers = buildInstanceFieldInitializerMap(
            declarations: typed.ast.declarations,
            symbols: typed.symbols
        )
        var fns: [KiraIRFunction] = []
        for decl in typed.ast.declarations {
            switch decl {
            case .function(let fn):
                fns.append(try buildFunction(
                    fn: fn,
                    symbols: typed.symbols,
                    typeInfo: typed.typeInfo,
                    instanceFieldInitializers: instanceFieldInitializers
                ))
            case .externFunction(let fn):
                fns.append(try buildExternFunction(fn: fn, symbols: typed.symbols))
            case .type(let td):
                for method in td.methods {
                    fns.append(try buildMethod(
                        typeName: td.name,
                        fn: method,
                        symbols: typed.symbols,
                        typeInfo: typed.typeInfo,
                        instanceFieldInitializers: instanceFieldInitializers
                    ))
                }
                for method in td.statics {
                    fns.append(try buildStaticMethod(
                        typeName: td.name,
                        fn: method,
                        symbols: typed.symbols,
                        typeInfo: typed.typeInfo,
                        instanceFieldInitializers: instanceFieldInitializers
                    ))
                }
            default:
                break
            }
        }
        if let initFn = try buildGlobalInit(
            declarations: typed.ast.declarations,
            symbols: typed.symbols,
            typeInfo: typed.typeInfo,
            instanceFieldInitializers: instanceFieldInitializers
        ) {
            fns.append(initFn)
        }
        return KiraIRModule(functions: fns)
    }

    private func buildInstanceFieldInitializerMap(
        declarations: [Decl],
        symbols: SymbolTable
    ) -> [String: [Expr?]] {
        var result: [String: [Expr?]] = [:]
        for decl in declarations {
            guard case .type(let td) = decl else { continue }
            let fieldCount = symbols.fields[td.name]?.count ?? td.fields.count
            var initializers: [Expr?] = Array(repeating: nil, count: fieldCount)
            for field in td.fields where !field.isStatic {
                guard let info = symbols.lookupField(typeName: td.name, name: field.name) else { continue }
                initializers[info.index] = field.initializer
            }
            result[td.name] = initializers
        }
        return result
    }

    private func ffiTypeEncoding(for type: KiraType, symbols: SymbolTable) -> FFIPrototype.TypeEncoding {
        switch type {
        case .int:
            return .scalar(.int64)
        case .float:
            return .scalar(.float64)
        case .double:
            return .scalar(.float64)
        case .bool:
            return .scalar(.uint8)
        case .void:
            return .scalar(.void)
        case .pointer(let inner):
            if inner == .named("CInt8") {
                return .scalar(.cstring)
            }
            return .pointerTo(.scalar(.void))
        case .fixedArray(let element, let count):
            let encoded = ffiTypeEncoding(for: element, symbols: symbols)
            return .cStruct(Array(repeating: encoded, count: count))
        case .named(let name):
            if symbols.cStructTypes.contains(name) {
                let orderedFields = (symbols.fields[name] ?? [:])
                    .values
                    .sorted(by: { $0.index < $1.index })
                let fields = orderedFields.map { ffiTypeEncoding(for: $0.type, symbols: symbols) }
                return .cStruct(fields)
            }
            switch name {
            case "Void", "CVoid":
                return .scalar(.void)
            case "Bool", "CBool":
                return .scalar(.uint8)
            case "Int":
                return .scalar(.int64)
            case "CInt8":
                return .scalar(.int8)
            case "CInt16":
                return .scalar(.int16)
            case "CInt32":
                return .scalar(.int32)
            case "CInt64":
                return .scalar(.int64)
            case "CUInt8":
                return .scalar(.uint8)
            case "CUInt16":
                return .scalar(.uint16)
            case "CUInt32":
                return .scalar(.uint32)
            case "CUInt64":
                return .scalar(.uint64)
            case "CFloat":
                return .scalar(.float32)
            case "Float":
                return .scalar(.float64)
            case "CDouble", "Double":
                return .scalar(.float64)
            default:
                return .scalar(.pointer)
            }
        case .optional(let inner):
            return ffiTypeEncoding(for: inner, symbols: symbols)
        default:
            return .scalar(.pointer)
        }
    }

    private enum DirectFFICallbackKind {
        case callback0
        case callback1I32
    }

    private func directFFICallbackKind(for expr: Expr, expected: KiraType?, symbols: SymbolTable) -> DirectFFICallbackKind? {
        guard expected == .pointer(.named("CVoid")) else { return nil }
        guard case .identifier(let name, _) = expr else { return nil }
        guard let fn = symbols.functions[name], !fn.isExtern else { return nil }
        guard case .function(let params, let returns) = fn.type, returns == .void else { return nil }
        if params.isEmpty { return .callback0 }
        if params.count == 1, params[0] == .int { return .callback1I32 }
        return nil
    }

    private func builderParamTypeName(params: [KiraType], explicitArgumentCount: Int, symbols: SymbolTable) -> String? {
        guard explicitArgumentCount + 1 == params.count else { return nil }
        guard case .named(let typeName) = params[explicitArgumentCount] else { return nil }
        guard symbols.fields[typeName] != nil else { return nil }
        return typeName
    }

    private func loweredStaticFieldName(typeName: String, fieldName: String) -> String {
        "__\(typeName)_static_\(fieldName)"
    }

    private func buildGlobalInit(
        declarations: [Decl],
        symbols: SymbolTable,
        typeInfo: TypeInfo,
        instanceFieldInitializers: [String: [Expr?]]
    ) throws -> KiraIRFunction? {
        let globals: [VarDeclStmt] = declarations.compactMap {
            if case .globalVar(let gv) = $0 { return gv }
            return nil
        }
        let staticFields: [(globalName: String, initializer: Expr)] = declarations.flatMap { decl in
            guard case .type(let td) = decl else {
                return [(globalName: String, initializer: Expr)]()
            }
            return td.fields
                .filter(\.isStatic)
                .map { (loweredStaticFieldName(typeName: td.name, fieldName: $0.name), $0.initializer ?? .nilLiteral($0.range)) }
        }
        guard !globals.isEmpty || !staticFields.isEmpty else { return nil }

        var emitter = StackEmitter()
        func exprType(_ e: Expr) -> KiraType? { typeInfo.exprTypes[e.range] }

        func enumConstructorInfo(_ callee: Expr) -> (String, EnumCaseSymbol)? {
            switch callee {
            case .member(let member):
                guard case .identifier(let enumName, _) = member.base else { return nil }
                return symbols.lookupEnumCase(typeName: enumName, name: member.name).map { (enumName, $0) }
            case .leadingMember(let name, _):
                guard case .function(_, let returns)? = exprType(callee),
                      case .named(let enumName) = returns else {
                    return nil
                }
                return symbols.lookupEnumCase(typeName: enumName, name: name).map { (enumName, $0) }
            default:
                return nil
            }
        }

        func emitExpr(_ e: Expr, coercedTo expected: KiraType? = nil) throws {
            if let callbackKind = directFFICallbackKind(for: e, expected: expected, symbols: symbols),
               case .identifier(let name, _) = e {
                emitter.emit(.pushString(name))
                switch callbackKind {
                case .callback0:
                    emitter.emit(.ffiCallback0)
                case .callback1I32:
                    emitter.emit(.ffiCallback1I32)
                }
                return
            }
            switch e {
            case .intLiteral(let v, _):
                emitter.emit(.pushInt(v))
            case .floatLiteral(let v, _):
                emitter.emit(.pushFloat(v))
            case .stringLiteral(let s, _):
                emitter.emit(.pushString(s))
            case .boolLiteral(let b, _):
                emitter.emit(.pushBool(b))
            case .nilLiteral:
                emitter.emit(.pushNil)
            case .leadingMember(let name, _):
                let contextualType = exprType(e) ?? expected
                if case .named(let typeName) = (contextualType ?? .unknown),
                   let enumCase = symbols.lookupEnumCase(typeName: typeName, name: name),
                   enumCase.associatedValues.isEmpty {
                    emitter.emit(.pushInt(enumCase.tag))
                } else {
                    emitter.emit(.pushNil)
                }
            case .sizeOf:
                emitter.emit(.pushInt(typeInfo.sizeOfValues[e.range] ?? 0))
            case .arrayLiteral(let literal):
                switch exprType(e) ?? .unknown {
                case .fixedArray(let elementType, let count):
                    for element in literal.elements {
                        try emitExpr(element)
                    }
                    let encoding = ffiTypeEncoding(for: elementType, symbols: symbols)
                    emitter.emit(.makeFFIArray(count: UInt16(count), elementType: encoding.bytes))
                case .array(let elementType):
                    emitter.emit(.pushInt(0))
                    emitter.emit(.newArray)
                    for element in literal.elements {
                        try emitExpr(element, coercedTo: elementType)
                        emitter.emit(.arrayAppend)
                    }
                default:
                    emitter.emit(.pushNil)
                }
            case .identifier(let name, _):
                emitter.emit(.loadGlobalSymbol(name))
            case .unary(let u):
                try emitExpr(u.expr)
                switch u.op {
                case .negate:
                    let t = exprType(u.expr) ?? .int
                    emitter.emit((t == .float || t == .double) ? .negFloat : .negInt)
                case .not:
                    emitter.emit(.notBool)
                }
            case .binary(let b):
                try emitExpr(b.lhs)
                try emitExpr(b.rhs)
                switch b.op {
                case .add:
                    let t = exprType(b.lhs) ?? .int
                    emitter.emit((t == .float || t == .double) ? .addFloat : .addInt)
                case .sub:
                    let t = exprType(b.lhs) ?? .int
                    emitter.emit((t == .float || t == .double) ? .subFloat : .subInt)
                case .mul:
                    let t = exprType(b.lhs) ?? .int
                    emitter.emit((t == .float || t == .double) ? .mulFloat : .mulInt)
                case .div:
                    let t = exprType(b.lhs) ?? .int
                    emitter.emit((t == .float || t == .double) ? .divFloat : .divInt)
                case .mod:
                    emitter.emit(.modInt)
                case .eq:
                    let t = exprType(b.lhs) ?? .int
                    emitter.emit((t == .float || t == .double) ? .eqFloat : .eqInt)
                case .lt:
                    let t = exprType(b.lhs) ?? .int
                    emitter.emit((t == .float || t == .double) ? .ltFloat : .ltInt)
                case .gt:
                    let t = exprType(b.lhs) ?? .int
                    emitter.emit((t == .float || t == .double) ? .gtFloat : .gtInt)
                case .lte:
                    let t = exprType(b.lhs) ?? .int
                    emitter.emit((t == .float || t == .double) ? .gtFloat : .gtInt)
                    emitter.emit(.notBool)
                case .gte:
                    let t = exprType(b.lhs) ?? .int
                    emitter.emit((t == .float || t == .double) ? .ltFloat : .ltInt)
                    emitter.emit(.notBool)
                case .and:
                    emitter.emit(.andBool)
                case .or:
                    emitter.emit(.orBool)
                case .neq:
                    let t = exprType(b.lhs) ?? .int
                    emitter.emit((t == .float || t == .double) ? .eqFloat : .eqInt)
                    emitter.emit(.notBool)
                }
            case .conditional(let c):
                let baseDepth = emitter.currentDepth()
                try emitExpr(c.condition)
                let jumpIfFalseIndex = emitter.emitPlaceholderJumpIfFalse()
                try emitExpr(c.thenExpr)
                let jumpOverElseIndex = emitter.emitPlaceholderJump()
                emitter.patchJump(at: jumpIfFalseIndex, to: emitter.currentOffset())
                emitter.restoreDepth(baseDepth)
                try emitExpr(c.elseExpr)
                emitter.patchJump(at: jumpOverElseIndex, to: emitter.currentOffset())
            case .call(let c):
                if case .identifier(let name, _) = c.callee, name == "print" {
                    guard c.arguments.count == 1 else { emitter.emit(.pushNil); return }
                    try emitExpr(c.arguments[0].value)
                    emitter.emit(.print)
                    emitter.emit(.pushNil)
                    return
                }
                if case .identifier(let typeName, _) = c.callee, let fieldMap = symbols.fields[typeName] {
                    let fieldCount = fieldMap.count
                    var fieldTypes: [KiraType] = Array(repeating: .unknown, count: fieldCount)
                    for info in fieldMap.values {
                        fieldTypes[info.index] = info.type
                    }
                    emitter.emit(.newTypedObject(typeName: typeName, fieldCount: UInt16(fieldCount)))

                    var argsByIndex: [Expr?] = Array(repeating: nil, count: fieldCount)
                    var used: Set<Int> = []
                    for (pos, a) in c.arguments.enumerated() {
                        if let label = a.label, let info = fieldMap[label] {
                            used.insert(info.index)
                            argsByIndex[info.index] = a.value
                        } else if a.label == nil, pos < fieldCount, !used.contains(pos) {
                            used.insert(pos)
                            argsByIndex[pos] = a.value
                        }
                    }
                    for i in 0..<fieldCount {
                        emitter.emit(.dup)
                        let defaultExpr = i < (instanceFieldInitializers[typeName]?.count ?? 0)
                            ? instanceFieldInitializers[typeName]![i]
                            : nil
                        try emitExpr(argsByIndex[i] ?? defaultExpr ?? .nilLiteral(c.range), coercedTo: fieldTypes[i])
                        emitter.emit(.storeField(UInt16(i)))
                    }
                    return
                }
                if case .identifier(let name, _) = c.callee, name == "ffi_callback0" {
                    guard c.arguments.count == 1 else { emitter.emit(.pushNil); return }
                    try emitExpr(c.arguments[0].value)
                    emitter.emit(.ffiCallback0)
                    return
                }
                if case .identifier(let name, _) = c.callee, name == "ffi_callback1_i32" {
                    guard c.arguments.count == 1 else { emitter.emit(.pushNil); return }
                    try emitExpr(c.arguments[0].value)
                    emitter.emit(.ffiCallback1I32)
                    return
                }
                if case .identifier(let name, _) = c.callee, name == "Color", exprType(e) == .named("Color") {
                    guard c.arguments.count == 4 else { emitter.emit(.pushNil); return }
                    for a in c.arguments { try emitExpr(a.value) }
                    emitter.emit(.makeColor)
                    return
                }
                if case .identifier(let name, _) = c.callee, name == "Float" {
                    guard c.arguments.count == 1 else { emitter.emit(.pushNil); return }
                    try emitExpr(c.arguments[0].value)
                    if (exprType(c.arguments[0].value) ?? .unknown) == .int {
                        emitter.emit(.intToFloat)
                    }
                    return
                }
                if case .identifier(let name, _) = c.callee, name == "Int" {
                    guard c.arguments.count == 1 else { emitter.emit(.pushNil); return }
                    try emitExpr(c.arguments[0].value)
                    let argumentType = exprType(c.arguments[0].value) ?? .unknown
                    if argumentType == .float || argumentType == .double {
                        emitter.emit(.floatToInt)
                    }
                    return
                }
                if case .member(let m) = c.callee,
                   case .array = (exprType(m.base) ?? .unknown),
                   m.name == "append" {
                    guard c.arguments.count == 1 else {
                        emitter.emit(.pushNil)
                        return
                    }
                    try emitExpr(m.base)
                    try emitExpr(c.arguments[0].value)
                    emitter.emit(.arrayAppend)
                    return
                }
                if case .member(let m) = c.callee,
                   case .named(let protocolName) = (exprType(m.base) ?? .unknown),
                   symbols.lookupProtocolRequirement(protocolName: protocolName, name: m.name) != nil {
                    try emitExpr(m.base)
                    for argument in c.arguments {
                        try emitExpr(argument.value)
                    }
                    emitter.emit(.callProtocolMethod(m.name, argCount: UInt8(c.arguments.count)))
                    return
                }

                if case .member(let m) = c.callee,
                   case .named(let typeName) = (exprType(m.base) ?? .unknown),
                   let method = symbols.lookupMethod(typeName: typeName, name: m.name) {
                    emitter.emit(.loadGlobalSymbol(method.loweredName))
                    try emitExpr(m.base)
                    let expectedParams: [KiraType]
                    if case .function(let params, _) = method.type {
                        expectedParams = params
                    } else {
                        expectedParams = []
                    }
                    for (index, a) in c.arguments.enumerated() {
                        let expectedArg = index < expectedParams.count ? expectedParams[index] : nil
                        try emitExpr(a.value, coercedTo: expectedArg)
                    }
                    emitter.emit(.call(argCount: UInt8(c.arguments.count + 1)))
                    return
                }

                let expectedParams: [KiraType]
                if case .identifier(let name, _) = c.callee,
                   symbols.functions[name]?.isExtern == true,
                   case .function(let params, _) = exprType(c.callee) ?? symbols.lookupValue(name) ?? .unknown {
                    expectedParams = params
                } else {
                    expectedParams = []
                }

                try emitExpr(c.callee)
                for (index, a) in c.arguments.enumerated() {
                    let expectedArg = index < expectedParams.count ? expectedParams[index] : nil
                    try emitExpr(a.value, coercedTo: expectedArg)
                }
                emitter.emit(.call(argCount: UInt8(c.arguments.count)))
            case .member(let m):
                if case .identifier(let enumName, _) = m.base,
                   let enumCase = symbols.lookupEnumCase(typeName: enumName, name: m.name),
                   enumCase.associatedValues.isEmpty {
                    emitter.emit(.pushInt(enumCase.tag))
                } else if (exprType(m.base) ?? .unknown) == .string, m.name == "count" {
                    try emitExpr(m.base)
                    emitter.emit(.stringLength)
                } else if case .array = (exprType(m.base) ?? .unknown), m.name == "count" {
                    try emitExpr(m.base)
                    emitter.emit(.arrayLength)
                } else if case .identifier(let typeName, _) = m.base,
                          symbols.lookupStaticField(typeName: typeName, name: m.name) != nil {
                    emitter.emit(.loadGlobalSymbol(loweredStaticFieldName(typeName: typeName, fieldName: m.name)))
                } else if case .identifier(let typeName, _) = m.base,
                          let method = symbols.lookupStaticMethod(typeName: typeName, name: m.name) {
                    emitter.emit(.loadGlobalSymbol(method.loweredName))
                } else if case .named(let typeName) = (exprType(m.base) ?? .unknown),
                   let f = symbols.lookupField(typeName: typeName, name: m.name) {
                    try emitExpr(m.base)
                    emitter.emit(.loadField(UInt16(f.index)))
                } else if case .named(let typeName) = (exprType(m.base) ?? .unknown),
                          let method = symbols.lookupMethod(typeName: typeName, name: m.name) {
                    emitter.emit(.loadGlobalSymbol(method.loweredName))
                } else {
                    emitter.emit(.loadGlobalSymbol(m.name))
                }
            case .index(let i):
                try emitExpr(i.base)
                try emitExpr(i.index)
                emitter.emit(.loadIndex)
            case .assign(let a):
                // Global init treats identifier assignments as global symbol stores.
                if case .member(let m) = a.target,
                   case .named(let typeName) = (exprType(m.base) ?? .unknown),
                   let f = symbols.lookupField(typeName: typeName, name: m.name) {
                    try emitExpr(m.base)
                    try emitExpr(a.value)
                    emitter.emit(.storeField(UInt16(f.index)))
                    emitter.emit(.pushNil)
                } else if case .index(let i) = a.target {
                    try emitExpr(i.base)
                    try emitExpr(i.index)
                    try emitExpr(a.value)
                    emitter.emit(.storeIndex)
                    emitter.emit(.pushNil)
                } else {
                    try emitExpr(a.value)
                    if case .identifier(let name, _) = a.target, symbols.globals[name] != nil {
                        emitter.emit(.storeGlobalSymbol(name))
                        emitter.emit(.loadGlobalSymbol(name))
                    } else {
                        emitter.emit(.pop)
                        emitter.emit(.pushNil)
                    }
                }
            case .shaderMacro(let sm):
                emitter.emit(.pushString("shader:\(sm.functionName)"))
            }
        }

        for gv in globals {
            try emitExpr(gv.initializer)
            emitter.emit(.storeGlobalSymbol(gv.name))
        }
        for staticField in staticFields {
            try emitExpr(staticField.initializer)
            emitter.emit(.storeGlobalSymbol(staticField.globalName))
        }
        emitter.emit(.pushNil)
        emitter.emit(.ret)

        return KiraIRFunction(
            name: "__kira_init_globals",
            params: [],
            returnType: .void,
            localCount: 0,
            maxStackDepth: emitter.maxDepth,
            instructions: emitter.instructions,
            executionMode: .auto
        )
    }

    private func buildExternFunction(fn: ExternFunctionDecl, symbols: SymbolTable) throws -> KiraIRFunction {
        let fnSym = symbols.functions[fn.name]!
        guard case .function(let params, let ret) = fnSym.type else {
            return KiraIRFunction(name: fn.name, params: [], returnType: .void, localCount: 0, maxStackDepth: 0, instructions: [], executionMode: .auto)
        }
        guard let proto = symbols.ffi[fn.name] else {
            return KiraIRFunction(name: fn.name, params: params, returnType: ret, localCount: params.count, maxStackDepth: 0, instructions: [.pushNil, .ret], executionMode: .auto)
        }

        var insts: [KiraIRInst] = []
        insts.reserveCapacity(6 + params.count)

        if let lib = proto.library {
            insts.append(.pushString(lib))
        } else {
            insts.append(.pushNil)
        }
        insts.append(.pushString(proto.symbol))
        insts.append(.ffiLoad)
        for i in 0..<params.count {
            insts.append(.loadLocal(UInt8(i)))
        }
        insts.append(.ffiCall(
            argCount: UInt8(proto.argumentTypes.count),
            returnType: proto.returnType.bytes,
            argumentTypes: proto.argumentTypes.map(\.bytes)
        ))
        insts.append(.ret)

        let maxStack = computeMaxStack(insts)

        return KiraIRFunction(
            name: fn.name,
            params: params,
            returnType: ret,
            localCount: params.count,
            maxStackDepth: maxStack,
            instructions: insts,
            executionMode: .auto
        )
    }

    private func buildFunction(
        fn: FunctionDecl,
        symbols: SymbolTable,
        typeInfo: TypeInfo,
        instanceFieldInitializers: [String: [Expr?]]
    ) throws -> KiraIRFunction {
        try buildCallable(
            fn: fn,
            loweredName: fn.name,
            selfType: nil,
            symbols: symbols,
            typeInfo: typeInfo,
            instanceFieldInitializers: instanceFieldInitializers
        )
    }

    private func buildMethod(
        typeName: String,
        fn: FunctionDecl,
        symbols: SymbolTable,
        typeInfo: TypeInfo,
        instanceFieldInitializers: [String: [Expr?]]
    ) throws -> KiraIRFunction {
        try buildCallable(
            fn: fn,
            loweredName: "__\(typeName)_\(fn.name)",
            selfType: .named(typeName),
            symbols: symbols,
            typeInfo: typeInfo,
            instanceFieldInitializers: instanceFieldInitializers
        )
    }

    private func buildStaticMethod(
        typeName: String,
        fn: FunctionDecl,
        symbols: SymbolTable,
        typeInfo: TypeInfo,
        instanceFieldInitializers: [String: [Expr?]]
    ) throws -> KiraIRFunction {
        try buildCallable(
            fn: fn,
            loweredName: "__\(typeName)_static_\(fn.name)",
            selfType: nil,
            symbols: symbols,
            typeInfo: typeInfo,
            instanceFieldInitializers: instanceFieldInitializers
        )
    }

    private func buildCallable(
        fn: FunctionDecl,
        loweredName: String,
        selfType: KiraType?,
        symbols: SymbolTable,
        typeInfo: TypeInfo,
        instanceFieldInitializers: [String: [Expr?]]
    ) throws -> KiraIRFunction {
        let fnSym = symbols.functions[loweredName]!
        let mode: KiraIRFunction.ExecutionMode
        switch fnSym.executionMode {
        case .auto: mode = .auto
        case .native: mode = .native
        case .runtime: mode = .runtime
        }
        guard case .function(let params, let ret) = fnSym.type else {
            return KiraIRFunction(name: loweredName, params: [], returnType: .void, localCount: 0, maxStackDepth: 0, instructions: [], executionMode: mode)
        }

        var emitter = StackEmitter()

        // Allocate locals: params first.
        struct LocalBinding {
            var slot: UInt8
            var type: KiraType
        }
        struct BuilderBinding {
            var slot: UInt8
            var typeName: String
        }
        var locals: [String: LocalBinding] = [:]
        var builderStack: [BuilderBinding] = []
        var nextLocal: UInt8 = 0
        var paramOffset = 0
        let implicitSelfTypeName: String? = {
            if case .named(let name) = selfType { return name }
            return nil
        }()
        if let selfType {
            locals["self"] = .init(slot: nextLocal, type: selfType)
            nextLocal &+= 1
            paramOffset = 1
        }
        for (i, p) in fn.parameters.enumerated() {
            locals[p.name] = .init(slot: nextLocal, type: params[i + paramOffset])
            nextLocal &+= 1
        }

        func allocLocal(_ name: String, type: KiraType) -> UInt8 {
            if let existing = locals[name] { return existing.slot }
            let slot = nextLocal
            locals[name] = .init(slot: slot, type: type)
            nextLocal &+= 1
            return slot
        }

        func builderBinding() -> BuilderBinding? {
            builderStack.last
        }

        func emitDefaultObject(typeName: String) throws {
            let fieldCount = symbols.fields[typeName]?.count ?? 0
            emitter.emit(.newTypedObject(typeName: typeName, fieldCount: UInt16(fieldCount)))
            var fieldTypes: [KiraType] = Array(repeating: .unknown, count: fieldCount)
            for info in (symbols.fields[typeName] ?? [:]).values {
                fieldTypes[info.index] = info.type
            }
            for index in 0..<fieldCount {
                emitter.emit(.dup)
                let defaultExpr = index < (instanceFieldInitializers[typeName]?.count ?? 0)
                    ? instanceFieldInitializers[typeName]![index]
                    : nil
                if let defaultExpr {
                    try emitExpr(defaultExpr, coercedTo: fieldTypes[index])
                } else {
                    emitter.emit(.pushNil)
                }
                emitter.emit(.storeField(UInt16(index)))
            }
        }

        func exprType(_ e: Expr) -> KiraType? { typeInfo.exprTypes[e.range] }

        func enumConstructorInfo(_ callee: Expr) -> (String, EnumCaseSymbol)? {
            switch callee {
            case .member(let member):
                guard case .identifier(let enumName, _) = member.base else { return nil }
                return symbols.lookupEnumCase(typeName: enumName, name: member.name).map { (enumName, $0) }
            case .leadingMember(let name, _):
                guard case .function(_, let returns)? = exprType(callee),
                      case .named(let enumName) = returns else {
                    return nil
                }
                return symbols.lookupEnumCase(typeName: enumName, name: name).map { (enumName, $0) }
            default:
                return nil
            }
        }

        func isIntLiteral(_ e: Expr) -> Bool {
            if case .intLiteral = e { return true }
            return false
        }

        func emitExpr(_ e: Expr, coercedTo expected: KiraType? = nil) throws {
            if let callbackKind = directFFICallbackKind(for: e, expected: expected, symbols: symbols),
               case .identifier(let name, _) = e {
                emitter.emit(.pushString(name))
                switch callbackKind {
                case .callback0:
                    emitter.emit(.ffiCallback0)
                case .callback1I32:
                    emitter.emit(.ffiCallback1I32)
                }
                return
            }
            switch e {
            case .intLiteral(let v, _):
                emitter.emit(.pushInt(v))
            case .floatLiteral(let v, _):
                emitter.emit(.pushFloat(v))
            case .stringLiteral(let s, _):
                emitter.emit(.pushString(s))
            case .boolLiteral(let b, _):
                emitter.emit(.pushBool(b))
            case .nilLiteral:
                emitter.emit(.pushNil)
            case .leadingMember(let name, _):
                let contextualType = exprType(e) ?? expected
                if case .named(let typeName) = (contextualType ?? .unknown),
                   let enumCase = symbols.lookupEnumCase(typeName: typeName, name: name),
                   enumCase.associatedValues.isEmpty {
                    emitter.emit(.pushInt(enumCase.tag))
                } else {
                    emitter.emit(.pushNil)
                }
            case .sizeOf:
                emitter.emit(.pushInt(typeInfo.sizeOfValues[e.range] ?? 0))
            case .arrayLiteral(let literal):
                switch exprType(e) ?? .unknown {
                case .fixedArray(let elementType, let count):
                    for element in literal.elements {
                        try emitExpr(element)
                    }
                    let encoding = ffiTypeEncoding(for: elementType, symbols: symbols)
                    emitter.emit(.makeFFIArray(count: UInt16(count), elementType: encoding.bytes))
                case .array(let elementType):
                    emitter.emit(.pushInt(0))
                    emitter.emit(.newArray)
                    for element in literal.elements {
                        try emitExpr(element, coercedTo: elementType)
                        emitter.emit(.arrayAppend)
                    }
                default:
                    emitter.emit(.pushNil)
                    return
                }
            case .identifier(let name, _):
                if let binding = locals[name] {
                    emitter.emit(.loadLocal(binding.slot))
                } else if let builder = builderBinding(),
                          let field = symbols.lookupField(typeName: builder.typeName, name: name) {
                    emitter.emit(.loadLocal(builder.slot))
                    emitter.emit(.loadField(UInt16(field.index)))
                } else if let builder = builderBinding(),
                          let method = symbols.lookupMethod(typeName: builder.typeName, name: name) {
                    emitter.emit(.loadGlobalSymbol(method.loweredName))
                } else if let typeName = implicitSelfTypeName,
                          let selfBinding = locals["self"],
                          let field = symbols.lookupField(typeName: typeName, name: name) {
                    emitter.emit(.loadLocal(selfBinding.slot))
                    emitter.emit(.loadField(UInt16(field.index)))
                } else if let typeName = implicitSelfTypeName,
                          symbols.lookupMethod(typeName: typeName, name: name) != nil {
                    emitter.emit(.loadGlobalSymbol("__\(typeName)_\(name)"))
                } else {
                    emitter.emit(.loadGlobalSymbol(name))
                }
            case .unary(let u):
                try emitExpr(u.expr)
                switch u.op {
                case .negate:
                    let t = exprType(e) ?? exprType(u.expr) ?? .int
                    if t == .float || t == .double {
                        emitter.emit(.negFloat)
                    } else {
                        emitter.emit(.negInt)
                    }
                case .not:
                    emitter.emit(.notBool)
                }
            case .binary(let b):
                try emitExpr(b.lhs)
                try emitExpr(b.rhs)
                switch b.op {
                case .add:
                    let t = exprType(e) ?? .int
                    emitter.emit((t == .float || t == .double) ? .addFloat : .addInt)
                case .sub:
                    let t = exprType(e) ?? .int
                    emitter.emit((t == .float || t == .double) ? .subFloat : .subInt)
                case .mul:
                    let t = exprType(e) ?? .int
                    emitter.emit((t == .float || t == .double) ? .mulFloat : .mulInt)
                case .div:
                    let t = exprType(e) ?? .int
                    emitter.emit((t == .float || t == .double) ? .divFloat : .divInt)
                case .mod:
                    emitter.emit(.modInt)
                case .eq:
                    let t = exprType(b.lhs) ?? .int
                    emitter.emit((t == .float || t == .double) ? .eqFloat : .eqInt)
                case .lt:
                    let t = exprType(b.lhs) ?? .int
                    emitter.emit((t == .float || t == .double) ? .ltFloat : .ltInt)
                case .gt:
                    let t = exprType(b.lhs) ?? .int
                    emitter.emit((t == .float || t == .double) ? .gtFloat : .gtInt)
                case .lte:
                    let t = exprType(b.lhs) ?? .int
                    emitter.emit((t == .float || t == .double) ? .gtFloat : .gtInt)
                    emitter.emit(.notBool)
                case .gte:
                    let t = exprType(b.lhs) ?? .int
                    emitter.emit((t == .float || t == .double) ? .ltFloat : .ltInt)
                    emitter.emit(.notBool)
                case .and: emitter.emit(.andBool)
                case .or: emitter.emit(.orBool)
                case .neq:
                    let t = exprType(b.lhs) ?? .int
                    emitter.emit((t == .float || t == .double) ? .eqFloat : .eqInt)
                    emitter.emit(.notBool)
                }
            case .conditional(let c):
                let baseDepth = emitter.currentDepth()
                try emitExpr(c.condition)
                let jumpIfFalseIndex = emitter.emitPlaceholderJumpIfFalse()
                try emitExpr(c.thenExpr)
                let jumpOverElseIndex = emitter.emitPlaceholderJump()
                emitter.patchJump(at: jumpIfFalseIndex, to: emitter.currentOffset())
                emitter.restoreDepth(baseDepth)
                try emitExpr(c.elseExpr)
                emitter.patchJump(at: jumpOverElseIndex, to: emitter.currentOffset())
            case .assign(let a):
                if case .member(let m) = a.target,
                   case .named(let typeName) = (exprType(m.base) ?? .unknown),
                   let f = symbols.lookupField(typeName: typeName, name: m.name) {
                    try emitExpr(m.base)
                    try emitExpr(a.value)
                    emitter.emit(.storeField(UInt16(f.index)))
                    emitter.emit(.pushNil)
                } else if case .index(let i) = a.target {
                    try emitExpr(i.base)
                    try emitExpr(i.index)
                    try emitExpr(a.value)
                    emitter.emit(.storeIndex)
                    emitter.emit(.pushNil)
                } else {
                    try emitExpr(a.value)
                    if case .identifier(let name, _) = a.target {
                        if let existing = locals[name] {
                            emitter.emit(.storeLocal(existing.slot))
                            emitter.emit(.loadLocal(existing.slot))
                        } else if let builder = builderBinding(),
                                  let field = symbols.lookupField(typeName: builder.typeName, name: name) {
                            emitter.emit(.loadLocal(builder.slot))
                            emitter.emit(.swap)
                            emitter.emit(.storeField(UInt16(field.index)))
                            emitter.emit(.pushNil)
                        } else if let typeName = implicitSelfTypeName,
                                  let selfBinding = locals["self"],
                                  let field = symbols.lookupField(typeName: typeName, name: name) {
                            emitter.emit(.loadLocal(selfBinding.slot))
                            emitter.emit(.swap)
                            emitter.emit(.storeField(UInt16(field.index)))
                            emitter.emit(.pushNil)
                        } else if symbols.globals[name] != nil {
                            emitter.emit(.storeGlobalSymbol(name))
                            emitter.emit(.loadGlobalSymbol(name))
                        } else {
                            let slot = allocLocal(name, type: exprType(a.value) ?? .unknown)
                            emitter.emit(.storeLocal(slot))
                            emitter.emit(.loadLocal(slot))
                        }
                    } else {
                        emitter.emit(.pop)
                        emitter.emit(.pushNil)
                    }
                }
            case .call(let c):
                if case .identifier(let name, _) = c.callee, name == "print" {
                    // Compiler intrinsic: print(x) pops x and prints, then pushes nil.
                    guard c.arguments.count == 1 else {
                        emitter.emit(.pushNil)
                        return
                    }
                    try emitExpr(c.arguments[0].value)
                    emitter.emit(.print)
                    emitter.emit(.pushNil)
                } else if let (_, enumCase) = enumConstructorInfo(c.callee) {
                    for argument in c.arguments {
                        try emitExpr(argument.value)
                    }
                    if enumCase.associatedValues.isEmpty {
                        emitter.emit(.pushInt(enumCase.tag))
                    } else {
                        emitter.emit(.makeEnum(tag: UInt16(enumCase.tag), valueCount: UInt8(enumCase.associatedValues.count)))
                    }
                } else if case .identifier(let typeName, _) = c.callee, let fieldMap = symbols.fields[typeName] {
                    // Type constructor: TypeName(field1:..., field2:...)
                    let fieldCount = fieldMap.count
                    var fieldTypes: [KiraType] = Array(repeating: .unknown, count: fieldCount)
                    for info in fieldMap.values {
                        fieldTypes[info.index] = info.type
                    }

                    emitter.emit(.newTypedObject(typeName: typeName, fieldCount: UInt16(fieldCount)))

                    var argsByIndex: [Expr?] = Array(repeating: nil, count: fieldCount)
                    var used: Set<Int> = []
                    for (pos, a) in c.arguments.enumerated() {
                        if let label = a.label, let info = fieldMap[label] {
                            used.insert(info.index)
                            argsByIndex[info.index] = a.value
                        } else if a.label == nil, pos < fieldCount, !used.contains(pos) {
                            used.insert(pos)
                            argsByIndex[pos] = a.value
                        }
                    }

                    for i in 0..<fieldCount {
                        emitter.emit(.dup)
                        let defaultExpr = i < (instanceFieldInitializers[typeName]?.count ?? 0)
                            ? instanceFieldInitializers[typeName]![i]
                            : nil
                        try emitExpr(argsByIndex[i] ?? defaultExpr ?? .nilLiteral(c.range), coercedTo: fieldTypes[i])
                        emitter.emit(.storeField(UInt16(i)))
                    }
                    if let trailing = c.trailingBlock {
                        try emitBuilderBlock(trailing, typeName: typeName)
                    }
                } else if case .identifier(let name, _) = c.callee, name == "ffi_callback0" {
                    // Compiler intrinsic: ffi_callback0("functionName") -> CPointer<CVoid>
                    guard c.arguments.count == 1 else {
                        emitter.emit(.pushNil)
                        return
                    }
                    try emitExpr(c.arguments[0].value)
                    emitter.emit(.ffiCallback0)
                } else if case .identifier(let name, _) = c.callee, name == "ffi_callback1_i32" {
                    // Compiler intrinsic: ffi_callback1_i32("functionName") -> CPointer<CVoid>
                    guard c.arguments.count == 1 else {
                        emitter.emit(.pushNil)
                        return
                    }
                    try emitExpr(c.arguments[0].value)
                    emitter.emit(.ffiCallback1I32)
                } else if case .identifier(let name, _) = c.callee, name == "Color", exprType(e) == .named("Color") {
                    // Compiler intrinsic: Color(r:g:b:a:) -> Color.
                    // Expects exactly 4 Float arguments.
                    guard c.arguments.count == 4 else {
                        emitter.emit(.pushNil)
                        return
                    }
                    for a in c.arguments { try emitExpr(a.value) }
                    emitter.emit(.makeColor)
                } else if case .identifier(let name, _) = c.callee, name == "Float" {
                    guard c.arguments.count == 1 else {
                        emitter.emit(.pushNil)
                        return
                    }
                    try emitExpr(c.arguments[0].value)
                    if (exprType(c.arguments[0].value) ?? .unknown) == .int {
                        emitter.emit(.intToFloat)
                    }
                } else if case .identifier(let name, _) = c.callee, name == "Int" {
                    guard c.arguments.count == 1 else {
                        emitter.emit(.pushNil)
                        return
                    }
                    try emitExpr(c.arguments[0].value)
                    let argumentType = exprType(c.arguments[0].value) ?? .unknown
                    if argumentType == .float || argumentType == .double {
                        emitter.emit(.floatToInt)
                    }
                } else if case .member(let m) = c.callee,
                          case .array = (exprType(m.base) ?? .unknown),
                          m.name == "append" {
                    guard c.arguments.count == 1 else {
                        emitter.emit(.pushNil)
                        return
                    }
                    try emitExpr(m.base)
                    try emitExpr(c.arguments[0].value)
                    emitter.emit(.arrayAppend)
                } else if case .member(let m) = c.callee,
                          case .named(let protocolName) = (exprType(m.base) ?? .unknown),
                          symbols.lookupProtocolRequirement(protocolName: protocolName, name: m.name) != nil {
                    try emitExpr(m.base)
                    for argument in c.arguments {
                        try emitExpr(argument.value)
                    }
                    emitter.emit(.callProtocolMethod(m.name, argCount: UInt8(c.arguments.count)))
                } else if case .identifier(let name, _) = c.callee,
                          let builder = builderBinding(),
                          let method = symbols.lookupMethod(typeName: builder.typeName, name: name) {
                    emitter.emit(.loadGlobalSymbol(method.loweredName))
                    emitter.emit(.loadLocal(builder.slot))
                    let expectedParams: [KiraType]
                    if case .function(let params, _) = method.type {
                        expectedParams = params
                    } else {
                        expectedParams = []
                    }
                    for (index, a) in c.arguments.enumerated() {
                        let expectedArg = index < expectedParams.count ? expectedParams[index] : nil
                        try emitExpr(a.value, coercedTo: expectedArg)
                    }
                    var callArgCount = c.arguments.count + 1
                    if let trailing = c.trailingBlock,
                       let builderType = builderParamTypeName(params: expectedParams, explicitArgumentCount: c.arguments.count, symbols: symbols) {
                        try emitDefaultObject(typeName: builderType)
                        try emitBuilderBlock(trailing, typeName: builderType)
                        callArgCount += 1
                    }
                    emitter.emit(.call(argCount: UInt8(callArgCount)))
                } else if case .identifier(let name, _) = c.callee,
                          let typeName = implicitSelfTypeName,
                          let selfBinding = locals["self"],
                          let method = symbols.lookupMethod(typeName: typeName, name: name) {
                    emitter.emit(.loadGlobalSymbol(method.loweredName))
                    emitter.emit(.loadLocal(selfBinding.slot))
                    let expectedParams: [KiraType]
                    if case .function(let params, _) = method.type {
                        expectedParams = params
                    } else {
                        expectedParams = []
                    }
                    for (index, a) in c.arguments.enumerated() {
                        let expectedArg = index < expectedParams.count ? expectedParams[index] : nil
                        try emitExpr(a.value, coercedTo: expectedArg)
                    }
                    var callArgCount = c.arguments.count + 1
                    if let trailing = c.trailingBlock,
                       let builderType = builderParamTypeName(params: expectedParams, explicitArgumentCount: c.arguments.count, symbols: symbols) {
                        try emitDefaultObject(typeName: builderType)
                        try emitBuilderBlock(trailing, typeName: builderType)
                        callArgCount += 1
                    }
                    emitter.emit(.call(argCount: UInt8(callArgCount)))
                } else if case .member(let m) = c.callee,
                          case .named(let typeName) = (exprType(m.base) ?? .unknown),
                          let method = symbols.lookupMethod(typeName: typeName, name: m.name) {
                    emitter.emit(.loadGlobalSymbol(method.loweredName))
                    try emitExpr(m.base)
                    let expectedParams: [KiraType]
                    if case .function(let params, _) = method.type {
                        expectedParams = params
                    } else {
                        expectedParams = []
                    }
                    for (index, a) in c.arguments.enumerated() {
                        let expectedArg = index < expectedParams.count ? expectedParams[index] : nil
                        try emitExpr(a.value, coercedTo: expectedArg)
                    }
                    var callArgCount = c.arguments.count + 1
                    if let trailing = c.trailingBlock,
                       let builderType = builderParamTypeName(params: expectedParams, explicitArgumentCount: c.arguments.count, symbols: symbols) {
                        try emitDefaultObject(typeName: builderType)
                        try emitBuilderBlock(trailing, typeName: builderType)
                        callArgCount += 1
                    }
                    emitter.emit(.call(argCount: UInt8(callArgCount)))
                } else {
                    let expectedParams: [KiraType]
                    if case .identifier(let name, _) = c.callee,
                       symbols.functions[name]?.isExtern == true,
                       case .function(let params, _) = exprType(c.callee) ?? symbols.lookupValue(name) ?? .unknown {
                        expectedParams = params
                    } else {
                        expectedParams = []
                    }

                    try emitExpr(c.callee)
                    for (index, a) in c.arguments.enumerated() {
                        let expectedArg = index < expectedParams.count ? expectedParams[index] : nil
                        try emitExpr(a.value, coercedTo: expectedArg)
                    }
                    if let trailing = c.trailingBlock,
                       let builderType = builderParamTypeName(params: expectedParams, explicitArgumentCount: c.arguments.count, symbols: symbols) {
                        try emitDefaultObject(typeName: builderType)
                        try emitBuilderBlock(trailing, typeName: builderType)
                    }
                    emitter.emit(.call(argCount: UInt8(c.arguments.count)))
                }
                if let trailing = c.trailingBlock,
                   builderParamTypeName(params: {
                       if case .identifier(let name, _) = c.callee,
                          let builder = builderBinding(),
                          let method = symbols.lookupMethod(typeName: builder.typeName, name: name),
                          case .function(let params, _) = method.type {
                           return params
                       }
                       if case .member(let m) = c.callee,
                          case .named(let typeName) = (exprType(m.base) ?? .unknown),
                          let method = symbols.lookupMethod(typeName: typeName, name: m.name),
                          case .function(let params, _) = method.type {
                           return params
                       }
                       if case .function(let params, _) = (exprType(c.callee) ?? .unknown) {
                           return params
                       }
                       return []
                   }(), explicitArgumentCount: c.arguments.count, symbols: symbols) == nil,
                   case .named(let typeName) = (exprType(e) ?? .unknown),
                   symbols.fields[typeName] != nil {
                    try emitBuilderBlock(trailing, typeName: typeName)
                }
            case .member(let m):
                if case .identifier(let enumName, _) = m.base,
                   let enumCase = symbols.lookupEnumCase(typeName: enumName, name: m.name),
                   enumCase.associatedValues.isEmpty {
                    emitter.emit(.pushInt(enumCase.tag))
                } else if (exprType(m.base) ?? .unknown) == .string, m.name == "count" {
                    try emitExpr(m.base)
                    emitter.emit(.stringLength)
                } else if case .array = (exprType(m.base) ?? .unknown), m.name == "count" {
                    try emitExpr(m.base)
                    emitter.emit(.arrayLength)
                } else if case .identifier(let typeName, _) = m.base,
                          symbols.lookupStaticField(typeName: typeName, name: m.name) != nil {
                    emitter.emit(.loadGlobalSymbol(loweredStaticFieldName(typeName: typeName, fieldName: m.name)))
                } else if case .identifier(let typeName, _) = m.base,
                          let method = symbols.lookupStaticMethod(typeName: typeName, name: m.name) {
                    emitter.emit(.loadGlobalSymbol(method.loweredName))
                } else if case .named(let typeName) = (exprType(m.base) ?? .unknown),
                   let f = symbols.lookupField(typeName: typeName, name: m.name) {
                    try emitExpr(m.base)
                    emitter.emit(.loadField(UInt16(f.index)))
                } else if case .named(let typeName) = (exprType(m.base) ?? .unknown),
                          let method = symbols.lookupMethod(typeName: typeName, name: m.name) {
                    emitter.emit(.loadGlobalSymbol(method.loweredName))
                } else {
                    _ = m.base
                    emitter.emit(.loadGlobalSymbol(m.name))
                }
            case .index(let i):
                try emitExpr(i.base)
                try emitExpr(i.index)
                emitter.emit(.loadIndex)
            case .shaderMacro(let sm):
                emitter.emit(.pushString("shader:\(sm.functionName)"))
            }
        }

        func emitBuilderBlock(_ block: BlockStmt, typeName: String) throws {
            let slot = allocLocal("__builder_\(nextLocal)", type: .named(typeName))
            emitter.emit(.storeLocal(slot))
            builderStack.append(.init(slot: slot, typeName: typeName))
            for statement in block.statements {
                try emitStmt(statement)
            }
            _ = builderStack.popLast()
            emitter.emit(.loadLocal(slot))
        }

        func emitStmt(_ s: Stmt) throws {
            switch s {
            case .variable(let vd):
                try emitExpr(vd.initializer)
                let finalType = typeInfo.varTypes[vd.range] ?? exprType(vd.initializer) ?? .unknown
                let initType = exprType(vd.initializer) ?? .unknown
                if (finalType == .float || finalType == .double), initType == .int, isIntLiteral(vd.initializer) {
                    emitter.emit(.intToFloat)
                }
                let slot = allocLocal(vd.name, type: finalType)
                emitter.emit(.storeLocal(slot))
            case .return(let rs):
                if let v = rs.value {
                    try emitExpr(v)
                    let got = exprType(v) ?? .unknown
                    if (ret == .float || ret == .double), got == .int, isIntLiteral(v) {
                        emitter.emit(.intToFloat)
                    }
                } else {
                    emitter.emit(.pushNil)
                }
                emitter.emit(.ret)
            case .expr(let e):
                try emitExpr(e)
                emitter.emit(.pop)
            case .if(let ifs):
                try emitExpr(ifs.condition)
                let jumpIfFalseIndex = emitter.emitPlaceholderJumpIfFalse()
                for st in ifs.thenBlock.statements { try emitStmt(st) }
                if let eb = ifs.elseBlock {
                    let jumpOverElseIndex = emitter.emitPlaceholderJump()
                    emitter.patchJump(at: jumpIfFalseIndex, to: emitter.currentOffset())
                    for st in eb.statements { try emitStmt(st) }
                    emitter.patchJump(at: jumpOverElseIndex, to: emitter.currentOffset())
                } else {
                    emitter.patchJump(at: jumpIfFalseIndex, to: emitter.currentOffset())
                }
            case .while(let whileStmt):
                let loopStart = emitter.currentOffset()
                try emitExpr(whileStmt.condition)
                let jumpOutIndex = emitter.emitPlaceholderJumpIfFalse()
                for st in whileStmt.body.statements {
                    try emitStmt(st)
                }
                let loopBackIndex = emitter.emitPlaceholderJump()
                emitter.patchJump(at: loopBackIndex, to: loopStart)
                emitter.patchJump(at: jumpOutIndex, to: emitter.currentOffset())
            case .match(let matchStmt):
                let matchSlot = allocLocal("__match_\(nextLocal)", type: exprType(matchStmt.value) ?? .unknown)
                try emitExpr(matchStmt.value)
                emitter.emit(.storeLocal(matchSlot))
                var endJumps: [Int] = []
                let matchedEnumName: String? = {
                    if case .named(let enumName)? = exprType(matchStmt.value) { return enumName }
                    return nil
                }()
                for matchCase in matchStmt.cases {
                    guard let matchedEnumName,
                          let enumCase = symbols.lookupEnumCase(typeName: matchedEnumName, name: matchCase.pattern.variantName) else {
                        continue
                    }
                    emitter.emit(.loadLocal(matchSlot))
                    emitter.emit(.matchEnum(tag: UInt16(enumCase.tag)))
                    let nextCaseJump = emitter.emitPlaceholderJumpIfFalse()
                    for (bindingIndex, binding) in matchCase.pattern.bindings.enumerated() {
                        let bindingType = bindingIndex < enumCase.associatedValues.count
                            ? enumCase.associatedValues[bindingIndex].type
                            : .unknown
                        let slot = allocLocal(binding, type: bindingType)
                        emitter.emit(.loadLocal(matchSlot))
                        emitter.emit(.getEnumField(index: UInt8(bindingIndex)))
                        emitter.emit(.storeLocal(slot))
                    }
                    for statement in matchCase.body.statements {
                        try emitStmt(statement)
                    }
                    endJumps.append(emitter.emitPlaceholderJump())
                    emitter.patchJump(at: nextCaseJump, to: emitter.currentOffset())
                }
                for jump in endJumps {
                    emitter.patchJump(at: jump, to: emitter.currentOffset())
                }
            }
        }

        for st in fn.body.statements {
            try emitStmt(st)
        }
        // Implicit return nil if missing.
        if !emitter.instructions.contains(.ret) {
            emitter.emit(.pushNil)
            emitter.emit(.ret)
        }

        return KiraIRFunction(
            name: loweredName,
            params: params,
            returnType: ret,
            localCount: Int(nextLocal),
            maxStackDepth: emitter.maxDepth,
            instructions: emitter.instructions,
            executionMode: mode
        )
    }
}

private struct StackEmitter {
    var instructions: [KiraIRInst] = []
    var depth: Int = 0
    var maxDepth: Int = 0

    mutating func emit(_ inst: KiraIRInst) {
        instructions.append(inst)
        adjustDepth(inst)
        if depth > maxDepth { maxDepth = depth }
    }

    mutating func emitPlaceholderJumpIfFalse() -> Int {
        let idx = instructions.count
        emit(.jumpIfFalse(0))
        return idx
    }

    mutating func emitPlaceholderJump() -> Int {
        let idx = instructions.count
        emit(.jump(0))
        return idx
    }

    mutating func patchJump(at index: Int, to targetOffset: Int) {
        let from = index + 1
        let delta = targetOffset - from
        let d16 = Int16(clamping: delta)
        switch instructions[index] {
        case .jumpIfFalse:
            instructions[index] = .jumpIfFalse(d16)
        case .jumpIfTrue:
            instructions[index] = .jumpIfTrue(d16)
        case .jump:
            instructions[index] = .jump(d16)
        default:
            break
        }
    }

    func currentOffset() -> Int { instructions.count }

    func currentDepth() -> Int { depth }

    mutating func restoreDepth(_ value: Int) {
        depth = max(0, value)
    }

    mutating func adjustDepth(_ inst: KiraIRInst) {
        switch inst {
        case .pushInt, .pushFloat, .pushString, .pushBool, .pushNil, .loadLocal, .loadGlobalSymbol:
            depth += 1
        case .storeLocal, .storeGlobalSymbol:
            depth -= 1
        case .newObject, .newTypedObject, .newArray:
            depth += 1
        case .makeEnum(_, let valueCount):
            depth -= Int(valueCount)
            depth += 1
        case .makeFFIArray(let count, _):
            depth -= Int(count)
            depth += 1
        case .arrayLength:
            break
        case .arrayAppend:
            depth -= 1
        case .loadField:
            break
        case .storeField:
            depth -= 2
        case .loadIndex:
            depth -= 1
        case .storeIndex:
            depth -= 3
        case .matchEnum:
            break
        case .getEnumField:
            break
        case .stringLength:
            break
        case .pop:
            depth -= 1
        case .dup:
            depth += 1
        case .swap:
            break
        case .addInt, .subInt, .mulInt, .divInt, .modInt,
             .addFloat, .subFloat, .mulFloat, .divFloat,
             .eqInt, .eqFloat, .ltInt, .ltFloat, .gtInt, .gtFloat,
             .andBool, .orBool:
            depth -= 1
        case .negInt, .negFloat, .notBool, .intToFloat, .floatToInt:
            break
        case .jump, .jumpIfTrue, .jumpIfFalse:
            if case .jump = inst {
                break
            }
            depth -= 1
        case .call(let argCount):
            depth -= Int(argCount) // args
            depth -= 1 // callee
            depth += 1 // return
        case .callProtocolMethod(_, let argCount):
            depth -= Int(argCount)
            depth -= 1
            depth += 1
        case .ffiLoad:
            // Pops: libName, symbolName; pushes native pointer.
            depth -= 1
        case .ffiCall(let argCount, _, _):
            // Pops: args + pointer; pushes return.
            depth -= Int(argCount) // args
            depth -= 1 // pointer
            depth += 1 // return
        case .ffiCallback0:
            // Pops function name string; pushes native pointer.
            break
        case .ffiCallback1I32:
            // Pops function name string; pushes native pointer.
            break
        case .print:
            // Pops value and pushes nothing; by convention, callers can push nil to represent Void.
            depth -= 1
        case .makeColor:
            // Pops 4 floats and pushes one reference.
            depth -= 3
        case .ret:
            depth = 0
        }
        if depth < 0 { depth = 0 }
    }
}

private func computeMaxStack(_ insts: [KiraIRInst]) -> Int {
    var depth = 0
    var maxDepth = 0
    for inst in insts {
        switch inst {
        case .pushInt, .pushFloat, .pushString, .pushBool, .pushNil, .loadLocal, .loadGlobalSymbol:
            depth += 1
        case .storeLocal, .storeGlobalSymbol:
            depth -= 1
        case .newObject, .newTypedObject, .newArray:
            depth += 1
        case .makeEnum(_, let valueCount):
            depth -= Int(valueCount)
            depth += 1
        case .makeFFIArray(let count, _):
            depth -= Int(count)
            depth += 1
        case .arrayLength:
            break
        case .arrayAppend:
            depth -= 1
        case .loadField:
            break
        case .storeField:
            depth -= 2
        case .loadIndex:
            depth -= 1
        case .storeIndex:
            depth -= 3
        case .matchEnum:
            break
        case .getEnumField:
            break
        case .stringLength:
            break
        case .pop:
            depth -= 1
        case .dup:
            depth += 1
        case .swap:
            break
        case .addInt, .subInt, .mulInt, .divInt, .modInt,
             .addFloat, .subFloat, .mulFloat, .divFloat,
             .eqInt, .eqFloat, .ltInt, .ltFloat, .gtInt, .gtFloat,
             .andBool, .orBool:
            depth -= 1
        case .negInt, .negFloat, .notBool, .intToFloat, .floatToInt:
            break
        case .jump, .jumpIfTrue, .jumpIfFalse:
            if case .jump = inst { break }
            depth -= 1
        case .call(let argCount):
            depth -= Int(argCount)
            depth -= 1
            depth += 1
        case .callProtocolMethod(_, let argCount):
            depth -= Int(argCount)
            depth -= 1
            depth += 1
        case .ffiLoad:
            depth -= 1
        case .ffiCall(let argCount, _, _):
            depth -= Int(argCount)
            depth -= 1
            depth += 1
        case .ffiCallback0:
            break
        case .ffiCallback1I32:
            break
        case .print:
            depth -= 1
        case .makeColor:
            depth -= 3
        case .ret:
            depth = 0
        }
        if depth < 0 { depth = 0 }
        if depth > maxDepth { maxDepth = depth }
    }
    return maxDepth
}
