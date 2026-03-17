import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if canImport(Clibffi)
import Clibffi
#endif

// MARK: - FFI callback support

#if canImport(Clibffi)

private enum FFICallbackTLS {
    // Current VM set while executing an `ffi_call` that may trigger native callbacks.
    // Assumes single-threaded execution (which matches the current VM design).
    static var currentVM: VirtualMachine?
}

private final class FFICallback0Context {
    let functionName: String
    init(functionName: String) {
        self.functionName = functionName
    }
}

private struct FFICallback0KeepAlive {
    let closurePtr: UnsafeMutableRawPointer
    let codePtr: UnsafeMutableRawPointer
    let userData: UnsafeMutableRawPointer

    func destroy() {
        Unmanaged<FFICallback0Context>.fromOpaque(userData).release()
        ffi_closure_free(closurePtr)
    }
}

private func ffiCallback0Trampoline(
    cif: UnsafeMutablePointer<ffi_cif>?,
    ret: UnsafeMutableRawPointer?,
    args: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    userdata: UnsafeMutableRawPointer?
) {
    _ = cif
    _ = ret
    _ = args
    guard let userdata else { return }
    guard let vm = FFICallbackTLS.currentVM else { return }
    let ctx = Unmanaged<FFICallback0Context>.fromOpaque(userdata).takeUnretainedValue()
    do {
        _ = try vm.run(function: ctx.functionName)
    } catch {
        vm.output("[ffi_callback0] error: \(error)")
    }
}

private final class FFICallback1I32Context {
    let functionName: String
    init(functionName: String) {
        self.functionName = functionName
    }
}

private struct FFICallback1I32KeepAlive {
    let closurePtr: UnsafeMutableRawPointer
    let codePtr: UnsafeMutableRawPointer
    let userData: UnsafeMutableRawPointer

    func destroy() {
        Unmanaged<FFICallback1I32Context>.fromOpaque(userData).release()
        ffi_closure_free(closurePtr)
    }
}

private func ffiCallback1I32Trampoline(
    cif: UnsafeMutablePointer<ffi_cif>?,
    ret: UnsafeMutableRawPointer?,
    args: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    userdata: UnsafeMutableRawPointer?
) {
    _ = cif
    _ = ret
    guard let userdata else { return }
    guard let vm = FFICallbackTLS.currentVM else { return }
    guard let args else { return }

    let ctx = Unmanaged<FFICallback1I32Context>.fromOpaque(userdata).takeUnretainedValue()
    let arg0Ptr = args[0]
    let v: Int32 = arg0Ptr?.load(as: Int32.self) ?? 0
    do {
        _ = try vm.run(function: ctx.functionName, args: [.int(Int64(v))])
    } catch {
        vm.output("[ffi_callback1_i32] error: \(error)")
    }
}

#endif

public enum VMError: Error, CustomStringConvertible, Sendable {
    case invalidBytecode(String)
    case invalidOpcode(UInt8)
    case typeError(expected: String, got: KiraValue)
    case divideByZero
    case invalidReference(ObjectRef)
    case unknownFunction(Int)
    case notCallable(KiraValue)

    public var description: String {
        switch self {
        case .invalidBytecode(let m): return "error: invalid bytecode: \(m)"
        case .invalidOpcode(let b): return "error: invalid opcode 0x\(String(b, radix: 16))"
        case .typeError(let e, let g): return "error: type error: expected \(e), got \(g)"
        case .divideByZero: return "error: divide by zero"
        case .invalidReference(let r): return "error: invalid reference \(r.id)"
        case .unknownFunction(let i): return "error: unknown function index \(i)"
        case .notCallable(let v): return "error: not callable: \(v)"
        }
    }
}

public struct BytecodeFunction: Sendable {
    public var name: String
    public var paramCount: Int
    public var localCount: Int
    public var maxStackDepth: Int
    public var code: [UInt8]
}

public struct BytecodeModule: Sendable {
    public var integers: [Int64]
    public var floats: [Double]
    public var strings: [String]
    public var functions: [BytecodeFunction]
}

public struct BytecodeLoader: Sendable {
    public init() {}

    public func load(data: Data) throws -> BytecodeModule {
        var cursor = 0
        func readU8() throws -> UInt8 {
            guard cursor + 1 <= data.count else { throw VMError.invalidBytecode("unexpected EOF") }
            let v = data[cursor]
            cursor += 1
            return v
        }
        func readU16() throws -> UInt16 {
            let hi = UInt16(try readU8())
            let lo = UInt16(try readU8())
            return (hi << 8) | lo
        }
        func readU32() throws -> UInt32 {
            var v: UInt32 = 0
            for _ in 0..<4 { v = (v << 8) | UInt32(try readU8()) }
            return v
        }
        func readI64() throws -> Int64 {
            var v: UInt64 = 0
            for _ in 0..<8 { v = (v << 8) | UInt64(try readU8()) }
            return Int64(bitPattern: v)
        }
        func readF64() throws -> Double {
            var v: UInt64 = 0
            for _ in 0..<8 { v = (v << 8) | UInt64(try readU8()) }
            return Double(bitPattern: v)
        }
        func readBytes(_ n: Int) throws -> [UInt8] {
            guard cursor + n <= data.count else { throw VMError.invalidBytecode("unexpected EOF") }
            let sub = data[cursor..<(cursor + n)]
            cursor += n
            return Array(sub)
        }

        let magic = try readU32()
        guard magic == 0x4B495242 else { throw VMError.invalidBytecode("bad magic") }
        _ = try readU32() // version
        _ = try readU32() // flags
        let fnCount = Int(try readU32())
        _ = try readBytes(16) // reserved

        let intCount = Int(try readU32())
        var integers: [Int64] = []
        integers.reserveCapacity(intCount)
        for _ in 0..<intCount { integers.append(try readI64()) }

        let floatCount = Int(try readU32())
        var floats: [Double] = []
        floats.reserveCapacity(floatCount)
        for _ in 0..<floatCount { floats.append(try readF64()) }

        let stringCount = Int(try readU32())
        var strings: [String] = []
        strings.reserveCapacity(stringCount)
        for _ in 0..<stringCount {
            let len = Int(try readU32())
            let bytes = try readBytes(len)
            strings.append(String(decoding: bytes, as: UTF8.self))
        }

        var functions: [BytecodeFunction] = []
        functions.reserveCapacity(fnCount)
        for _ in 0..<fnCount {
            let nameIndex = Int(try readU16())
            let paramCount = Int(try readU8())
            let localCount = Int(try readU16())
            let maxStack = Int(try readU16())
            let codeLen = Int(try readU32())
            let code = try readBytes(codeLen)
            let name = nameIndex < strings.count ? strings[nameIndex] : "<fn\(functions.count)>"
            functions.append(BytecodeFunction(name: name, paramCount: paramCount, localCount: localCount, maxStackDepth: maxStack, code: code))
        }

        return BytecodeModule(integers: integers, floats: floats, strings: strings, functions: functions)
    }
}

public final class VirtualMachine: @unchecked Sendable {
    public let module: BytecodeModule
    public let heap = VMHeap()
    public var globals: [KiraValue]
    public var debugger: VMDebugger?
    public var output: @Sendable (String) -> Void
    private let trace: Bool

    public struct NativeFunction: @unchecked Sendable {
        public var arity: Int
        public var call: @Sendable ([KiraValue]) throws -> KiraValue

        public init(arity: Int, call: @escaping @Sendable ([KiraValue]) throws -> KiraValue) {
            self.arity = arity
            self.call = call
        }
    }

