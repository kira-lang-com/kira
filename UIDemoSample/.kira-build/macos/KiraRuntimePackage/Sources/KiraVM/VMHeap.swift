import Foundation

public enum GCColor: Sendable { case white, gray, black }

public struct KiraTypeDescriptor: Hashable, Sendable {
    public var name: String
    public var fieldCount: Int
    public init(name: String, fieldCount: Int) {
        self.name = name
        self.fieldCount = fieldCount
    }
}

public class KiraObject: @unchecked Sendable {
    public var gcColor: GCColor = .white
    public var type: KiraTypeDescriptor
    public var fields: [KiraValue]

    public init(type: KiraTypeDescriptor, fields: [KiraValue]) {
        self.type = type
        self.fields = fields
    }
}

public final class KiraArray: KiraObject, @unchecked Sendable {
    public var elements: [KiraValue] {
        get { fields }
        set { fields = newValue }
    }
    public init(elements: [KiraValue]) {
        super.init(type: KiraTypeDescriptor(name: "Array", fieldCount: 0), fields: elements)
    }
}

public final class KiraString: KiraObject, @unchecked Sendable {
    public var value: String
    public var hashValueCache: UInt64

    public init(_ value: String) {
        self.value = value
        self.hashValueCache = KiraString.computeHash(value)
        super.init(type: KiraTypeDescriptor(name: "String", fieldCount: 0), fields: [])
    }

    private static func computeHash(_ s: String) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        for b in s.utf8 {
            hash ^= UInt64(b)
            hash &*= 1099511628211
        }
        return hash
    }
}

public final class KiraClosure: KiraObject, @unchecked Sendable {
    public let functionIndex: Int
    public var captures: [KiraValue]

    public init(functionIndex: Int, captures: [KiraValue]) {
        self.functionIndex = functionIndex
        self.captures = captures
        super.init(type: KiraTypeDescriptor(name: "Closure", fieldCount: 0), fields: [])
    }
}

public final class KiraFiberObject: KiraObject, @unchecked Sendable {
    public let fiber: VMFiber
    public init(fiber: VMFiber) {
        self.fiber = fiber
        super.init(type: KiraTypeDescriptor(name: "Fiber", fieldCount: 0), fields: [])
    }
}

public final class VMHeap: @unchecked Sendable {
    private var nextId: Int = 1
    private var objects: [Int: KiraObject] = [:]
    public let gc = VMGarbageCollector()

    public init() {}

    public func allocate(_ obj: KiraObject) -> ObjectRef {
        let id = nextId
        nextId += 1
        // If an incremental GC cycle is already in progress, ensure newly allocated objects
        // won't be swept in the current cycle before they're linked into the root graph.
        if gc.phase != .idle {
            obj.gcColor = .black
        }
        objects[id] = obj
        gc.allObjectIDs.append(id)
        return ObjectRef(id)
    }

    public func get(_ ref: ObjectRef) throws -> KiraObject {
        guard let o = objects[ref.id] else { throw VMError.invalidReference(ref) }
        return o
    }

    public func remove(_ ref: ObjectRef) {
        objects.removeValue(forKey: ref.id)
    }
}
