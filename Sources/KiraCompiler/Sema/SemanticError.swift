import Foundation

public enum SemanticError: Error, CustomStringConvertible, Sendable {
    case duplicateSymbol(String, SourceLocation)
    case unknownIdentifier(String, SourceLocation)
    case notCallable(SourceLocation)
    case typeMismatch(expected: KiraType, got: KiraType, SourceLocation, hint: String?)
    case runtimeNotSupportedOnWasm(SourceLocation)
    case memberNotFound(base: KiraType, name: String, SourceLocation)
    case protocolConformanceMissing(typeName: String, protocolName: String, requirement: String, SourceLocation)
    case protocolConformanceMismatch(typeName: String, protocolName: String, requirement: String, candidate: String, SourceLocation)

    public var description: String {
        switch self {
        case .duplicateSymbol(let name, let loc):
            return "\(loc.file):\(loc.line):\(loc.column): error: duplicate symbol '\(name)'"
        case .unknownIdentifier(let name, let loc):
            return "\(loc.file):\(loc.line):\(loc.column): error: unknown identifier '\(name)'"
        case .notCallable(let loc):
            return "\(loc.file):\(loc.line):\(loc.column): error: value is not callable"
        case .typeMismatch(let expected, let got, let loc, let hint):
            var msg = "\(loc.file):\(loc.line):\(loc.column): error: expected \(expected), got \(got)"
            if let hint { msg += " — hint: \(hint)" }
            return msg
        case .runtimeNotSupportedOnWasm(let loc):
            return "\(loc.file):\(loc.line):\(loc.column): error: @Runtime is not supported on WebAssembly. Use @Native or remove the annotation."
        case .memberNotFound(let base, let name, let loc):
            return "\(loc.file):\(loc.line):\(loc.column): error: '\(base)' has no member '\(name)'"
        case .protocolConformanceMissing(let typeName, let protocolName, let requirement, let loc):
            return "\(loc.file):\(loc.line):\(loc.column): error: type '\(typeName)' does not conform to protocol '\(protocolName)'\nmissing: \(requirement)"
        case .protocolConformanceMismatch(let typeName, let protocolName, let requirement, let candidate, let loc):
            return "\(loc.file):\(loc.line):\(loc.column): error: type '\(typeName)' does not conform to protocol '\(protocolName)'\nrequired: \(requirement)\nfound: \(candidate)"
        }
    }
}
