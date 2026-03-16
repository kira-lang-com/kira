import Foundation

public struct IRBuilder {
    public init() {}

    public func build(from typed: TypedModule) throws -> KiraIRModule {
        let fns: [KiraIRFunction] = try typed.ast.declarations.compactMap { decl in
            guard case .function(let fn) = decl else { return nil }
            return try buildFunction(fn: fn, symbols: typed.symbols, typeInfo: typed.typeInfo)
        }
        return KiraIRModule(functions: fns)
    }

    private func buildFunction(fn: FunctionDecl, symbols: SymbolTable, typeInfo: TypeInfo) throws -> KiraIRFunction {
        let fnSym = symbols.functions[fn.name]!
        let mode: KiraIRFunction.ExecutionMode
        switch fnSym.executionMode {
        case .auto: mode = .auto
        case .native: mode = .native
        case .runtime: mode = .runtime
        }
        guard case .function(let params, let ret) = fnSym.type else {
            return KiraIRFunction(name: fn.name, params: [], returnType: .void, localCount: 0, maxStackDepth: 0, instructions: [], executionMode: mode)
        }

        var emitter = StackEmitter()

        // Allocate locals: params first.
        struct LocalBinding {
            var slot: UInt8
            var type: KiraType
        }
        var locals: [String: LocalBinding] = [:]
        var nextLocal: UInt8 = 0
        for (i, p) in fn.parameters.enumerated() {
            locals[p.name] = .init(slot: nextLocal, type: params[i])
            nextLocal &+= 1
        }

        func allocLocal(_ name: String, type: KiraType) -> UInt8 {
            if let existing = locals[name] { return existing.slot }
            let slot = nextLocal
            locals[name] = .init(slot: slot, type: type)
            nextLocal &+= 1
            return slot
        }

        func exprType(_ e: Expr) -> KiraType? { typeInfo.exprTypes[e.range] }

        func isIntLiteral(_ e: Expr) -> Bool {
            if case .intLiteral = e { return true }
            return false
        }

        func emitExpr(_ e: Expr) throws {
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
            case .identifier(let name, _):
                if let binding = locals[name] {
                    emitter.emit(.loadLocal(binding.slot))
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
            case .assign(let a):
                try emitExpr(a.value)
                if case .identifier(let name, _) = a.target {
                    let slot = allocLocal(name, type: exprType(a.value) ?? .unknown)
                    emitter.emit(.storeLocal(slot))
                    emitter.emit(.loadLocal(slot))
                } else {
                    emitter.emit(.pop)
                    emitter.emit(.pushNil)
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
                } else if case .identifier(let name, _) = c.callee, name == "Color", exprType(e) == .named("Color") {
                    // Compiler intrinsic: Color(r:g:b:a:) -> Color.
                    // Expects exactly 4 Float arguments.
                    guard c.arguments.count == 4 else {
                        emitter.emit(.pushNil)
                        return
                    }
                    for a in c.arguments { try emitExpr(a.value) }
                    emitter.emit(.makeColor)
                } else {
                    try emitExpr(c.callee)
                    for a in c.arguments { try emitExpr(a.value) }
                    emitter.emit(.call(argCount: UInt8(c.arguments.count)))
                }
            case .member(let m):
                _ = m.base
                emitter.emit(.loadGlobalSymbol(m.name))
            case .shaderMacro(let sm):
                emitter.emit(.pushString("shader:\(sm.functionName)"))
            }
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
            name: fn.name,
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

    mutating func adjustDepth(_ inst: KiraIRInst) {
        switch inst {
        case .pushInt, .pushFloat, .pushString, .pushBool, .pushNil, .loadLocal, .loadGlobalSymbol:
            depth += 1
        case .storeLocal, .storeGlobalSymbol:
            depth -= 1
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
