import Foundation

public struct FunctionSymbol: Hashable, Sendable {
    public enum ExecutionMode: Hashable, Sendable { case auto, native, runtime }

    public var name: String
    public var type: KiraType
    public var executionMode: ExecutionMode
    public var isExtern: Bool
    public var range: SourceRange

    public init(name: String, type: KiraType, executionMode: ExecutionMode, isExtern: Bool, range: SourceRange) {
        self.name = name
        self.type = type
        self.executionMode = executionMode
        self.isExtern = isExtern
        self.range = range
    }
}

public struct FFIPrototype: Sendable {
    public enum TypeTag: UInt8, Sendable {
        case void = 0
        case int8 = 1, int16 = 2, int32 = 3, int64 = 4
        case uint8 = 5, uint16 = 6, uint32 = 7, uint64 = 8
        case float32 = 9, float64 = 10
        case pointer = 11
        case cstring = 12
    }

    public var library: String?
    public var symbol: String
    public var linkage: FFILinkage
    public var returnType: TypeTag
    public var argumentTypes: [TypeTag]

    public init(library: String?, symbol: String, linkage: FFILinkage, returnType: TypeTag, argumentTypes: [TypeTag]) {
        self.library = library
        self.symbol = symbol
        self.linkage = linkage
        self.returnType = returnType
        self.argumentTypes = argumentTypes
    }
}

public struct SymbolTable: Sendable {
    public private(set) var functions: [String: FunctionSymbol] = [:]
    public private(set) var types: Set<String> = []
    public private(set) var methods: [String: [String: KiraType]] = [:] // TypeName -> method -> fnType
    public private(set) var ffi: [String: FFIPrototype] = [:]

    public init() {}

    public mutating func addType(_ name: String) { types.insert(name) }

    public mutating func addFunction(_ sym: FunctionSymbol) throws {
        if functions[sym.name] != nil {
            throw SemanticError.duplicateSymbol(sym.name, sym.range.start)
        }
        functions[sym.name] = sym
    }

    public mutating func addFFIPrototype(functionName: String, proto: FFIPrototype) {
        ffi[functionName] = proto
    }

    public mutating func addMethod(typeName: String, methodName: String, methodType: KiraType) {
        methods[typeName, default: [:]][methodName] = methodType
    }

    public func lookupValue(_ name: String) -> KiraType? {
        if let fn = functions[name] { return fn.type }
        return nil
    }

    public func lookupMethod(typeName: String, name: String) -> KiraType? {
        methods[typeName]?[name]
    }
}
