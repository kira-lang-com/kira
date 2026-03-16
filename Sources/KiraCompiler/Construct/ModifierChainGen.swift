import Foundation

public struct ModifierSignature: Sendable {
    public var name: String
    public var parameterType: TypeRef?
    public var isScoped: Bool

    public init(name: String, parameterType: TypeRef?, isScoped: Bool) {
        self.name = name
        self.parameterType = parameterType
        self.isScoped = isScoped
    }
}

public struct ModifierChainGen {
    public init() {}

    public func generate(for construct: ConstructDefinition) -> [ModifierSignature] {
        construct.modifiers.map { m in
            ModifierSignature(name: m.name, parameterType: m.type, isScoped: m.isScoped)
        }
    }
}
