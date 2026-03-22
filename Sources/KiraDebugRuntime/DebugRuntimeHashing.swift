import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

public enum KiraDebugHashing {
    public static func sha256Hex(_ data: Data) -> String {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        return fnv1a64Hex(data)
        #endif
    }

    public static func sha256Hex(_ string: String) -> String {
        sha256Hex(Data(string.utf8))
    }

    public static func fnv1a64Hex(_ string: String) -> String {
        fnv1a64Hex(Data(string.utf8))
    }

    public static func fnv1a64Hex(_ data: Data) -> String {
        let prime: UInt64 = 1099511628211
        var hash: UInt64 = 14695981039346656037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= prime
        }
        return String(hash, radix: 16)
    }

    public static func stableHash(components: [String]) -> String {
        sha256Hex(components.joined(separator: "\u{1F}"))
    }

    public static func stableHash<S: Sequence>(_ components: S) -> String where S.Element == String {
        sha256Hex(Array(components).joined(separator: "\u{1F}"))
    }
}
