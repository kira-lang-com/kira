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

public struct MethodSymbol: Hashable, Sendable {
    public var name: String
    public var loweredName: String
    public var parameterLabels: [String?]
    public var type: KiraType

    public init(name: String, loweredName: String, parameterLabels: [String?], type: KiraType) {
        self.name = name
        self.loweredName = loweredName
        self.parameterLabels = parameterLabels
        self.type = type
    }
}

public struct EnumCaseSymbol: Hashable, Sendable {
    public struct AssociatedValue: Hashable, Sendable {
        public var label: String?
        public var type: KiraType

        public init(label: String?, type: KiraType) {
            self.label = label
            self.type = type
        }
    }

    public var name: String
    public var tag: Int64
    public var associatedValues: [AssociatedValue]

    public init(name: String, tag: Int64, associatedValues: [AssociatedValue]) {
        self.name = name
        self.tag = tag
        self.associatedValues = associatedValues
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
        case cstruct = 13
        case pointerTo = 14
    }

    public struct TypeEncoding: Sendable, Equatable {
        public var bytes: [UInt8]

        public init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        public static func scalar(_ tag: TypeTag) -> TypeEncoding {
            TypeEncoding(bytes: [tag.rawValue])
        }

        public static func cStruct(_ fields: [TypeEncoding]) -> TypeEncoding {
            var out: [UInt8] = [TypeTag.cstruct.rawValue, UInt8(clamping: fields.count)]
            for f in fields { out.append(contentsOf: f.bytes) }
            return TypeEncoding(bytes: out)
        }

        public static func pointerTo(_ pointee: TypeEncoding) -> TypeEncoding {
            TypeEncoding(bytes: [TypeTag.pointerTo.rawValue] + pointee.bytes)
        }
    }

    public var library: String?
    public var symbol: String
    public var linkage: FFILinkage
    public var returnType: TypeEncoding
    public var argumentTypes: [TypeEncoding]

    public init(library: String?, symbol: String, linkage: FFILinkage, returnType: TypeEncoding, argumentTypes: [TypeEncoding]) {
        self.library = library
        self.symbol = symbol
        self.linkage = linkage
        self.returnType = returnType
        self.argumentTypes = argumentTypes
    }
}

public struct SymbolTable: Sendable {
    public private(set) var functions: [String: FunctionSymbol] = [:]
    public private(set) var globals: [String: KiraType] = [:]
    public private(set) var types: Set<String> = []
    public private(set) var typeAliases: [String: KiraType] = [:]
    public private(set) var enumCases: [String: [String: EnumCaseSymbol]] = [:]
    public private(set) var protocolRequirements: [String: [String: MethodSymbol]] = [:]
    public private(set) var conformances: [String: Set<String>] = [:]
    public private(set) var methods: [String: [String: MethodSymbol]] = [:] // TypeName -> method -> symbol
    public private(set) var staticMethods: [String: [String: MethodSymbol]] = [:] // TypeName -> method -> symbol
    public private(set) var ffi: [String: FFIPrototype] = [:]
    public private(set) var cStructTypes: Set<String> = []
    public private(set) var fields: [String: [String: (index: Int, type: KiraType)]] = [:] // TypeName -> field -> (index, type)
    public private(set) var staticFields: [String: [String: KiraType]] = [:]

    public init() {}

    public mutating func addType(_ name: String) { types.insert(name) }

    public mutating func addTypeAlias(_ name: String, target: KiraType) {
        typeAliases[name] = target
    }

    public mutating func addEnumCases(
        typeName: String,
        cases: [(name: String, tag: Int64, associatedValues: [EnumCaseSymbol.AssociatedValue], range: SourceRange)]
    ) throws {
        var map = enumCases[typeName] ?? [:]
        for enumCase in cases {
            if map[enumCase.name] != nil {
                throw SemanticError.duplicateSymbol(enumCase.name, enumCase.range.start)
            }
            map[enumCase.name] = EnumCaseSymbol(
                name: enumCase.name,
                tag: enumCase.tag,
                associatedValues: enumCase.associatedValues
            )
        }
        enumCases[typeName] = map
    }

