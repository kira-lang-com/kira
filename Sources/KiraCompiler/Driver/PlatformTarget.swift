import Foundation

public enum PlatformTarget: Hashable, Sendable {
    public enum Arch: Hashable, Sendable {
        case arm64
        case x86_64
    }

    case iOS(arch: Arch)
    case android(arch: Arch)
    case macOS(arch: Arch)
    case linux(arch: Arch)
    case windows(arch: Arch)
    case wasm32

    public var isWasm: Bool {
        if case .wasm32 = self { return true }
        return false
    }
}

