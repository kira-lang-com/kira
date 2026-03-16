import Foundation

public enum ConstructError: Error, CustomStringConvertible, Sendable {
    case unknownConstruct(String, SourceLocation)
    case missingRequiredBlock(construct: String, block: String, SourceLocation)
    case invalidAnnotation(construct: String, annotation: String, SourceLocation)
    case scopedOnlyOnModifier(SourceLocation)

    public var description: String {
        switch self {
        case .unknownConstruct(let n, let loc):
            return "\(loc.file):\(loc.line):\(loc.column): error: unknown construct '\(n)'"
        case .missingRequiredBlock(let construct, let block, let loc):
            return "\(loc.file):\(loc.line):\(loc.column): error: \(construct) requires a \(block) {} block"
        case .invalidAnnotation(let construct, let ann, let loc):
            return "\(loc.file):\(loc.line):\(loc.column): error: @\(ann) is not valid in \(construct)"
        case .scopedOnlyOnModifier(let loc):
            return "\(loc.file):\(loc.line):\(loc.column): error: @Scoped can only annotate modifier fields"
        }
    }
}

public struct AnnotationValidator {
    public init() {}

    public func validate(module: ModuleAST, registry: ConstructRegistry) throws {
        for decl in module.declarations {
            if case .constructInstance(let inst) = decl {
                try validate(instance: inst, registry: registry)
            }
        }
    }

    public func validate(instance: ConstructInstanceDecl, registry: ConstructRegistry) throws {
        guard let def = registry.lookup(instance.constructName) else {
            throw ConstructError.unknownConstruct(instance.constructName, instance.range.start)
        }

        var presentBlocks: Set<String> = []
        for m in instance.members {
            if case .block(let name, _) = m.kind { presentBlocks.insert(name) }
        }
        for required in def.requiredBlocks where !presentBlocks.contains(required) {
            throw ConstructError.missingRequiredBlock(construct: def.name, block: required, instance.range.start)
        }

        // Validate field annotations.
        for m in instance.members {
            guard case .field(let field) = m.kind else { continue }
            for ann in field.annotations {
                if !def.allowedAnnotations.contains(ann.name) {
                    throw ConstructError.invalidAnnotation(construct: def.name, annotation: ann.name, ann.range.start)
                }
            }
            let isScoped = field.annotations.contains(where: { $0.name == "Scoped" })
            if isScoped {
                // Scoped is only meaningful for modifiers declared by the construct.
                let isModifier = def.modifiers.contains(where: { $0.name == field.name })
                if !isModifier {
                    throw ConstructError.scopedOnlyOnModifier(field.range.start)
                }
            }
        }
    }
}

