import Foundation

public enum FFILinkage: Hashable, Sendable {
    case dynamic
    case `static`
}

public struct FFISymbol: Hashable, Sendable {
    public var library: String?
    public var name: String
    public var linkage: FFILinkage

    public init(library: String?, name: String, linkage: FFILinkage) {
        self.library = library
        self.name = name
        self.linkage = linkage
    }
}

public enum FFIError: Error, CustomStringConvertible, Sendable {
    case unsupportedOnPlatform(String)
    case libraryLoadFailed(String)
    case symbolNotFound(String)

    public var description: String {
        switch self {
        case .unsupportedOnPlatform(let msg): return "error: \(msg)"
        case .libraryLoadFailed(let lib): return "error: failed to load library '\(lib)'"
        case .symbolNotFound(let sym): return "error: symbol not found '\(sym)'"
        }
    }
}

public struct FFIResolver: Sendable {
    public init() {}

    public func resolve(_ symbol: FFISymbol, target: PlatformTarget) throws -> UnsafeMutableRawPointer {
        switch target {
        case .iOS:
            if symbol.linkage != .static {
                // iOS restriction warning is emitted at higher layers; resolution falls back to error here.
                throw FFIError.unsupportedOnPlatform("dlopen is not permitted on iOS App Store builds. Add linkage: .static.")
            }
            return try StaticLoader().resolve(symbolName: symbol.name)
        case .wasm32:
            throw FFIError.unsupportedOnPlatform("FFI is not available in wasm32 runtime execution; use @Native wasm imports.")
        default:
            if symbol.linkage == .static {
                return try StaticLoader().resolve(symbolName: symbol.name)
            }
            let lib = symbol.library ?? ""
            return try DlopenLoader().resolve(library: lib, symbolName: symbol.name)
        }
    }
}

