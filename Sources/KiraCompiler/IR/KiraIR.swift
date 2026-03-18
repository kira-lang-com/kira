import Foundation

public struct KiraIRModule: Sendable {
    public var functions: [KiraIRFunction]

    public init(functions: [KiraIRFunction]) {
        self.functions = functions
    }
}

public struct KiraIRFunction: Sendable {
    public enum ExecutionMode: Sendable { case auto, native, runtime }

    public var name: String
    public var params: [KiraType]
    public var returnType: KiraType
    public var localCount: Int
    public var maxStackDepth: Int
    public var instructions: [KiraIRInst]
    public var executionMode: ExecutionMode

    public init(name: String, params: [KiraType], returnType: KiraType, localCount: Int, maxStackDepth: Int, instructions: [KiraIRInst], executionMode: ExecutionMode) {
        self.name = name
        self.params = params
        self.returnType = returnType
        self.localCount = localCount
        self.maxStackDepth = maxStackDepth
        self.instructions = instructions
        self.executionMode = executionMode
    }
}

public enum KiraIRInst: Sendable, Equatable {
    case pushInt(Int64)
    case pushFloat(Double)
    case pushString(String)
    case pushBool(Bool)
    case pushNil

    case pop
    case dup
    case swap

    case loadLocal(UInt8)
    case storeLocal(UInt8)
    case loadGlobalSymbol(String)
    case storeGlobalSymbol(String)

    case newObject(fieldCount: UInt16)
    case makeFFIArray(count: UInt16, elementType: [UInt8])
    case loadField(UInt16)
    case storeField(UInt16)

    case addInt
    case subInt
    case mulInt
    case divInt
    case modInt
    case negInt

    case addFloat
    case subFloat
    case mulFloat
    case divFloat
    case negFloat

    case intToFloat
    case floatToInt

    case eqInt
    case eqFloat
    case ltInt
    case ltFloat
    case gtInt
    case gtFloat

    case andBool
    case orBool
    case notBool

    case jump(Int16)
    case jumpIfTrue(Int16)
    case jumpIfFalse(Int16)

    case call(argCount: UInt8)
    case ffiLoad
    case ffiCall(argCount: UInt8, returnType: [UInt8], argumentTypes: [[UInt8]])
    case ffiCallback0
    case ffiCallback1I32
    case print
    case makeColor
    case ret
}
