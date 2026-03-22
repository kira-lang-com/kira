import Foundation

public struct VMCallFrame: Sendable {
    public var functionIndex: Int
    public var ip: Int
    public var locals: [KiraValue]
    public var baseStackCount: Int
    public var closure: ObjectRef?

    public init(functionIndex: Int, ip: Int, locals: [KiraValue], baseStackCount: Int, closure: ObjectRef?) {
        self.functionIndex = functionIndex
        self.ip = ip
        self.locals = locals
        self.baseStackCount = baseStackCount
        self.closure = closure
    }
}

