import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum BinaryPatchError: Error, CustomStringConvertible, Sendable {
    case unsupported
    case protectFailed
    case invalidAddress

    public var description: String {
        switch self {
        case .unsupported: return "error: binary patching is not supported on this platform/build"
        case .protectFailed: return "error: failed to change page protection"
        case .invalidAddress: return "error: invalid patch address"
        }
    }
}

public struct BinaryPatcher: Sendable {
    public init() {}

    public func patch(at entry: UnsafeMutableRawPointer, to target: UnsafeRawPointer) throws {
        #if os(iOS) || os(Android) || os(WASI) || os(Windows)
        throw BinaryPatchError.unsupported
        #else
        let pageSize = Int(getpagesize())
        let addr = Int(bitPattern: entry)
        guard addr != 0 else { throw BinaryPatchError.invalidAddress }
        let pageStart = addr & ~(pageSize - 1)
        if mprotect(UnsafeMutableRawPointer(bitPattern: pageStart), pageSize, PROT_READ | PROT_WRITE | PROT_EXEC) != 0 {
            throw BinaryPatchError.protectFailed
        }
        defer { _ = mprotect(UnsafeMutableRawPointer(bitPattern: pageStart), pageSize, PROT_READ | PROT_EXEC) }

        #if arch(x86_64)
        // 14-byte RIP-relative indirect jmp trampoline.
        // FF 25 00 00 00 00 ; JMP QWORD PTR [RIP+0]
        // <8-byte absolute address>
        var bytes: [UInt8] = [0xFF, 0x25, 0x00, 0x00, 0x00, 0x00]
        var addr64 = UInt64(bitPattern: Int64(Int(bitPattern: target))).littleEndian
        withUnsafeBytes(of: &addr64) { bytes.append(contentsOf: $0) }
        memcpy(entry, bytes, bytes.count)
        #elseif arch(arm64)
        // 12-byte trampoline:
        // LDR X16, #8 ; BR X16 ; <8-byte absolute address>
        var bytes: [UInt8] = []
        var ldr: UInt32 = 0x58000050
        var br: UInt32 = 0xD61F0200
        var ldrLE = ldr.littleEndian
        var brLE = br.littleEndian
        withUnsafeBytes(of: &ldrLE) { bytes.append(contentsOf: $0) }
        withUnsafeBytes(of: &brLE) { bytes.append(contentsOf: $0) }
        var addr64 = UInt64(bitPattern: Int64(Int(bitPattern: target))).littleEndian
        withUnsafeBytes(of: &addr64) { bytes.append(contentsOf: $0) }
        memcpy(entry, bytes, bytes.count)
        #if canImport(Darwin)
        sys_icache_invalidate(entry, bytes.count)
        #endif
        #else
        throw BinaryPatchError.unsupported
        #endif
        #endif
    }
}