    // Native function registry (for embedding).
    public var nativeFunctions: [NativeFunction] = []

    private var gcTickCounter: Int = 0
    private let gcTickThreshold: Int = 512

    #if canImport(Clibffi)
    private var ffiCallback0s: [FFICallback0KeepAlive] = []
    private var ffiCallback1I32s: [FFICallback1I32KeepAlive] = []
    #endif

    public init(module: BytecodeModule, output: @escaping @Sendable (String) -> Void = { Swift.print($0) }) {
        self.module = module
        self.output = output
        self.trace = ProcessInfo.processInfo.environment["KIRA_VM_TRACE"] == "1"
        self.globals = Array(repeating: .nil_, count: max(256, module.functions.count))
        // Preload function refs into globals.
        for i in 0..<module.functions.count {
            let closure = KiraClosure(functionIndex: i, captures: [])
            let ref = heap.allocate(closure)
            globals[i] = .reference(ref)
        }
    }

    deinit {
        #if canImport(Clibffi)
        for cb in ffiCallback0s {
            cb.destroy()
        }
        for cb in ffiCallback1I32s {
            cb.destroy()
        }
        #endif
    }

    public func run(function name: String, args: [KiraValue] = []) throws -> KiraValue {
        guard let idx = module.functions.firstIndex(where: { $0.name == name }) else { throw VMError.invalidBytecode("entry function not found") }
        let fiber = VMFiber()
        // Push callee + args, then call.
        fiber.operandStack.push(globals[idx])
        for a in args { fiber.operandStack.push(a) }
        try pushCallFrame(fiber: fiber, callee: globals[idx], argCount: args.count)
        return try run(fiber: fiber)
    }

