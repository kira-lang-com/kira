import Foundation

public protocol PlatformBackend: Sendable {
    var name: String { get }
    func initialize()
    func shutdown()
}

public struct NullBackend: PlatformBackend {
    public let name: String = "NullBackend"
    public init() {}
    public func initialize() {}
    public func shutdown() {}
}