    public mutating func addProtocolRequirements(
        protocolName: String,
        requirements: [(name: String, parameterLabels: [String?], type: KiraType)]
    ) {
        var map: [String: MethodSymbol] = [:]
        for requirement in requirements {
            map[requirement.name] = MethodSymbol(
                name: requirement.name,
                loweredName: requirement.name,
                parameterLabels: requirement.parameterLabels,
                type: requirement.type
            )
        }
        protocolRequirements[protocolName] = map
    }

    public mutating func addConformance(typeName: String, protocolName: String) {
        conformances[typeName, default: []].insert(protocolName)
    }

    public mutating func addFunction(_ sym: FunctionSymbol) throws {
        if functions[sym.name] != nil {
            throw SemanticError.duplicateSymbol(sym.name, sym.range.start)
        }
        functions[sym.name] = sym
    }

    public mutating func addGlobal(name: String, type: KiraType, range: SourceRange) throws {
        if functions[name] != nil || globals[name] != nil {
            throw SemanticError.duplicateSymbol(name, range.start)
        }
        globals[name] = type
    }

    public mutating func addFFIPrototype(functionName: String, proto: FFIPrototype) {
        ffi[functionName] = proto
    }

    public mutating func addMethod(typeName: String, methodName: String, loweredName: String, parameterLabels: [String?], methodType: KiraType) {
        methods[typeName, default: [:]][methodName] = MethodSymbol(
            name: methodName,
            loweredName: loweredName,
            parameterLabels: parameterLabels,
            type: methodType
        )
    }

    public mutating func addStaticMethod(typeName: String, methodName: String, loweredName: String, parameterLabels: [String?], methodType: KiraType) {
        staticMethods[typeName, default: [:]][methodName] = MethodSymbol(
            name: methodName,
            loweredName: loweredName,
            parameterLabels: parameterLabels,
            type: methodType
        )
    }

    public mutating func addFields(typeName: String, fields: [(name: String, type: KiraType)]) {
        var map: [String: (index: Int, type: KiraType)] = [:]
        map.reserveCapacity(fields.count)
        for (i, f) in fields.enumerated() {
            map[f.name] = (i, f.type)
        }
        self.fields[typeName] = map
    }

    public mutating func addStaticField(typeName: String, fieldName: String, type: KiraType) {
        staticFields[typeName, default: [:]][fieldName] = type
    }

    public mutating func addCStruct(typeName: String, fields: [(name: String, type: KiraType)]) {
        cStructTypes.insert(typeName)
        addFields(typeName: typeName, fields: fields)
    }

    public func lookupValue(_ name: String) -> KiraType? {
        if let fn = functions[name] { return fn.type }
        if let g = globals[name] { return g }
        return nil
    }

    public func lookupMethod(typeName: String, name: String) -> MethodSymbol? {
        methods[typeName]?[name]
    }

    public func lookupStaticMethod(typeName: String, name: String) -> MethodSymbol? {
        staticMethods[typeName]?[name]
    }

    public func lookupEnumCase(typeName: String, name: String) -> EnumCaseSymbol? {
        enumCases[typeName]?[name]
    }

    public func lookupProtocolRequirement(protocolName: String, name: String) -> MethodSymbol? {
        protocolRequirements[protocolName]?[name]
    }

    public func typeConformsToProtocol(typeName: String, protocolName: String) -> Bool {
        conformances[typeName]?.contains(protocolName) == true
    }

    public func isProtocol(_ name: String) -> Bool {
        protocolRequirements[name] != nil
    }

    public func lookupField(typeName: String, name: String) -> (index: Int, type: KiraType)? {
        fields[typeName]?[name]
    }

    public func lookupStaticField(typeName: String, name: String) -> KiraType? {
        staticFields[typeName]?[name]
    }
}
