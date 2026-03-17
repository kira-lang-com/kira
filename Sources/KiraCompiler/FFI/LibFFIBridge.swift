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

public enum CKiraValue: @unchecked Sendable {
    case int8(Int8)
    case int16(Int16)
    case int32(Int32)
    case int64(Int64)
    case uint8(UInt8)
    case uint16(UInt16)
    case uint32(UInt32)
    case uint64(UInt64)
    case float32(Float)
    case float64(Double)
    case pointer(UnsafeMutableRawPointer?)
    case void
}

public enum LibFFIError: Error, CustomStringConvertible, Sendable {
    case unavailable
    case cifPreparationFailed

    public var description: String {
        switch self {
        case .unavailable:
            return "error: libffi is not available in this build"
        case .cifPreparationFailed:
            return "error: ffi_cif preparation failed"
        }
    }
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

    public func callFunction(
        pointer: UnsafeMutableRawPointer,
        returnType: CKiraType,
        arguments: [(type: CKiraType, value: CKiraValue)]
    ) throws -> CKiraValue {
        var argTypes: [UnsafeMutablePointer<ffi_type>?] = arguments.map { arg in
            ffiTypePointer(for: arg.type).assumingMemoryBound(to: ffi_type.self)
        }

        var cif = ffi_cif()
        let status: ffi_status = argTypes.withUnsafeMutableBufferPointer { argTypeBuf in
            let retTypePtr = ffiTypePointer(for: returnType).assumingMemoryBound(to: ffi_type.self)
            return ffi_prep_cif(
                &cif,
                FFI_DEFAULT_ABI,
                UInt32(arguments.count),
                retTypePtr,
                argTypeBuf.baseAddress
            )
        }
        guard status == FFI_OK else { throw LibFFIError.cifPreparationFailed }

        func box<T>(_ value: T) -> UnsafeMutableRawPointer {
            let ptr = UnsafeMutablePointer<T>.allocate(capacity: 1)
            ptr.initialize(to: value)
            return UnsafeMutableRawPointer(ptr)
        }

        var argPtrs: [UnsafeMutableRawPointer?] = []
        argPtrs.reserveCapacity(arguments.count)
        var argDeallocators: [() -> Void] = []
        argDeallocators.reserveCapacity(arguments.count)

        for arg in arguments {
            switch arg.value {
            case .int8(let v):
                let ptr = box(v).assumingMemoryBound(to: Int8.self)
                argPtrs.append(UnsafeMutableRawPointer(ptr))
                argDeallocators.append {
                    ptr.deinitialize(count: 1)
                    ptr.deallocate()
                }
            case .int16(let v):
                let ptr = box(v).assumingMemoryBound(to: Int16.self)
                argPtrs.append(UnsafeMutableRawPointer(ptr))
                argDeallocators.append {
                    ptr.deinitialize(count: 1)
                    ptr.deallocate()
                }
            case .int32(let v):
                let ptr = box(v).assumingMemoryBound(to: Int32.self)
                argPtrs.append(UnsafeMutableRawPointer(ptr))
                argDeallocators.append {
                    ptr.deinitialize(count: 1)
                    ptr.deallocate()
                }
            case .int64(let v):
                let ptr = box(v).assumingMemoryBound(to: Int64.self)
                argPtrs.append(UnsafeMutableRawPointer(ptr))
                argDeallocators.append {
                    ptr.deinitialize(count: 1)
                    ptr.deallocate()
                }
            case .uint8(let v):
                let ptr = box(v).assumingMemoryBound(to: UInt8.self)
                argPtrs.append(UnsafeMutableRawPointer(ptr))
                argDeallocators.append {
                    ptr.deinitialize(count: 1)
                    ptr.deallocate()
                }
            case .uint16(let v):
                let ptr = box(v).assumingMemoryBound(to: UInt16.self)
                argPtrs.append(UnsafeMutableRawPointer(ptr))
                argDeallocators.append {
                    ptr.deinitialize(count: 1)
                    ptr.deallocate()
                }
            case .uint32(let v):
                let ptr = box(v).assumingMemoryBound(to: UInt32.self)
                argPtrs.append(UnsafeMutableRawPointer(ptr))
                argDeallocators.append {
                    ptr.deinitialize(count: 1)
                    ptr.deallocate()
                }
            case .uint64(let v):
                let ptr = box(v).assumingMemoryBound(to: UInt64.self)
                argPtrs.append(UnsafeMutableRawPointer(ptr))
                argDeallocators.append {
                    ptr.deinitialize(count: 1)
                    ptr.deallocate()
                }
            case .float32(let v):
                let ptr = box(v).assumingMemoryBound(to: Float.self)
                argPtrs.append(UnsafeMutableRawPointer(ptr))
                argDeallocators.append {
                    ptr.deinitialize(count: 1)
                    ptr.deallocate()
                }
            case .float64(let v):
                let ptr = box(v).assumingMemoryBound(to: Double.self)
                argPtrs.append(UnsafeMutableRawPointer(ptr))
                argDeallocators.append {
                    ptr.deinitialize(count: 1)
                    ptr.deallocate()
                }
            case .pointer(let p):
                let ptr = box(p).assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
                argPtrs.append(UnsafeMutableRawPointer(ptr))
                argDeallocators.append {
                    ptr.deinitialize(count: 1)
                    ptr.deallocate()
                }
            case .void:
                let ptr = UnsafeMutableRawPointer.allocate(byteCount: 8, alignment: 8)
                argPtrs.append(ptr)
                argDeallocators.append { ptr.deallocate() }
            }
        }

        defer {
            for d in argDeallocators.reversed() { d() }
        }

        let retPtr: UnsafeMutableRawPointer
        let retDeallocator: () -> Void
        switch returnType {
        case .void:
            let ptr = UnsafeMutableRawPointer.allocate(byteCount: 8, alignment: 8)
            retPtr = ptr
            retDeallocator = { ptr.deallocate() }
        case .int8, .int16, .int32, .int64, .uint8, .uint16, .uint32, .uint64:
            let ptr = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
            ptr.initialize(to: 0)
            retPtr = UnsafeMutableRawPointer(ptr)
            retDeallocator = {
                ptr.deinitialize(count: 1)
                ptr.deallocate()
            }
        case .float32:
            let ptr = UnsafeMutablePointer<Float>.allocate(capacity: 1)
            ptr.initialize(to: 0)
            retPtr = UnsafeMutableRawPointer(ptr)
            retDeallocator = {
                ptr.deinitialize(count: 1)
                ptr.deallocate()
            }
        case .float64:
            let ptr = UnsafeMutablePointer<Double>.allocate(capacity: 1)
            ptr.initialize(to: 0)
            retPtr = UnsafeMutableRawPointer(ptr)
            retDeallocator = {
                ptr.deinitialize(count: 1)
                ptr.deallocate()
            }
        case .pointer:
            let ptr = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
            ptr.initialize(to: nil)
            retPtr = UnsafeMutableRawPointer(ptr)
            retDeallocator = {
                ptr.deinitialize(count: 1)
                ptr.deallocate()
            }
        }
        defer { retDeallocator() }

        argPtrs.withUnsafeMutableBufferPointer { argBuf in
            ffi_call(
                &cif,
                unsafeBitCast(pointer, to: (@convention(c) () -> Void).self),
                retPtr,
                argBuf.baseAddress
            )
        }

        switch returnType {
        case .void:
            return .void
        case .int8:
            let v = retPtr.load(as: Int64.self)
            return .int8(Int8(v))
        case .int16:
            let v = retPtr.load(as: Int64.self)
            return .int16(Int16(v))
        case .int32:
            let v = retPtr.load(as: Int64.self)
            return .int32(Int32(v))
        case .int64:
            let v = retPtr.load(as: Int64.self)
            return .int64(v)
        case .uint8:
            let v = UInt64(bitPattern: retPtr.load(as: Int64.self))
            return .uint8(UInt8(v))
        case .uint16:
            let v = UInt64(bitPattern: retPtr.load(as: Int64.self))
            return .uint16(UInt16(v))
        case .uint32:
            let v = UInt64(bitPattern: retPtr.load(as: Int64.self))
            return .uint32(UInt32(v))
        case .uint64:
            let v = UInt64(bitPattern: retPtr.load(as: Int64.self))
            return .uint64(v)
        case .float32:
            let v = retPtr.load(as: Float.self)
            return .float32(v)
        case .float64:
            let v = retPtr.load(as: Double.self)
            return .float64(v)
        case .pointer:
            let v = retPtr.load(as: UnsafeMutableRawPointer?.self)
            return .pointer(v)
        }
    }
    #else
    public func ffiTypePointer(for type: CKiraType) throws -> UnsafeMutableRawPointer {
        _ = type
        throw LibFFIError.unavailable
    }

    public func callFunction(
        pointer: UnsafeMutableRawPointer,
        returnType: CKiraType,
        arguments: [(type: CKiraType, value: CKiraValue)]
    ) throws -> CKiraValue {
        _ = pointer
        _ = returnType
        _ = arguments
        throw LibFFIError.unavailable
    }
    #endif
}
