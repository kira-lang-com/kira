import Foundation

#if canImport(Clibffi)
import Clibffi
#endif

public enum CKiraType: Hashable, Sendable {
    case int8, int16, int32, int64
    case uint8, uint16, uint32, uint64
    case float32, float64
    case pointer
    case void
}

public enum LibFFIError: Error, CustomStringConvertible, Sendable {
    case unavailable

    public var description: String { "error: libffi is not available in this build" }
}

public struct LibFFIBridge: Sendable {
    public init() {}

    #if canImport(Clibffi)
    public func ffiTypePointer(for type: CKiraType) -> UnsafeMutableRawPointer {
        let ptr: UnsafeMutablePointer<ffi_type>
        switch type {
        case .int8: ptr = UnsafeMutablePointer(mutating: &ffi_type_sint8)
        case .int16: ptr = UnsafeMutablePointer(mutating: &ffi_type_sint16)
        case .int32: ptr = UnsafeMutablePointer(mutating: &ffi_type_sint32)
        case .int64: ptr = UnsafeMutablePointer(mutating: &ffi_type_sint64)
        case .uint8: ptr = UnsafeMutablePointer(mutating: &ffi_type_uint8)
        case .uint16: ptr = UnsafeMutablePointer(mutating: &ffi_type_uint16)
        case .uint32: ptr = UnsafeMutablePointer(mutating: &ffi_type_uint32)
        case .uint64: ptr = UnsafeMutablePointer(mutating: &ffi_type_uint64)
        case .float32: ptr = UnsafeMutablePointer(mutating: &ffi_type_float)
        case .float64: ptr = UnsafeMutablePointer(mutating: &ffi_type_double)
        case .pointer: ptr = UnsafeMutablePointer(mutating: &ffi_type_pointer)
        case .void: ptr = UnsafeMutablePointer(mutating: &ffi_type_void)
        }
        return UnsafeMutableRawPointer(ptr)
    }
    #else
    public func ffiTypePointer(for type: CKiraType) throws -> UnsafeMutableRawPointer {
        _ = type
        throw LibFFIError.unavailable
    }
    #endif
}
