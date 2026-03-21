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

    public var isApple: Bool {
        switch self {
        case .iOS, .macOS:
            return true
        default:
            return false
        }
    }

    public var architectureName: String {
        switch self {
        case .iOS(let arch), .android(let arch), .macOS(let arch), .linux(let arch), .windows(let arch):
            switch arch {
            case .arm64:
                return "arm64"
            case .x86_64:
                return "x86_64"
            }
        case .wasm32:
            return "wasm32"
        }
    }

    public var platformName: String {
        switch self {
        case .iOS:
            return "ios"
        case .android:
            return "android"
        case .macOS:
            return "macos"
        case .linux:
            return "linux"
        case .windows:
            return "windows"
        case .wasm32:
            return "wasm32"
        }
    }

    public var sdkName: String? {
        switch self {
        case .iOS:
            return "iphoneos"
        case .macOS:
            return "macosx"
        default:
            return nil
        }
    }

    public func triple(minimumVersion: String? = nil) -> String {
        switch self {
        case .iOS(let arch):
            let version = minimumVersion ?? "17.0"
            return "\(archName(arch))-apple-ios\(version)"
        case .android(let arch):
            return "\(archName(arch))-linux-android"
        case .macOS(let arch):
            let version = minimumVersion ?? "14.0"
            return "\(archName(arch))-apple-macosx\(version)"
        case .linux(let arch):
            return "\(archName(arch))-unknown-linux-gnu"
        case .windows(let arch):
            return "\(archName(arch))-pc-windows-msvc"
        case .wasm32:
            return "wasm32-unknown-unknown"
        }
    }

    private func archName(_ arch: Arch) -> String {
        switch arch {
        case .arm64:
            return "arm64"
        case .x86_64:
            return "x86_64"
        }
    }
}
