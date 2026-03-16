import Foundation

public final class Scope: @unchecked Sendable {
    private var values: [String: KiraType] = [:]
    public let parent: Scope?

    public init(parent: Scope? = nil) {
        self.parent = parent
    }

    public func define(_ name: String, type: KiraType) throws {
        if values[name] != nil {
            throw SemanticError.duplicateSymbol(name, SourceLocation(file: "<unknown>", offset: 0, line: 1, column: 1))
        }
        values[name] = type
    }

    public func lookup(_ name: String) -> KiraType? {
        if let t = values[name] { return t }
        return parent?.lookup(name)
    }
}

