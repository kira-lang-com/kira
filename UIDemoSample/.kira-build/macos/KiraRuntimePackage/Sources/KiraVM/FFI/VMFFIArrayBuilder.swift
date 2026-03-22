import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WinSDK)
import WinSDK
#endif

private indirect enum VMFFIArrayTypeDesc {
    case scalar(UInt8)
    case cstruct([VMFFIArrayTypeDesc])
    case pointer(VMFFIArrayTypeDesc)
}

private enum VMFFIArrayLayout {
    case scalar(tag: UInt8, size: Int, alignment: Int)
    case cstruct(fields: [VMFFIArrayLayout], offsets: [Int], size: Int, alignment: Int)

    var size: Int {
        switch self {
        case .scalar(_, let size, _):
            return size
        case .cstruct(_, _, let size, _):
            return size
        }
    }

    var alignment: Int {
        switch self {
        case .scalar(_, _, let alignment):
            return alignment
        case .cstruct(_, _, _, let alignment):
            return alignment
        }
    }
}

extension VirtualMachine {
    func executeMakeFFIArray(fn: BytecodeFunction, frame: inout VMCallFrame, fiber: VMFiber) throws {
        let count = Int(try readFFIArrayU16(fn: fn, frame: &frame))
        let elementDesc = try readFFIArrayTypeDesc(fn: fn, frame: &frame)
        let elementLayout = ffiArrayLayout(for: elementDesc)
        let stride = ffiArrayAlignUp(elementLayout.size, to: elementLayout.alignment)
        let totalSize = max(1, stride * max(0, count))
        let alignment = max(1, elementLayout.alignment)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: totalSize, alignment: alignment)
        memset(buffer, 0, totalSize)

        var values: [KiraValue] = []
        values.reserveCapacity(count)
        for _ in 0..<count {
            values.append(fiber.operandStack.pop())
        }
        values.reverse()

        var deallocators: [() -> Void] = []
        deallocators.reserveCapacity(count)

        do {
            for index in 0..<values.count {
                try packFFIArrayValue(
                    values[index],
                    layout: elementLayout,
                    into: buffer.advanced(by: stride * index),
                    heap: heap,
                    deallocators: &deallocators
                )
            }
        } catch {
            for cleanup in deallocators.reversed() {
                cleanup()
            }
            buffer.deallocate()
            throw error
        }

        keepAliveFFIAllocation {
            for cleanup in deallocators.reversed() {
                cleanup()
            }
            buffer.deallocate()
        }
        fiber.operandStack.push(.nativePointer(buffer))
    }
}

private func readFFIArrayU8(fn: BytecodeFunction, frame: inout VMCallFrame) throws -> UInt8 {
    guard frame.ip < fn.code.count else {
        throw VMError.invalidBytecode("EOF")
    }
    let value = fn.code[frame.ip]
    frame.ip += 1
    return value
}

private func readFFIArrayU16(fn: BytecodeFunction, frame: inout VMCallFrame) throws -> UInt16 {
    let hi = UInt16(try readFFIArrayU8(fn: fn, frame: &frame))
    let lo = UInt16(try readFFIArrayU8(fn: fn, frame: &frame))
    return (hi << 8) | lo
}

private func readFFIArrayTypeDesc(fn: BytecodeFunction, frame: inout VMCallFrame) throws -> VMFFIArrayTypeDesc {
    let tag = try readFFIArrayU8(fn: fn, frame: &frame)
    if tag == 13 {
        let fieldCount = Int(try readFFIArrayU8(fn: fn, frame: &frame))
        var fields: [VMFFIArrayTypeDesc] = []
        fields.reserveCapacity(fieldCount)
        for _ in 0..<fieldCount {
            fields.append(try readFFIArrayTypeDesc(fn: fn, frame: &frame))
        }
        return .cstruct(fields)
    }
    if tag == 14 {
        return .pointer(try readFFIArrayTypeDesc(fn: fn, frame: &frame))
    }
    return .scalar(tag)
}

private func ffiArrayAlignUp(_ value: Int, to alignment: Int) -> Int {
    guard alignment > 1 else {
        return value
    }
    let mask = alignment - 1
    return (value + mask) & ~mask
}

private func ffiArrayScalarSizeAlign(tag: UInt8) -> (size: Int, alignment: Int) {
    switch tag {
    case 1, 5:
        return (1, 1)
    case 2, 6:
        return (2, 2)
    case 3, 7, 9:
        return (4, 4)
    case 4, 8, 10:
        return (8, 8)
    case 11, 12:
        return (
            MemoryLayout<UnsafeMutableRawPointer?>.size,
            MemoryLayout<UnsafeMutableRawPointer?>.alignment
        )
    default:
        return (8, 8)
    }
}

private func ffiArrayLayout(for desc: VMFFIArrayTypeDesc) -> VMFFIArrayLayout {
    switch desc {
    case .scalar(let tag):
        let scalar = ffiArrayScalarSizeAlign(tag: tag)
        return .scalar(tag: tag, size: scalar.size, alignment: scalar.alignment)
    case .cstruct(let fields):
        let fieldLayouts = fields.map(ffiArrayLayout(for:))
        var offsets = Array(repeating: 0, count: fieldLayouts.count)
        var offset = 0
        var maxAlignment = 1
        for index in 0..<fieldLayouts.count {
            let fieldAlignment = fieldLayouts[index].alignment
            maxAlignment = max(maxAlignment, fieldAlignment)
            offset = ffiArrayAlignUp(offset, to: fieldAlignment)
            offsets[index] = offset
            offset += fieldLayouts[index].size
        }
        let totalSize = ffiArrayAlignUp(offset, to: maxAlignment)
        return .cstruct(fields: fieldLayouts, offsets: offsets, size: totalSize, alignment: maxAlignment)
    case .pointer:
        let scalar = ffiArrayScalarSizeAlign(tag: 11)
        return .scalar(tag: 11, size: scalar.size, alignment: scalar.alignment)
    }
}

