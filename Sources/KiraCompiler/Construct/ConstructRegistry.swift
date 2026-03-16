import Foundation

public struct ConstructRegistry: Sendable {
    private var constructs: [String: ConstructDefinition] = [:]

    public init() {}

    public mutating func register(_ decl: ConstructDecl) {
        constructs[decl.name] = ConstructDefinition(from: decl)
    }

    public mutating func register(_ def: ConstructDefinition) {
        constructs[def.name] = def
    }

    public func lookup(_ name: String) -> ConstructDefinition? {
        constructs[name]
    }

    public var all: [ConstructDefinition] { Array(constructs.values) }
}