    public func run(fiber: VMFiber) throws -> KiraValue {
        runLoop: while true {
            if case .suspended(let v) = fiber.state { return v }
            guard let frame = fiber.callStack.last else { return .nil_ }
            let fn = try function(at: frame.functionIndex)
            var current = frame

            while current.ip < fn.code.count {
                let opcodeByte = fn.code[current.ip]
                current.ip += 1
                guard let opcode = Instruction(rawValue: opcodeByte) else { throw VMError.invalidOpcode(opcodeByte) }
                if trace {
                    output("[vm] \(fn.name) ip=\(current.ip - 1) op=0x\(String(opcodeByte, radix: 16)) stack=\(fiber.operandStack.count)")
                }

                switch opcode {
                case .push_int:
                    let idx = try readU16(fn, &current)
                    let i = Int(idx)
                    guard i >= 0, i < module.integers.count else {
                        throw VMError.invalidBytecode("integer constant index out of bounds: \(i)")
                    }
                    fiber.operandStack.push(.int(module.integers[i]))
                case .push_float:
                    let idx = try readU16(fn, &current)
                    let i = Int(idx)
                    guard i >= 0, i < module.floats.count else {
                        throw VMError.invalidBytecode("float constant index out of bounds: \(i)")
                    }
                    fiber.operandStack.push(.float(module.floats[i]))
                case .push_string:
                    let idx = try readU16(fn, &current)
                    let i = Int(idx)
                    guard i >= 0, i < module.strings.count else {
                        throw VMError.invalidBytecode("string constant index out of bounds: \(i)")
                    }
                    let s = module.strings[i]
                    let ref = heap.allocate(KiraString(s))
                    fiber.operandStack.push(.reference(ref))
                case .push_bool_true:
                    fiber.operandStack.push(.bool(true))
                case .push_bool_false:
                    fiber.operandStack.push(.bool(false))
                case .push_nil:
                    fiber.operandStack.push(.nil_)
                case .pop:
                    _ = fiber.operandStack.pop()
                case .dup:
                    fiber.operandStack.push(fiber.operandStack.peek())
                case .swap:
                    let a = fiber.operandStack.pop()
                    let b = fiber.operandStack.pop()
                    fiber.operandStack.push(a)
                    fiber.operandStack.push(b)

                case .load_local:
                    let slot = Int(try readU8(fn, &current))
                    guard slot >= 0, slot < current.locals.count else {
                        throw VMError.invalidBytecode("local slot out of bounds: \(slot) (locals=\(current.locals.count))")
                    }
                    fiber.operandStack.push(current.locals[slot])
                case .store_local:
                    let slot = Int(try readU8(fn, &current))
                    guard slot >= 0, slot < current.locals.count else {
                        throw VMError.invalidBytecode("local slot out of bounds: \(slot) (locals=\(current.locals.count))")
                    }
                    current.locals[slot] = fiber.operandStack.pop()

                case .load_global:
                    let idx = Int(try readU16(fn, &current))
                    guard idx >= 0, idx < globals.count else {
                        throw VMError.invalidBytecode("global slot out of bounds: \(idx) (globals=\(globals.count))")
                    }
                    fiber.operandStack.push(globals[idx])
                case .store_global:
                    let idx = Int(try readU16(fn, &current))
                    guard idx >= 0, idx < globals.count else {
                        throw VMError.invalidBytecode("global slot out of bounds: \(idx) (globals=\(globals.count))")
                    }
                    globals[idx] = fiber.operandStack.pop()

                case .add_int:
                    let b = try fiber.operandStack.popInt()
                    let a = try fiber.operandStack.popInt()
                    fiber.operandStack.push(.int(a &+ b))
                case .sub_int:
                    let b = try fiber.operandStack.popInt()
                    let a = try fiber.operandStack.popInt()
                    fiber.operandStack.push(.int(a &- b))
                case .mul_int:
                    let b = try fiber.operandStack.popInt()
                    let a = try fiber.operandStack.popInt()
                    fiber.operandStack.push(.int(a &* b))
                case .div_int:
                    let b = try fiber.operandStack.popInt()
                    if b == 0 { throw VMError.divideByZero }
                    let a = try fiber.operandStack.popInt()
                    fiber.operandStack.push(.int(a / b))
                case .mod_int:
                    let b = try fiber.operandStack.popInt()
                    let a = try fiber.operandStack.popInt()
                    fiber.operandStack.push(.int(a % b))
                case .neg_int:
                    let a = try fiber.operandStack.popInt()
                    fiber.operandStack.push(.int(-a))
                case .bitand_int:
                    let b = try fiber.operandStack.popInt()
                    let a = try fiber.operandStack.popInt()
                    fiber.operandStack.push(.int(a & b))
                case .bitor_int:
                    let b = try fiber.operandStack.popInt()
                    let a = try fiber.operandStack.popInt()
                    fiber.operandStack.push(.int(a | b))
                case .bitxor_int:
                    let b = try fiber.operandStack.popInt()
                    let a = try fiber.operandStack.popInt()
                    fiber.operandStack.push(.int(a ^ b))
                case .shl_int:
                    let b = try fiber.operandStack.popInt()
                    let a = try fiber.operandStack.popInt()
                    fiber.operandStack.push(.int(a << b))
                case .shr_int:
                    let b = try fiber.operandStack.popInt()
                    let a = try fiber.operandStack.popInt()
                    fiber.operandStack.push(.int(a >> b))

                case .add_float:
                    let b = try fiber.operandStack.popFloat()
                    let a = try fiber.operandStack.popFloat()
                    fiber.operandStack.push(.float(a + b))
                case .sub_float:
                    let b = try fiber.operandStack.popFloat()
                    let a = try fiber.operandStack.popFloat()
                    fiber.operandStack.push(.float(a - b))
                case .mul_float:
                    let b = try fiber.operandStack.popFloat()
                    let a = try fiber.operandStack.popFloat()
                    fiber.operandStack.push(.float(a * b))
                case .div_float:
                    let b = try fiber.operandStack.popFloat()
                    let a = try fiber.operandStack.popFloat()
                    fiber.operandStack.push(.float(a / b))
                case .neg_float:
                    let a = try fiber.operandStack.popFloat()
                    fiber.operandStack.push(.float(-a))

                case .int_to_float:
                    let a = try fiber.operandStack.popInt()
                    fiber.operandStack.push(.float(Double(a)))
                case .float_to_int:
                    let a = try fiber.operandStack.popFloat()
                    fiber.operandStack.push(.int(Int64(a)))

                case .eq_int:
                    let b = try fiber.operandStack.popInt()
                    let a = try fiber.operandStack.popInt()
                    fiber.operandStack.push(.bool(a == b))
                case .neq_int:
                    let b = try fiber.operandStack.popInt()
                    let a = try fiber.operandStack.popInt()
                    fiber.operandStack.push(.bool(a != b))
                case .lt_int:
                    let b = try fiber.operandStack.popInt()
                    let a = try fiber.operandStack.popInt()
                    fiber.operandStack.push(.bool(a < b))
                case .gt_int:
                    let b = try fiber.operandStack.popInt()
                    let a = try fiber.operandStack.popInt()
                    fiber.operandStack.push(.bool(a > b))
                case .lte_int:
                    let b = try fiber.operandStack.popInt()
                    let a = try fiber.operandStack.popInt()
                    fiber.operandStack.push(.bool(a <= b))
                case .gte_int:
                    let b = try fiber.operandStack.popInt()
                    let a = try fiber.operandStack.popInt()
                    fiber.operandStack.push(.bool(a >= b))
                case .eq_float:
                    let b = try fiber.operandStack.popFloat()
                    let a = try fiber.operandStack.popFloat()
                    fiber.operandStack.push(.bool(a == b))
                case .lt_float:
                    let b = try fiber.operandStack.popFloat()
                    let a = try fiber.operandStack.popFloat()
                    fiber.operandStack.push(.bool(a < b))
                case .gt_float:
                    let b = try fiber.operandStack.popFloat()
                    let a = try fiber.operandStack.popFloat()
                    fiber.operandStack.push(.bool(a > b))
                case .eq_ref:
                    let b = try fiber.operandStack.popRef()
                    let a = try fiber.operandStack.popRef()
                    fiber.operandStack.push(.bool(a == b))

                case .and_bool:
                    let b = try fiber.operandStack.popBool()
                    let a = try fiber.operandStack.popBool()
                    fiber.operandStack.push(.bool(a && b))
                case .or_bool:
                    let b = try fiber.operandStack.popBool()
                    let a = try fiber.operandStack.popBool()
                    fiber.operandStack.push(.bool(a || b))
                case .not_bool:
                    let a = try fiber.operandStack.popBool()
                    fiber.operandStack.push(.bool(!a))

                case .jump:
                    let delta = try readI16(fn, &current)
                    current.ip += Int(delta)
                case .jump_if_true:
                    let delta = try readI16(fn, &current)
                    let cond = try fiber.operandStack.popBool()
                    if cond { current.ip += Int(delta) }
                case .jump_if_false:
                    let delta = try readI16(fn, &current)
                    let cond = try fiber.operandStack.popBool()
                    if !cond { current.ip += Int(delta) }
                case .jump_if_nil:
                    let delta = try readI16(fn, &current)
                    let v = fiber.operandStack.pop()
                    if case .nil_ = v { current.ip += Int(delta) }
                    else { fiber.operandStack.push(v) }

                case .call:
                    let argc = Int(try readU8(fn, &current))
                    if fiber.operandStack.count <= argc {
                        throw VMError.invalidBytecode("stack underflow in call (argc=\(argc))")
                    }
                    let callee = fiber.operandStack.peek(argc)
                    try pushCallFrame(fiber: fiber, callee: callee, argCount: argc)
                    // Save updated caller frame.
                    fiber.callStack[fiber.callStack.count - 2] = current
                    // Start executing the callee frame (reload `fn` from the new top of stack).
                    continue runLoop
                case .tail_call:
                    let argc = Int(try readU8(fn, &current))
                    if fiber.operandStack.count <= argc {
                        throw VMError.invalidBytecode("stack underflow in tail_call (argc=\(argc))")
                    }
                    let callee = fiber.operandStack.peek(argc)
                    try tailCall(fiber: fiber, callee: callee, argCount: argc)
                    continue runLoop
                case .call_native:
                    let idx = Int(try readU16(fn, &current))
                    guard idx < nativeFunctions.count else { throw VMError.invalidBytecode("native index out of range") }
                    let argc = nativeFunctions[idx].arity
                    var args: [KiraValue] = []
                    args.reserveCapacity(argc)
                    for _ in 0..<argc { args.append(fiber.operandStack.pop()) }
                    args.reverse()
                    let result = try nativeFunctions[idx].call(args)
                    fiber.operandStack.push(result)
                case .ret:
                    let result: KiraValue = (fiber.operandStack.count > 0) ? fiber.operandStack.pop() : .nil_
                    // Pop frame
                    _ = fiber.callStack.popLast()
                    if fiber.callStack.isEmpty {
                        fiber.state = .dead
                        return result
                    }
                    // Restore stack to base count and push result.
                    let callerBase = fiber.currentFrame.baseStackCount
                    fiber.operandStack.truncate(to: callerBase)
                    fiber.operandStack.push(result)
                    continue runLoop

                case .new_object:
                    let fieldCount = Int(try readU16(fn, &current))
                    let ref = heap.allocate(KiraObject(
                        type: KiraTypeDescriptor(name: "Object", fieldCount: fieldCount),
                        fields: Array(repeating: .nil_, count: max(0, fieldCount))
                    ))
                    fiber.operandStack.push(.reference(ref))
                case .new_array:
                    let count = Int(try fiber.operandStack.popInt())
                    let elements = Array(repeating: KiraValue.nil_, count: max(0, count))
                    let ref = heap.allocate(KiraArray(elements: elements))
                    fiber.operandStack.push(.reference(ref))
                case .array_length:
                    let arrRef = try fiber.operandStack.popRef()
                    let obj = try heap.get(arrRef)
                    guard let arr = obj as? KiraArray else { throw VMError.typeError(expected: "Array", got: .reference(arrRef)) }
                    fiber.operandStack.push(.int(Int64(arr.elements.count)))
                case .array_append:
                    let value = fiber.operandStack.pop()
                    let arrRef = try fiber.operandStack.popRef()
                    let obj = try heap.get(arrRef)
                    guard let arr = obj as? KiraArray else { throw VMError.typeError(expected: "Array", got: .reference(arrRef)) }
                    arr.elements.append(value)
                    fiber.operandStack.push(.reference(arrRef))
                case .array_slice:
                    let end = Int(try fiber.operandStack.popInt())
                    let start = Int(try fiber.operandStack.popInt())
                    let arrRef = try fiber.operandStack.popRef()
                    let obj = try heap.get(arrRef)
                    guard let arr = obj as? KiraArray else { throw VMError.typeError(expected: "Array", got: .reference(arrRef)) }
                    let slice = Array(arr.elements[max(0, start)..<min(end, arr.elements.count)])
                    let ref = heap.allocate(KiraArray(elements: slice))
                    fiber.operandStack.push(.reference(ref))

                case .load_index:
                    let idx = Int(try fiber.operandStack.popInt())
                    let arrRef = try fiber.operandStack.popRef()
                    let obj = try heap.get(arrRef)
                    guard let arr = obj as? KiraArray else { throw VMError.typeError(expected: "Array", got: .reference(arrRef)) }
                    fiber.operandStack.push(arr.elements[idx])
                case .store_index:
                    let value = fiber.operandStack.pop()
                    let idx = Int(try fiber.operandStack.popInt())
                    let arrRef = try fiber.operandStack.popRef()
                    let obj = try heap.get(arrRef)
                    guard let arr = obj as? KiraArray else { throw VMError.typeError(expected: "Array", got: .reference(arrRef)) }
                    arr.elements[idx] = value

                case .string_concat:
                    let bRef = try fiber.operandStack.popRef()
                    let aRef = try fiber.operandStack.popRef()
                    let bObj = try heap.get(bRef)
                    let aObj = try heap.get(aRef)
                    guard let bStr = bObj as? KiraString, let aStr = aObj as? KiraString else {
                        throw VMError.typeError(expected: "String", got: .reference(aRef))
                    }
                    let ref = heap.allocate(KiraString(aStr.value + bStr.value))
                    fiber.operandStack.push(.reference(ref))
                case .string_length:
                    let sRef = try fiber.operandStack.popRef()
                    let obj = try heap.get(sRef)
                    guard let s = obj as? KiraString else { throw VMError.typeError(expected: "String", got: .reference(sRef)) }
                    fiber.operandStack.push(.int(Int64(s.value.count)))
                case .string_interpolate:
                    let segmentCount = Int(try readU8(fn, &current))
                    var parts: [String] = []
                    parts.reserveCapacity(segmentCount)
                    for _ in 0..<segmentCount {
                        let v = fiber.operandStack.pop()
                        parts.append(stringify(v))
                    }
                    parts.reverse()
                    let ref = heap.allocate(KiraString(parts.joined()))
                    fiber.operandStack.push(.reference(ref))
                case .print:
                    let v = fiber.operandStack.pop()
                    output(stringify(v))
                case .make_color:
                    let a = try fiber.operandStack.popFloat()
                    let b = try fiber.operandStack.popFloat()
                    let g = try fiber.operandStack.popFloat()
                    let r = try fiber.operandStack.popFloat()
                    let obj = KiraObject(
                        type: KiraTypeDescriptor(name: "Color", fieldCount: 4),
                        fields: [.float(r), .float(g), .float(b), .float(a)]
                    )
                    let ref = heap.allocate(obj)
                    fiber.operandStack.push(.reference(ref))

                case .make_closure:
                    let fidx = Int(try readU16(fn, &current))
                    let captureCount = Int(try readU8(fn, &current))
                    var captures: [KiraValue] = []
                    captures.reserveCapacity(captureCount)
                    for _ in 0..<captureCount {
                        let slot = Int(try readU8(fn, &current))
                        guard slot >= 0, slot < current.locals.count else {
                            throw VMError.invalidBytecode("closure capture slot out of bounds: \(slot) (locals=\(current.locals.count))")
                        }
                        captures.append(current.locals[slot])
                    }
                    let ref = heap.allocate(KiraClosure(functionIndex: fidx, captures: captures))
                    fiber.operandStack.push(.reference(ref))
                case .load_capture:
                    let slot = Int(try readU8(fn, &current))
                    guard let closureRef = current.closure else { throw VMError.invalidBytecode("load_capture outside closure") }
                    let obj = try heap.get(closureRef)
                    guard let closure = obj as? KiraClosure else { throw VMError.invalidBytecode("invalid closure") }
                    fiber.operandStack.push(closure.captures[slot])

                case .ffi_load:
                    // Expects: libName(string or nil), symbolName(string) on stack
                    let symRef = try fiber.operandStack.popRef()
                    let libVal = fiber.operandStack.pop()
                    let symObj = try heap.get(symRef)
                    guard let symStr = symObj as? KiraString else { throw VMError.typeError(expected: "String", got: .reference(symRef)) }
                    let libName: String
                    switch libVal {
                    case .nil_:
                        libName = ""
                    case .reference(let r):
                        let o = try heap.get(r)
                        guard let s = o as? KiraString else { throw VMError.typeError(expected: "String", got: libVal) }
                        libName = s.value
                    default:
                        throw VMError.typeError(expected: "String|nil", got: libVal)
                    }
                    #if canImport(Darwin)
                    let handle = dlopen(libName.isEmpty ? nil : libName, RTLD_NOW)
                    guard let handle else { throw VMError.invalidBytecode("dlopen failed") }
                    guard let ptr = dlsym(handle, symStr.value) else { throw VMError.invalidBytecode("dlsym failed") }
                    fiber.operandStack.push(.nativePointer(UnsafeMutableRawPointer(mutating: ptr)))
                    #else
                    throw VMError.invalidBytecode("ffi_load unsupported on this platform")
                    #endif
                case .ffi_callback0:
                    #if canImport(Clibffi)
                    let nameRef = try fiber.operandStack.popRef()
                    let obj = try heap.get(nameRef)
                    guard let nameStr = obj as? KiraString else {
                        throw VMError.typeError(expected: "String", got: .reference(nameRef))
                    }

                    // Prepare a cif for: void callback(void)
                    var cif = ffi_cif()
                    var retType = ffi_type_void
                    let status = ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 0, &retType, nil)
                    guard status == FFI_OK else { throw VMError.invalidBytecode("ffi_callback0 cif preparation failed") }

                    var codePtr: UnsafeMutableRawPointer?
                    guard let closurePtr = ffi_closure_alloc(MemoryLayout<ffi_closure>.size, &codePtr) else {
                        throw VMError.invalidBytecode("ffi_callback0 closure allocation failed")
                    }
                    guard let codePtr else {
                        ffi_closure_free(closurePtr)
                        throw VMError.invalidBytecode("ffi_callback0 closure code pointer is null")
                    }

                    let ctx = FFICallback0Context(functionName: nameStr.value)
                    let userData = Unmanaged.passRetained(ctx).toOpaque()

                    let prepStatus = ffi_prep_closure_loc(
                        closurePtr.assumingMemoryBound(to: ffi_closure.self),
                        &cif,
                        ffiCallback0Trampoline,
                        userData,
                        codePtr
                    )
                    guard prepStatus == FFI_OK else {
                        Unmanaged<FFICallback0Context>.fromOpaque(userData).release()
                        ffi_closure_free(closurePtr)
                        throw VMError.invalidBytecode("ffi_callback0 closure preparation failed")
                    }

                    ffiCallback0s.append(.init(closurePtr: closurePtr, codePtr: codePtr, userData: userData))
                    fiber.operandStack.push(.nativePointer(codePtr))
                    #else
                    throw VMError.invalidBytecode("ffi_callback0 unsupported on this platform")
                    #endif
                case .ffi_callback1_i32:
                    #if canImport(Clibffi)
                    let nameRef = try fiber.operandStack.popRef()
                    let obj = try heap.get(nameRef)
                    guard let nameStr = obj as? KiraString else {
                        throw VMError.typeError(expected: "String", got: .reference(nameRef))
                    }

                    // Prepare a cif for: void callback(int32)
                    var cif = ffi_cif()
                    var retType = ffi_type_void
                    var argTypes: [UnsafeMutablePointer<ffi_type>?] = [UnsafeMutablePointer(mutating: &ffi_type_sint32)]
                    let status = argTypes.withUnsafeMutableBufferPointer { buf in
                        ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 1, &retType, buf.baseAddress)
                    }
                    guard status == FFI_OK else { throw VMError.invalidBytecode("ffi_callback1_i32 cif preparation failed") }

                    var codePtr: UnsafeMutableRawPointer?
                    guard let closurePtr = ffi_closure_alloc(MemoryLayout<ffi_closure>.size, &codePtr) else {
                        throw VMError.invalidBytecode("ffi_callback1_i32 closure allocation failed")
                    }
                    guard let codePtr else {
                        ffi_closure_free(closurePtr)
                        throw VMError.invalidBytecode("ffi_callback1_i32 closure code pointer is null")
                    }

                    let ctx = FFICallback1I32Context(functionName: nameStr.value)
                    let userData = Unmanaged.passRetained(ctx).toOpaque()

                    let prepStatus = ffi_prep_closure_loc(
                        closurePtr.assumingMemoryBound(to: ffi_closure.self),
                        &cif,
                        ffiCallback1I32Trampoline,
                        userData,
                        codePtr
                    )
                    guard prepStatus == FFI_OK else {
                        Unmanaged<FFICallback1I32Context>.fromOpaque(userData).release()
                        ffi_closure_free(closurePtr)
                        throw VMError.invalidBytecode("ffi_callback1_i32 closure preparation failed")
                    }

                    ffiCallback1I32s.append(.init(closurePtr: closurePtr, codePtr: codePtr, userData: userData))
                    fiber.operandStack.push(.nativePointer(codePtr))
                    #else
                    throw VMError.invalidBytecode("ffi_callback1_i32 unsupported on this platform")
                    #endif
                case .ffi_call:
                    #if canImport(Clibffi)
                    let argc = Int(try readU8(fn, &current))

                    indirect enum FFITypeDesc {
                        case scalar(UInt8)
                        case cstruct([FFITypeDesc])
                    }

                    func readFFITypeDesc() throws -> FFITypeDesc {
                        let tag = try readU8(fn, &current)
                        if tag == 13 {
                            let fieldCount = Int(try readU8(fn, &current))
                            var fields: [FFITypeDesc] = []
                            fields.reserveCapacity(fieldCount)
                            for _ in 0..<fieldCount { fields.append(try readFFITypeDesc()) }
                            return .cstruct(fields)
                        }
                        return .scalar(tag)
                    }

                    let retDesc = try readFFITypeDesc()
                    var argDescs: [FFITypeDesc] = []
                    argDescs.reserveCapacity(argc)
                    for _ in 0..<argc { argDescs.append(try readFFITypeDesc()) }

                    // Pop arguments (in call order) and then the function pointer.
                    var args: [KiraValue] = []
                    args.reserveCapacity(argc)
                    for _ in 0..<argc { args.append(fiber.operandStack.pop()) }
                    args.reverse()

                    let fnPtrVal = fiber.operandStack.pop()
                    let fnPtr: UnsafeMutableRawPointer?
                    switch fnPtrVal {
                    case .nativePointer(let p):
                        fnPtr = p
                    case .nil_:
                        fnPtr = nil
                    default:
                        throw VMError.typeError(expected: "Pointer", got: fnPtrVal)
                    }
                    guard let fnPtr else { throw VMError.invalidBytecode("ffi_call null function pointer") }

                    func ffiScalarType(for tag: UInt8) -> UnsafeMutablePointer<ffi_type> {
                        switch tag {
                        case 0: return UnsafeMutablePointer(mutating: &ffi_type_void)
                        case 1: return UnsafeMutablePointer(mutating: &ffi_type_sint8)
                        case 2: return UnsafeMutablePointer(mutating: &ffi_type_sint16)
                        case 3: return UnsafeMutablePointer(mutating: &ffi_type_sint32)
                        case 4: return UnsafeMutablePointer(mutating: &ffi_type_sint64)
                        case 5: return UnsafeMutablePointer(mutating: &ffi_type_uint8)
                        case 6: return UnsafeMutablePointer(mutating: &ffi_type_uint16)
                        case 7: return UnsafeMutablePointer(mutating: &ffi_type_uint32)
                        case 8: return UnsafeMutablePointer(mutating: &ffi_type_uint64)
                        case 9: return UnsafeMutablePointer(mutating: &ffi_type_float)
                        case 10: return UnsafeMutablePointer(mutating: &ffi_type_double)
                        case 11, 12: return UnsafeMutablePointer(mutating: &ffi_type_pointer)
                        default: return UnsafeMutablePointer(mutating: &ffi_type_pointer)
                        }
                    }

                    var ffiTypeDeallocators: [() -> Void] = []
                    ffiTypeDeallocators.reserveCapacity(8)

                    func ffiType(for desc: FFITypeDesc) -> UnsafeMutablePointer<ffi_type> {
                        switch desc {
                        case .scalar(let tag):
                            return ffiScalarType(for: tag)
                        case .cstruct(let fields):
                            let fieldPtrs = fields.map { ffiType(for: $0) }
                            let elements = UnsafeMutablePointer<UnsafeMutablePointer<ffi_type>?>.allocate(capacity: fieldPtrs.count + 1)
                            for i in 0..<fieldPtrs.count { elements[i] = fieldPtrs[i] }
                            elements[fieldPtrs.count] = nil

                            let t = UnsafeMutablePointer<ffi_type>.allocate(capacity: 1)
                            t.initialize(to: ffi_type())
                            t.pointee.size = 0
                            t.pointee.alignment = 0
                            t.pointee.type = UInt16(13) // FFI_TYPE_STRUCT
                            t.pointee.elements = elements

                            ffiTypeDeallocators.append {
                                elements.deallocate()
                                t.deinitialize(count: 1)
                                t.deallocate()
                            }
                            return t
                        }
                    }

                    defer { for d in ffiTypeDeallocators.reversed() { d() } }

                    var argTypes: [UnsafeMutablePointer<ffi_type>?] = argDescs.map { ffiType(for: $0) }
                    var cif = ffi_cif()
                    let status: ffi_status = argTypes.withUnsafeMutableBufferPointer { argTypeBuf in
                        let retTypePtr = ffiType(for: retDesc)
                        return ffi_prep_cif(
                            &cif,
                            FFI_DEFAULT_ABI,
                            UInt32(argc),
                            retTypePtr,
                            argTypeBuf.baseAddress
                        )
                    }
                    guard status == FFI_OK else { throw VMError.invalidBytecode("ffi_cif preparation failed") }

                    func box<T>(_ value: T) -> UnsafeMutableRawPointer {
                        let ptr = UnsafeMutablePointer<T>.allocate(capacity: 1)
                        ptr.initialize(to: value)
                        return UnsafeMutableRawPointer(ptr)
                    }

                    var boxedArgs: [UnsafeMutableRawPointer?] = []
                    boxedArgs.reserveCapacity(argc)
                    var deallocators: [() -> Void] = []
                    deallocators.reserveCapacity(argc + 8)

                    func alignUp(_ x: Int, to alignment: Int) -> Int {
                        guard alignment > 1 else { return x }
                        let m = alignment - 1
                        return (x + m) & ~m
                    }

                    func scalarSizeAlign(tag: UInt8) -> (size: Int, alignment: Int) {
                        switch tag {
                        case 1, 5: return (1, 1)
                        case 2, 6: return (2, 2)
                        case 3, 7, 9: return (4, 4)
                        case 4, 8, 10: return (8, 8)
                        case 11, 12:
                            return (MemoryLayout<UnsafeMutableRawPointer?>.size, MemoryLayout<UnsafeMutableRawPointer?>.alignment)
                        default:
                            return (8, 8)
                        }
                    }

                    indirect enum FFILayout {
                        case scalar(tag: UInt8, size: Int, alignment: Int)
                        case cstruct(fields: [FFILayout], offsets: [Int], size: Int, alignment: Int)

                        var size: Int {
                            switch self {
                            case .scalar(_, let s, _): return s
                            case .cstruct(_, _, let s, _): return s
                            }
                        }

                        var alignment: Int {
                            switch self {
                            case .scalar(_, _, let a): return a
                            case .cstruct(_, _, _, let a): return a
                            }
                        }
                    }

                    func layout(for desc: FFITypeDesc) -> FFILayout {
                        switch desc {
                        case .scalar(let tag):
                            let sa = scalarSizeAlign(tag: tag)
                            return .scalar(tag: tag, size: sa.size, alignment: sa.alignment)
                        case .cstruct(let fields):
                            let fieldLayouts = fields.map(layout(for:))
                            var offsets: [Int] = Array(repeating: 0, count: fieldLayouts.count)
                            var offset = 0
                            var maxAlign = 1
                            for i in 0..<fieldLayouts.count {
                                let a = fieldLayouts[i].alignment
                                maxAlign = max(maxAlign, a)
                                offset = alignUp(offset, to: a)
                                offsets[i] = offset
                                offset += fieldLayouts[i].size
                            }
                            let totalSize = alignUp(offset, to: maxAlign)
                            return .cstruct(fields: fieldLayouts, offsets: offsets, size: totalSize, alignment: maxAlign)
                        }
                    }

                    func pack(_ v: KiraValue, layout: FFILayout, into dst: UnsafeMutableRawPointer) throws {
                        switch layout {
                        case .scalar(let tag, _, _):
                            switch tag {
                            case 1:
                                let iv = Int8(truncatingIfNeeded: try v.asInt())
                                dst.storeBytes(of: iv, as: Int8.self)
                            case 2:
                                let iv = Int16(truncatingIfNeeded: try v.asInt())
                                dst.storeBytes(of: iv, as: Int16.self)
                            case 3:
                                let iv = Int32(truncatingIfNeeded: try v.asInt())
                                dst.storeBytes(of: iv, as: Int32.self)
                            case 4:
                                let iv = Int64(try v.asInt())
                                dst.storeBytes(of: iv, as: Int64.self)
                            case 5:
                                let iv = UInt8(truncatingIfNeeded: try v.asInt())
                                dst.storeBytes(of: iv, as: UInt8.self)
                            case 6:
                                let iv = UInt16(truncatingIfNeeded: try v.asInt())
                                dst.storeBytes(of: iv, as: UInt16.self)
                            case 7:
                                let iv = UInt32(truncatingIfNeeded: try v.asInt())
                                dst.storeBytes(of: iv, as: UInt32.self)
                            case 8:
                                let iv = UInt64(bitPattern: try v.asInt())
                                dst.storeBytes(of: iv, as: UInt64.self)
                            case 9:
                                let fv = try v.asFloat32()
                                dst.storeBytes(of: fv, as: Float.self)
                            case 10:
                                let fv = try v.asFloat64()
                                dst.storeBytes(of: fv, as: Double.self)
                            case 12: // cstring
                                switch v {
                                case .reference(let r):
                                    let o = try heap.get(r)
                                    guard let s = o as? KiraString else { throw VMError.typeError(expected: "String", got: v) }
                                    let cstr = strdup(s.value)
                                    let pp: UnsafeMutablePointer<CChar>? = cstr
                                    dst.storeBytes(of: pp, as: UnsafeMutablePointer<CChar>?.self)
                                    deallocators.append { if let cstr { free(cstr) } }
                                case .nil_:
                                    let pp: UnsafeMutablePointer<CChar>? = nil
                                    dst.storeBytes(of: pp, as: UnsafeMutablePointer<CChar>?.self)
                                default:
                                    throw VMError.typeError(expected: "String|nil", got: v)
                                }
                            default: // pointer / unknown
                                let p: UnsafeMutableRawPointer?
                                switch v {
                                case .nativePointer(let np): p = np
                                case .nil_: p = nil
                                default: throw VMError.typeError(expected: "Pointer|nil", got: v)
                                }
                                dst.storeBytes(of: p, as: UnsafeMutableRawPointer?.self)
                            }
                        case .cstruct(let fields, let offsets, _, _):
                            guard case .reference(let r) = v else { throw VMError.typeError(expected: "CStruct", got: v) }
                            let obj = try heap.get(r)
                            guard obj.fields.count >= fields.count else {
                                throw VMError.invalidBytecode("cstruct field count mismatch (got=\(obj.fields.count), expected=\(fields.count))")
                            }
                            for i in 0..<fields.count {
                                try pack(obj.fields[i], layout: fields[i], into: dst.advanced(by: offsets[i]))
                            }
                        }
                    }

                    func unpack(layout: FFILayout, from src: UnsafeMutableRawPointer) throws -> KiraValue {
                        switch layout {
                        case .scalar(let tag, _, _):
                            switch tag {
                            case 0:
                                return .nil_
                            case 1:
                                return .int(Int64(src.load(as: Int8.self)))
                            case 2:
                                return .int(Int64(src.load(as: Int16.self)))
                            case 3:
                                return .int(Int64(src.load(as: Int32.self)))
                            case 4:
                                return .int(src.load(as: Int64.self))
                            case 5:
                                return .int(Int64(src.load(as: UInt8.self)))
                            case 6:
                                return .int(Int64(src.load(as: UInt16.self)))
                            case 7:
                                return .int(Int64(src.load(as: UInt32.self)))
                            case 8:
                                return .int(Int64(bitPattern: src.load(as: UInt64.self)))
                            case 9:
                                return .float(Double(src.load(as: Float.self)))
                            case 10:
                                return .float(src.load(as: Double.self))
                            case 11, 12:
                                let p = src.load(as: UnsafeMutableRawPointer?.self)
                                if let p { return .nativePointer(p) }
                                return .nil_
                            default:
                                return .nil_
                            }
                        case .cstruct(let fields, let offsets, _, _):
                            var outFields: [KiraValue] = []
                            outFields.reserveCapacity(fields.count)
                            for i in 0..<fields.count {
                                outFields.append(try unpack(layout: fields[i], from: src.advanced(by: offsets[i])))
                            }
                            let obj = KiraObject(type: KiraTypeDescriptor(name: "CStruct", fieldCount: outFields.count), fields: outFields)
                            let ref = heap.allocate(obj)
                            return .reference(ref)
                        }
                    }

                    for i in 0..<argc {
                        let desc = argDescs[i]
                        let v = args[i]

                        switch desc {
                        case .scalar(let tag) where tag != 13:
                            switch tag {
                            case 1: // int8
                            let iv = Int8(truncatingIfNeeded: try v.asInt())
                            let ptr = box(iv).assumingMemoryBound(to: Int8.self)
                            boxedArgs.append(UnsafeMutableRawPointer(ptr))
                            deallocators.append { ptr.deinitialize(count: 1); ptr.deallocate() }
                            case 2:
                            let iv = Int16(truncatingIfNeeded: try v.asInt())
                            let ptr = box(iv).assumingMemoryBound(to: Int16.self)
                            boxedArgs.append(UnsafeMutableRawPointer(ptr))
                            deallocators.append { ptr.deinitialize(count: 1); ptr.deallocate() }
                            case 3:
                            let iv = Int32(truncatingIfNeeded: try v.asInt())
                            let ptr = box(iv).assumingMemoryBound(to: Int32.self)
                            boxedArgs.append(UnsafeMutableRawPointer(ptr))
                            deallocators.append { ptr.deinitialize(count: 1); ptr.deallocate() }
                            case 4:
                            let iv = Int64(try v.asInt())
                            let ptr = box(iv).assumingMemoryBound(to: Int64.self)
                            boxedArgs.append(UnsafeMutableRawPointer(ptr))
                            deallocators.append { ptr.deinitialize(count: 1); ptr.deallocate() }
                            case 5:
                            let iv = UInt8(truncatingIfNeeded: try v.asInt())
                            let ptr = box(iv).assumingMemoryBound(to: UInt8.self)
                            boxedArgs.append(UnsafeMutableRawPointer(ptr))
                            deallocators.append { ptr.deinitialize(count: 1); ptr.deallocate() }
                            case 6:
                            let iv = UInt16(truncatingIfNeeded: try v.asInt())
                            let ptr = box(iv).assumingMemoryBound(to: UInt16.self)
                            boxedArgs.append(UnsafeMutableRawPointer(ptr))
                            deallocators.append { ptr.deinitialize(count: 1); ptr.deallocate() }
                            case 7:
                            let iv = UInt32(truncatingIfNeeded: try v.asInt())
                            let ptr = box(iv).assumingMemoryBound(to: UInt32.self)
                            boxedArgs.append(UnsafeMutableRawPointer(ptr))
                            deallocators.append { ptr.deinitialize(count: 1); ptr.deallocate() }
                            case 8:
                            let iv = UInt64(bitPattern: try v.asInt())
                            let ptr = box(iv).assumingMemoryBound(to: UInt64.self)
                            boxedArgs.append(UnsafeMutableRawPointer(ptr))
                            deallocators.append { ptr.deinitialize(count: 1); ptr.deallocate() }
                            case 9:
                            let fv = try v.asFloat32()
                            let ptr = box(fv).assumingMemoryBound(to: Float.self)
                            boxedArgs.append(UnsafeMutableRawPointer(ptr))
                            deallocators.append { ptr.deinitialize(count: 1); ptr.deallocate() }
                            case 10:
                            let fv = try v.asFloat64()
                            let ptr = box(fv).assumingMemoryBound(to: Double.self)
                            boxedArgs.append(UnsafeMutableRawPointer(ptr))
                            deallocators.append { ptr.deinitialize(count: 1); ptr.deallocate() }
                            case 12: // cstring
                            switch v {
                            case .reference(let r):
                                let o = try heap.get(r)
                                guard let s = o as? KiraString else { throw VMError.typeError(expected: "String", got: v) }
                                let cstr = strdup(s.value)
                                let ptr = box(cstr).assumingMemoryBound(to: UnsafeMutablePointer<CChar>?.self)
                                boxedArgs.append(UnsafeMutableRawPointer(ptr))
                                deallocators.append {
                                    let p = ptr.pointee
                                    if let p { free(p) }
                                    ptr.deinitialize(count: 1)
                                    ptr.deallocate()
                                }
                            case .nil_:
                                let ptr = box(UnsafeMutablePointer<CChar>(nil)).assumingMemoryBound(to: UnsafeMutablePointer<CChar>?.self)
                                boxedArgs.append(UnsafeMutableRawPointer(ptr))
                                deallocators.append { ptr.deinitialize(count: 1); ptr.deallocate() }
                            default:
                                throw VMError.typeError(expected: "String|nil", got: v)
                            }
                            default: // pointer / unknown
                            let p: UnsafeMutableRawPointer?
                            switch v {
                            case .nativePointer(let np): p = np
                            case .nil_: p = nil
                            default: throw VMError.typeError(expected: "Pointer|nil", got: v)
                            }
                            let ptr = box(p).assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
                            boxedArgs.append(UnsafeMutableRawPointer(ptr))
                            deallocators.append { ptr.deinitialize(count: 1); ptr.deallocate() }
                            }
                        default:
                            let l = layout(for: desc)
                            let ptr = UnsafeMutableRawPointer.allocate(byteCount: max(1, l.size), alignment: max(1, l.alignment))
                            memset(ptr, 0, max(1, l.size))
                            try pack(v, layout: l, into: ptr)
                            boxedArgs.append(ptr)
                            deallocators.append { ptr.deallocate() }
                        }
                    }

                    defer { for d in deallocators.reversed() { d() } }

                    let retPtr: UnsafeMutableRawPointer
                    let retDeallocator: () -> Void
                    switch retDesc {
                    case .scalar(let tag) where tag == 0:
                        let ptr = UnsafeMutableRawPointer.allocate(byteCount: 8, alignment: 8)
                        retPtr = ptr
                        retDeallocator = { ptr.deallocate() }
                    case .scalar(let tag) where tag == 9:
                        let ptr = UnsafeMutablePointer<Float>.allocate(capacity: 1)
                        ptr.initialize(to: 0)
                        retPtr = UnsafeMutableRawPointer(ptr)
                        retDeallocator = { ptr.deinitialize(count: 1); ptr.deallocate() }
                    case .scalar(let tag) where tag == 10:
                        let ptr = UnsafeMutablePointer<Double>.allocate(capacity: 1)
                        ptr.initialize(to: 0)
                        retPtr = UnsafeMutableRawPointer(ptr)
                        retDeallocator = { ptr.deinitialize(count: 1); ptr.deallocate() }
                    case .scalar(let tag) where tag == 11 || tag == 12:
                        let ptr = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
                        ptr.initialize(to: nil)
                        retPtr = UnsafeMutableRawPointer(ptr)
                        retDeallocator = { ptr.deinitialize(count: 1); ptr.deallocate() }
                    case .scalar:
                        let ptr = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
                        ptr.initialize(to: 0)
                        retPtr = UnsafeMutableRawPointer(ptr)
                        retDeallocator = { ptr.deinitialize(count: 1); ptr.deallocate() }
                    case .cstruct:
                        let l = layout(for: retDesc)
                        let ptr = UnsafeMutableRawPointer.allocate(byteCount: max(1, l.size), alignment: max(1, l.alignment))
                        memset(ptr, 0, max(1, l.size))
                        retPtr = ptr
                        retDeallocator = { ptr.deallocate() }
                    }
                    defer { retDeallocator() }

                    FFICallbackTLS.currentVM = self
                    defer { FFICallbackTLS.currentVM = nil }
                    boxedArgs.withUnsafeMutableBufferPointer { argBuf in
                        ffi_call(
                            &cif,
                            unsafeBitCast(fnPtr, to: (@convention(c) () -> Void).self),
                            retPtr,
                            argBuf.baseAddress
                        )
                    }

                    let retVal: KiraValue
                    switch retDesc {
                    case .scalar(let tag) where tag == 0:
                        retVal = .nil_
                    default:
                        let l = layout(for: retDesc)
                        retVal = try unpack(layout: l, from: retPtr)
                    }

                    fiber.operandStack.push(retVal)
                    #else
                    throw VMError.invalidBytecode("ffi_call unsupported on this platform")
                    #endif

                case .fiber_new:
                    let fidx = Int(try readU16(fn, &current))
                    let fn2 = try function(at: fidx)
                    let newFiber = VMFiber(entryFunctionIndex: fidx, localCount: fn2.localCount)
                    let ref = heap.allocate(KiraFiberObject(fiber: newFiber))
                    fiber.operandStack.push(.reference(ref))
                case .fiber_resume:
                    let fiberRef = try fiber.operandStack.popRef()
                    let obj = try heap.get(fiberRef)
                    guard let fiberObj = obj as? KiraFiberObject else { throw VMError.typeError(expected: "Fiber", got: .reference(fiberRef)) }
                    let resumed = try run(fiber: fiberObj.fiber)
                    fiber.operandStack.push(resumed)
                case .yield:
                    let v = fiber.operandStack.pop()
                    fiber.state = .suspended(yieldedValue: v)
                    fiber.currentFrame = current
                    return v

                case .unwrap_or_jump:
                    let delta = try readI16(fn, &current)
                    let v = fiber.operandStack.pop()
                    if case .nil_ = v { current.ip += Int(delta) }
                    else { fiber.operandStack.push(v) }

                case .breakpoint:
                    fiber.state = .suspended(yieldedValue: .nil_)
                    fiber.currentFrame = current
                    return .nil_
                case .line_number:
                    let line = Int(try readU16(fn, &current))
                    debugger?.onLineReached(location: SourceLocationVM(file: fn.name, line: line), fiber: fiber)
                case .load_field, .store_field:
                    // Field operations not used by scaffold bytecode; implement minimal object storage.
                    let fieldIndex = Int(try readU16(fn, &current))
                    if opcode == .load_field {
                        let objRef = try fiber.operandStack.popRef()
                        let obj = try heap.get(objRef)
                        guard fieldIndex >= 0, fieldIndex < obj.fields.count else {
                            throw VMError.invalidBytecode("field index out of bounds: \(fieldIndex) (count=\(obj.fields.count))")
                        }
                        fiber.operandStack.push(obj.fields[fieldIndex])
                    } else {
                        let value = fiber.operandStack.pop()
                        let objRef = try fiber.operandStack.popRef()
                        let obj = try heap.get(objRef)
                        if fieldIndex >= obj.fields.count {
                            obj.fields += Array(repeating: .nil_, count: fieldIndex - obj.fields.count + 1)
                        }
                        obj.fields[fieldIndex] = value
                    }
                }

                // GC tick
                gcTickCounter += 1
                if gcTickCounter >= gcTickThreshold {
                    gcTickCounter = 0
                    let roots = collectRoots(fiber: fiber)
                    heap.gc.incrementalStep(roots: roots, heap: heap)
                }
            }

