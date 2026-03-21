import Foundation

public final class VMFiber: @unchecked Sendable {
    public enum FiberState: Sendable {
        case running
        case suspended(yieldedValue: KiraValue)
        case dead
    }

    public var callStack: [VMCallFrame] = []
    public var operandStack = VMStack()
    public var state: FiberState = .running

    public init() {}

    public init(entryFunctionIndex: Int, localCount: Int) {
        let locals = Array(repeating: KiraValue.nil_, count: localCount)
        callStack.append(VMCallFrame(functionIndex: entryFunctionIndex, ip: 0, locals: locals, baseStackCount: 0, closure: nil))
    }

    public var currentFrame: VMCallFrame {
        get { callStack[callStack.count - 1] }
        set { callStack[callStack.count - 1] = newValue }
    }
}
