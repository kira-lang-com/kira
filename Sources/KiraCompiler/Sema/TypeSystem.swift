import Foundation

public enum KiraType: Hashable, Sendable, CustomStringConvertible {
    case int
    case float
    case double
    case bool
    case string
    case void
    case named(String)
    indirect case pointer(KiraType)
    indirect case array(KiraType)
    indirect case dictionary(key: KiraType, value: KiraType)
    indirect case optional(KiraType)
    indirect case function(params: [KiraType], returns: KiraType)
    case unknown

    public var description: String {
        switch self {
        case .int: return "Int"
        case .float: return "Float"
        case .double: return "Double"
        case .bool: return "Bool"
        case .string: return "String"
        case .void: return "Void"
        case .named(let n): return n
        case .pointer(let t): return "CPointer<\(t)>"
        case .array(let t): return "[\(t)]"
        case .dictionary(let k, let v): return "[\(k): \(v)]"
        case .optional(let t): return "\(t)?"
        case .function(let ps, let r): return "(\(ps.map(\.description).joined(separator: ", "))) -> \(r)"
        case .unknown: return "<unknown>"
        }
    }
}

public struct TypeSystem: Sendable {
    public init() {}

    public func resolve(_ ref: TypeRef) -> KiraType {
        switch ref.kind {
        case .named(let n):
            switch n {
            case "Int": return .int
            case "Float": return .float
            case "Double": return .double
            case "Bool": return .bool
            case "String": return .string
            case "Void": return .void
            default: return .named(n)
            }
        case .applied(let base, let args):
            if base == "CPointer", let first = args.first {
                return .pointer(resolve(first))
            }
            let rendered = "\(base)<\(args.map { resolve($0).description }.joined(separator: ", "))>"
            return .named(rendered)
        case .array(let inner):
            return .array(resolve(inner))
        case .dictionary(let key, let value):
            return .dictionary(key: resolve(key), value: resolve(value))
        case .optional(let inner):
            return .optional(resolve(inner))
        case .function(let params, let returns):
            return .function(params: params.map(resolve), returns: resolve(returns))
        }
    }
}
