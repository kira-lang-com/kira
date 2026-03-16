import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct DlopenLoader: Sendable {
    public init() {}

    public func resolve(library: String, symbolName: String) throws -> UnsafeMutableRawPointer {
        #if os(Windows)
        throw FFIError.unsupportedOnPlatform("dynamic library loading is not yet implemented on Windows in this scaffold")
        #else
        let handle: UnsafeMutableRawPointer?
        if library.isEmpty {
            handle = dlopen(nil, RTLD_NOW)
        } else {
            handle = dlopen(library, RTLD_NOW)
        }
        guard let handle else { throw FFIError.libraryLoadFailed(library) }
        guard let sym = dlsym(handle, symbolName) else { throw FFIError.symbolNotFound(symbolName) }
        return sym
        #endif
    }
}

