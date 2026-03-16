import Foundation

public struct PatchableSymbolTable: @unchecked Sendable {
    private var symbols: [String: UnsafeMutableRawPointer] = [:]

    public init() {}

    public mutating func register(name: String, address: UnsafeMutableRawPointer) {
        symbols[name] = address
    }

    public func address(of name: String) -> UnsafeMutableRawPointer? {
        symbols[name]
    }
}
