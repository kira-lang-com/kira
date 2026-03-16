import Foundation

public struct FunctionSymbol: Hashable, Sendable {
    public enum ExecutionMode: Hashable, Sendable { case auto, native, runtime }

    public var name: String
    public var type: KiraType
    public var executionMode: ExecutionMode
    public var range: SourceRange

    public init(name: String, type: KiraType, executionMode: ExecutionMode, range: SourceRange) {
        self.name = name
        self.type = type
        self.executionMode = executionMode
        self.range = range
    }
}

public struct SymbolTable: Sendable {
    public private(set) var functions: [String: FunctionSymbol] = [:]
    public private(set) var types: Set<String> = []
    public private(set) var methods: [String: [String: KiraType]] = [:] // TypeName -> method -> fnType

    public init() {}

    public mutating func addType(_ name: String) { types.insert(name) }

    public mutating func addFunction(_ sym: FunctionSymbol) throws {
        if functions[sym.name] != nil {
            throw SemanticError.duplicateSymbol(sym.name, sym.range.start)
        }
        functions[sym.name] = sym
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

