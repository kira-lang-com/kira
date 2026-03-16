import Foundation

public struct StaticLoader: Sendable {
    public init() {}

    public func resolve(symbolName: String) throws -> UnsafeMutableRawPointer {
        // Static symbols are resolved from the current process image.
        return try DlopenLoader().resolve(library: "", symbolName: symbolName)
    }
}

