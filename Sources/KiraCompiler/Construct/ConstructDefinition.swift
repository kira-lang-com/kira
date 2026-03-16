import Foundation

public struct ConstructDefinition: Sendable {
    public struct Modifier: Sendable {
        public var name: String
        public var type: TypeRef?
        public var defaultValue: Expr?
        public var isScoped: Bool

        public init(name: String, type: TypeRef?, defaultValue: Expr?, isScoped: Bool) {
            self.name = name
            self.type = type
            self.defaultValue = defaultValue
            self.isScoped = isScoped
        }
    }

    public var name: String
    public var allowedAnnotations: Set<String>
    public var requiredBlocks: Set<String>
    public var modifiers: [Modifier]

    public init(name: String, allowedAnnotations: Set<String>, requiredBlocks: Set<String>, modifiers: [Modifier]) {
        self.name = name
        self.allowedAnnotations = allowedAnnotations
        self.requiredBlocks = requiredBlocks
        self.modifiers = modifiers
    }

    public init(from decl: ConstructDecl) {
        self.name = decl.name
        self.allowedAnnotations = Set(decl.allowedAnnotations)
        self.requiredBlocks = Set(decl.requiredBlocks)
        self.modifiers = decl.modifiers.map { .init(name: $0.name, type: $0.type, defaultValue: $0.defaultValue, isScoped: $0.isScoped) }
    }
}