private func packFFIArrayValue(
    _ value: KiraValue,
    layout: VMFFIArrayLayout,
    into destination: UnsafeMutableRawPointer,
    heap: VMHeap,
    deallocators: inout [() -> Void]
) throws {
    switch layout {
    case .scalar(let tag, _, _):
        if case .nil_ = value {
            switch tag {
            case 1:
                destination.storeBytes(of: Int8(0), as: Int8.self)
                return
            case 2:
                destination.storeBytes(of: Int16(0), as: Int16.self)
                return
            case 3:
                destination.storeBytes(of: Int32(0), as: Int32.self)
                return
            case 4:
                destination.storeBytes(of: Int64(0), as: Int64.self)
                return
            case 5:
                destination.storeBytes(of: UInt8(0), as: UInt8.self)
                return
            case 6:
                destination.storeBytes(of: UInt16(0), as: UInt16.self)
                return
            case 7:
                destination.storeBytes(of: UInt32(0), as: UInt32.self)
                return
            case 8:
                destination.storeBytes(of: UInt64(0), as: UInt64.self)
                return
            case 9:
                destination.storeBytes(of: Float(0), as: Float.self)
                return
            case 10:
                destination.storeBytes(of: Double(0), as: Double.self)
                return
            case 11:
                let pointer: UnsafeMutableRawPointer? = nil
                destination.storeBytes(of: pointer, as: UnsafeMutableRawPointer?.self)
                return
            case 12:
                let pointer: UnsafeMutablePointer<CChar>? = nil
                destination.storeBytes(of: pointer, as: UnsafeMutablePointer<CChar>?.self)
                return
            default:
                break
            }
        }

        switch tag {
        case 1:
            destination.storeBytes(of: Int8(truncatingIfNeeded: try value.asInt()), as: Int8.self)
        case 2:
            destination.storeBytes(of: Int16(truncatingIfNeeded: try value.asInt()), as: Int16.self)
        case 3:
            destination.storeBytes(of: Int32(truncatingIfNeeded: try value.asInt()), as: Int32.self)
        case 4:
            destination.storeBytes(of: Int64(try value.asInt()), as: Int64.self)
        case 5:
            destination.storeBytes(of: UInt8(truncatingIfNeeded: try value.asInt()), as: UInt8.self)
        case 6:
            destination.storeBytes(of: UInt16(truncatingIfNeeded: try value.asInt()), as: UInt16.self)
        case 7:
            destination.storeBytes(of: UInt32(truncatingIfNeeded: try value.asInt()), as: UInt32.self)
        case 8:
            destination.storeBytes(of: UInt64(bitPattern: try value.asInt()), as: UInt64.self)
        case 9:
            destination.storeBytes(of: try value.asFloat32(), as: Float.self)
        case 10:
            destination.storeBytes(of: try value.asFloat64(), as: Double.self)
        case 12:
            switch value {
            case .reference(let ref):
                let object = try heap.get(ref)
                guard let string = object as? KiraString else {
                    throw VMError.typeError(expected: "String", got: value)
                }
                let cString = strdup(string.value)
                let pointer: UnsafeMutablePointer<CChar>? = cString
                destination.storeBytes(of: pointer, as: UnsafeMutablePointer<CChar>?.self)
                deallocators.append {
                    if let cString {
                        free(cString)
                    }
                }
            case .nil_:
                let pointer: UnsafeMutablePointer<CChar>? = nil
                destination.storeBytes(of: pointer, as: UnsafeMutablePointer<CChar>?.self)
            case .nativePointer(let nativePointer):
                let pointer: UnsafeMutablePointer<CChar>? = nativePointer.assumingMemoryBound(to: CChar.self)
                destination.storeBytes(of: pointer, as: UnsafeMutablePointer<CChar>?.self)
            default:
                throw VMError.typeError(expected: "String|nil", got: value)
            }
        default:
            let pointer: UnsafeMutableRawPointer?
            switch value {
            case .nativePointer(let nativePointer):
                pointer = nativePointer
            case .nil_:
                pointer = nil
            default:
                throw VMError.typeError(expected: "Pointer|nil", got: value)
            }
            destination.storeBytes(of: pointer, as: UnsafeMutableRawPointer?.self)
        }
    case .cstruct(let fields, let offsets, let size, _):
        if case .nil_ = value {
            memset(destination, 0, max(1, size))
            return
        }
        guard case .reference(let ref) = value else {
            throw VMError.typeError(expected: "CStruct", got: value)
        }
        let object = try heap.get(ref)
        guard object.fields.count >= fields.count else {
            throw VMError.invalidBytecode(
                "cstruct field count mismatch (got=\(object.fields.count), expected=\(fields.count))"
            )
        }
        for index in 0..<fields.count {
            try packFFIArrayValue(
                object.fields[index],
                layout: fields[index],
                into: destination.advanced(by: offsets[index]),
                heap: heap,
                deallocators: &deallocators
            )
        }
    }
}
