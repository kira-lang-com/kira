import Foundation

public enum KiraValue: Hashable, @unchecked Sendable {
    case int(Int64)
    case float(Float64)
    case bool(Bool)
    case reference(ObjectRef)
    case nativePointer(UnsafeMutableRawPointer)
    case nil_
}

public struct ObjectRef: Hashable, Sendable {
    public let id: Int
    public init(_ id: Int) { self.id = id }
}

public struct VMStack: Sendable {
    private var slots: [KiraValue] = []

    public init() {}

    public var count: Int { slots.count }

    public mutating func push(_ value: KiraValue) {
        slots.append(value)
    }

    @discardableResult
    public mutating func pop() -> KiraValue {
        slots.removeLast()
    }

    public func peek(_ offset: Int = 0) -> KiraValue {
        slots[slots.count - 1 - offset]
    }

    public mutating func popInt() throws -> Int64 {
        let v = pop()
        guard case .int(let i) = v else { throw VMError.typeError(expected: "Int", got: v) }
        return i
    }

    public mutating func popFloat() throws -> Double {
        let v = pop()
        guard case .float(let f) = v else { throw VMError.typeError(expected: "Float", got: v) }
        return f
    }

    public mutating func popBool() throws -> Bool {
        let v = pop()
        guard case .bool(let b) = v else { throw VMError.typeError(expected: "Bool", got: v) }
        return b
    }

    public mutating func popRef() throws -> ObjectRef {
        let v = pop()
        guard case .reference(let r) = v else { throw VMError.typeError(expected: "Reference", got: v) }
        return r
    }

    public mutating func truncate(to count: Int) {
        slots.removeLast(max(0, slots.count - count))
    }
}
