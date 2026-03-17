import Foundation

public enum BytecodeEmitError: Error, CustomStringConvertible, Sendable {
    case unknownGlobalSymbol(String)
    case jumpOutOfRange

    public var description: String {
        switch self {
        case .unknownGlobalSymbol(let s): return "error: unknown global symbol '\(s)'"
        case .jumpOutOfRange: return "error: jump offset out of range"
        }
    }
}

public struct BytecodeEmitter: Sendable {
    public init() {}

    public func emit(module: KiraIRModule) throws -> Data {
        let functionNames = module.functions.map(\.name)
        let globalIndex: [String: UInt16] = Dictionary(uniqueKeysWithValues: functionNames.enumerated().map { ($0.element, UInt16($0.offset)) })

        var intConstants: [Int64] = []
        var floatConstants: [Double] = []
        var strings: [String] = []
        var stringIndex: [String: UInt16] = [:]

        func internString(_ s: String) -> UInt16 {
            if let i = stringIndex[s] { return i }
            let i = UInt16(strings.count)
            strings.append(s)
            stringIndex[s] = i
            return i
        }

        func internInt(_ v: Int64) -> UInt16 {
            if let i = intConstants.firstIndex(of: v) { return UInt16(i) }
            intConstants.append(v)
            return UInt16(intConstants.count - 1)
        }

        func internFloat(_ v: Double) -> UInt16 {
            if let i = floatConstants.firstIndex(of: v) { return UInt16(i) }
            floatConstants.append(v)
            return UInt16(floatConstants.count - 1)
        }

        struct EncodedOp {
            var op: Instruction
            var operands: [UInt8]
            var irIndex: Int
        }

        func encodeFunction(_ fn: KiraIRFunction) throws -> (nameIndex: UInt16, paramCount: UInt8, localCount: UInt16, maxStack: UInt16, code: [UInt8]) {
            _ = internString(fn.name)
            let nameIndex = stringIndex[fn.name]!

            var ops: [EncodedOp] = []

            func append(_ op: Instruction, _ bytes: [UInt8] = [], irIndex: Int) {
                ops.append(.init(op: op, operands: bytes, irIndex: irIndex))
            }

            for (i, inst) in fn.instructions.enumerated() {
                switch inst {
                case .pushInt(let v):
                    let idx = internInt(v)
                    append(.push_int, [UInt8(idx >> 8), UInt8(idx & 0xff)], irIndex: i)
                case .pushFloat(let v):
                    let idx = internFloat(v)
                    append(.push_float, [UInt8(idx >> 8), UInt8(idx & 0xff)], irIndex: i)
                case .pushString(let s):
                    let idx = internString(s)
                    append(.push_string, [UInt8(idx >> 8), UInt8(idx & 0xff)], irIndex: i)
                case .pushBool(let b):
                    append(b ? .push_bool_true : .push_bool_false, [], irIndex: i)
                case .pushNil:
                    append(.push_nil, [], irIndex: i)
                case .pop:
                    append(.pop, [], irIndex: i)
                case .dup:
                    append(.dup, [], irIndex: i)
                case .swap:
                    append(.swap, [], irIndex: i)
                case .loadLocal(let slot):
                    append(.load_local, [slot], irIndex: i)
                case .storeLocal(let slot):
                    append(.store_local, [slot], irIndex: i)
                case .loadGlobalSymbol(let name):
                    guard let sym = globalIndex[name] else { throw BytecodeEmitError.unknownGlobalSymbol(name) }
                    append(.load_global, [UInt8(sym >> 8), UInt8(sym & 0xff)], irIndex: i)
                case .storeGlobalSymbol(let name):
                    guard let sym = globalIndex[name] else { throw BytecodeEmitError.unknownGlobalSymbol(name) }
                    append(.store_global, [UInt8(sym >> 8), UInt8(sym & 0xff)], irIndex: i)
                case .newObject(let fieldCount):
                    append(.new_object, [UInt8(fieldCount >> 8), UInt8(fieldCount & 0xff)], irIndex: i)
                case .loadField(let fieldIndex):
                    append(.load_field, [UInt8(fieldIndex >> 8), UInt8(fieldIndex & 0xff)], irIndex: i)
                case .storeField(let fieldIndex):
                    append(.store_field, [UInt8(fieldIndex >> 8), UInt8(fieldIndex & 0xff)], irIndex: i)
                case .addInt: append(.add_int, [], irIndex: i)
                case .subInt: append(.sub_int, [], irIndex: i)
                case .mulInt: append(.mul_int, [], irIndex: i)
                case .divInt: append(.div_int, [], irIndex: i)
                case .modInt: append(.mod_int, [], irIndex: i)
                case .negInt: append(.neg_int, [], irIndex: i)
                case .addFloat: append(.add_float, [], irIndex: i)
                case .subFloat: append(.sub_float, [], irIndex: i)
                case .mulFloat: append(.mul_float, [], irIndex: i)
                case .divFloat: append(.div_float, [], irIndex: i)
                case .negFloat: append(.neg_float, [], irIndex: i)
                case .intToFloat: append(.int_to_float, [], irIndex: i)
                case .floatToInt: append(.float_to_int, [], irIndex: i)
                case .eqInt: append(.eq_int, [], irIndex: i)
                case .eqFloat: append(.eq_float, [], irIndex: i)
                case .ltInt: append(.lt_int, [], irIndex: i)
                case .ltFloat: append(.lt_float, [], irIndex: i)
                case .gtInt: append(.gt_int, [], irIndex: i)
                case .gtFloat: append(.gt_float, [], irIndex: i)
                case .andBool: append(.and_bool, [], irIndex: i)
                case .orBool: append(.or_bool, [], irIndex: i)
                case .notBool: append(.not_bool, [], irIndex: i)
                case .jump(let delta):
                    let u = UInt16(bitPattern: delta)
                    append(.jump, [UInt8(u >> 8), UInt8(u & 0xff)], irIndex: i)
                case .jumpIfTrue(let delta):
                    let u = UInt16(bitPattern: delta)
                    append(.jump_if_true, [UInt8(u >> 8), UInt8(u & 0xff)], irIndex: i)
                case .jumpIfFalse(let delta):
                    let u = UInt16(bitPattern: delta)
                    append(.jump_if_false, [UInt8(u >> 8), UInt8(u & 0xff)], irIndex: i)
                case .call(let argCount):
                    append(.call, [argCount], irIndex: i)
                case .ffiLoad:
                    append(.ffi_load, [], irIndex: i)
                case .ffiCall(let argCount, let returnType, let argumentTypes):
                    var bytes: [UInt8] = [argCount]
                    bytes.append(contentsOf: returnType)
                    for a in argumentTypes { bytes.append(contentsOf: a) }
                    append(.ffi_call, bytes, irIndex: i)
                case .ffiCallback0:
                    append(.ffi_callback0, [], irIndex: i)
                case .ffiCallback1I32:
                    append(.ffi_callback1_i32, [], irIndex: i)
                case .print:
                    append(.print, [], irIndex: i)
                case .makeColor:
                    append(.make_color, [], irIndex: i)
                case .ret:
                    append(.ret, [], irIndex: i)
                }
            }

            // Patch jump operands from IR-relative instruction offsets to byte-relative offsets.
            // IR jump delta is relative to the next IR instruction.
            var byteOffsets: [Int] = Array(repeating: 0, count: ops.count + 1)
            for i in 0..<ops.count {
                byteOffsets[i + 1] = byteOffsets[i] + 1 + ops[i].operands.count
            }

            func patchJump(_ i: Int, irDelta: Int16) throws {
                let fromIrNext = i + 1
                let toIr = fromIrNext + Int(irDelta)
                guard toIr >= 0 && toIr <= ops.count else { throw BytecodeEmitError.jumpOutOfRange }
                let fromByteNext = byteOffsets[fromIrNext]
                let toByte = byteOffsets[toIr]
                let deltaBytes = toByte - fromByteNext
                let d16 = Int16(clamping: deltaBytes)
                let hi = UInt8(bitPattern: Int8(d16 >> 8))
                let lo = UInt8(bitPattern: Int8(d16 & 0xff))
                ops[i].operands = [hi, lo]
            }

            for i in 0..<ops.count {
                switch ops[i].op {
                case .jump, .jump_if_true, .jump_if_false, .jump_if_nil, .unwrap_or_jump:
                    if ops[i].operands.count == 2 {
                        let hi = Int16(Int8(bitPattern: ops[i].operands[0]))
                        let lo = Int16(Int8(bitPattern: ops[i].operands[1]))
                        let irDelta = (hi << 8) | (lo & 0xff)
                        try patchJump(i, irDelta: irDelta)
                    }
                default:
                    break
                }
            }

            var code: [UInt8] = []
            code.reserveCapacity(byteOffsets.last ?? 0)
            for o in ops {
                code.append(o.op.rawValue)
                code.append(contentsOf: o.operands)
            }
            return (nameIndex, UInt8(fn.params.count), UInt16(fn.localCount), UInt16(fn.maxStackDepth), code)
        }

        var encodedFunctions: [(UInt16, UInt8, UInt16, UInt16, [UInt8])] = []
        encodedFunctions.reserveCapacity(module.functions.count)
        for fn in module.functions {
            encodedFunctions.append(try encodeFunction(fn))
        }

        // Build final binary.
        var data = Data()
        func appendU32(_ v: UInt32) {
            var be = v.bigEndian
            withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
        }
        func appendU16(_ v: UInt16) {
            var be = v.bigEndian
            withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
        }
        func appendU8(_ v: UInt8) { data.append(v) }
        func appendI64(_ v: Int64) {
            var be = v.bigEndian
            withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
        }
        func appendF64(_ v: Double) {
            var raw = v.bitPattern.bigEndian
            withUnsafeBytes(of: &raw) { data.append(contentsOf: $0) }
        }

        // Header (32 bytes).
        appendU32(0x4B495242) // "KIRB"
        appendU32(1) // version
        appendU32(0) // flags
        appendU32(UInt32(encodedFunctions.count))
        data.append(contentsOf: Array(repeating: 0, count: 16))

        // Constant pools.
        appendU32(UInt32(intConstants.count))
        for v in intConstants { appendI64(v) }
        appendU32(UInt32(floatConstants.count))
        for v in floatConstants { appendF64(v) }

        // String table.
        appendU32(UInt32(strings.count))
        for s in strings {
            let bytes = Array(s.utf8)
            appendU32(UInt32(bytes.count))
            data.append(contentsOf: bytes)
        }

        // Function table.
        for (nameIndex, paramCount, localCount, maxStack, code) in encodedFunctions {
            appendU16(nameIndex)
            appendU8(paramCount)
            appendU16(localCount)
            appendU16(maxStack)
            appendU32(UInt32(code.count))
            data.append(contentsOf: code)
        }

        return data
    }
}