            // Save frame back to fiber.
            fiber.currentFrame = current
            if fiber.callStack.isEmpty { return .nil_ }
        }
    }

    private func function(at index: Int) throws -> BytecodeFunction {
        guard index >= 0 && index < module.functions.count else { throw VMError.unknownFunction(index) }
        return module.functions[index]
    }

    private func collectRoots(fiber: VMFiber) -> [ObjectRef] {
        var roots: [ObjectRef] = []
        for g in globals {
            if case .reference(let r) = g { roots.append(r) }
        }
        for v in fiber.operandStackSnapshot() {
            if case .reference(let r) = v { roots.append(r) }
        }
        for f in fiber.callStack {
            for v in f.locals {
                if case .reference(let r) = v { roots.append(r) }
            }
            if let c = f.closure { roots.append(c) }
        }
        return roots
    }

    private func pushCallFrame(fiber: VMFiber, callee: KiraValue, argCount: Int) throws {
        let (functionIndex, closureRef): (Int, ObjectRef?)
        switch callee {
        case .reference(let ref):
            let obj = try heap.get(ref)
            if let closure = obj as? KiraClosure {
                functionIndex = closure.functionIndex
                closureRef = ref
            } else if obj is KiraFiberObject {
                throw VMError.notCallable(callee)
            } else {
                throw VMError.notCallable(callee)
            }
        default:
            throw VMError.notCallable(callee)
        }
        let fn = try function(at: functionIndex)
        // Collect args.
        var args: [KiraValue] = []
        args.reserveCapacity(argCount)
        for _ in 0..<argCount { args.append(fiber.operandStack.pop()) }
        args.reverse()
        _ = fiber.operandStack.pop() // callee
        let base = fiber.operandStack.count
        var locals = Array(repeating: KiraValue.nil_, count: fn.localCount)
        for i in 0..<min(args.count, fn.paramCount) { locals[i] = args[i] }
        let frame = VMCallFrame(functionIndex: functionIndex, ip: 0, locals: locals, baseStackCount: base, closure: closureRef)
        fiber.callStack.append(frame)
    }

    private func tailCall(fiber: VMFiber, callee: KiraValue, argCount: Int) throws {
        _ = fiber.callStack.popLast()
        try pushCallFrame(fiber: fiber, callee: callee, argCount: argCount)
    }

    private func readU8(_ fn: BytecodeFunction, _ frame: inout VMCallFrame) throws -> UInt8 {
        guard frame.ip < fn.code.count else { throw VMError.invalidBytecode("EOF") }
        let v = fn.code[frame.ip]
        frame.ip += 1
        return v
    }

    private func readU16(_ fn: BytecodeFunction, _ frame: inout VMCallFrame) throws -> UInt16 {
        let hi = UInt16(try readU8(fn, &frame))
        let lo = UInt16(try readU8(fn, &frame))
        return (hi << 8) | lo
    }

    private func readI16(_ fn: BytecodeFunction, _ frame: inout VMCallFrame) throws -> Int16 {
        let hi = Int16(Int8(bitPattern: try readU8(fn, &frame)))
        let lo = Int16(Int8(bitPattern: try readU8(fn, &frame)))
        return (hi << 8) | (lo & 0xff)
    }

    private func stringify(_ v: KiraValue) -> String {
        switch v {
        case .int(let i): return String(i)
        case .float(let f): return String(f)
        case .bool(let b): return b ? "true" : "false"
        case .nil_: return "nil"
        case .nativePointer(let p): return "0x\(String(UInt(bitPattern: p), radix: 16))"
        case .reference(let r):
            guard let obj = try? heap.get(r) else { return "<ref \(r.id)>" }
            if let s = obj as? KiraString { return s.value }
            if obj.type.name == "Color", obj.fields.count >= 4,
               case .float(let rr) = obj.fields[0],
               case .float(let gg) = obj.fields[1],
               case .float(let bb) = obj.fields[2],
               case .float(let aa) = obj.fields[3] {
                return "Color(r: \(rr), g: \(gg), b: \(bb), a: \(aa))"
            }
            return "<\(obj.type.name) \(r.id)>"
        }
    }
}

private extension KiraValue {
    func asInt() throws -> Int64 {
        if case .int(let i) = self { return i }
        if case .bool(let b) = self { return b ? 1 : 0 }
        throw VMError.typeError(expected: "Int", got: self)
    }

    func asFloat64() throws -> Double {
        if case .float(let f) = self { return f }
        if case .int(let i) = self { return Double(i) }
        throw VMError.typeError(expected: "Float", got: self)
    }

    func asFloat32() throws -> Float {
        Float(try asFloat64())
    }
}

private extension VMFiber {
    func operandStackSnapshot() -> [KiraValue] {
        // Mirror snapshot is only for GC roots.
        // We keep this as a computed property to avoid exposing slots mutably.
        var tmp: [KiraValue] = []
        let n = operandStack.count
        tmp.reserveCapacity(n)
        for i in 0..<n {
            tmp.append(operandStack.peek(n - 1 - i))
        }
        return tmp
    }
}
