import Foundation

public struct SourceLocationVM: Hashable, Sendable {
    public var file: String
    public var line: Int
    public init(file: String, line: Int) { self.file = file; self.line = line }
}

public final class VMDebugger: @unchecked Sendable {
    public enum StepMode: Sendable { case none, stepOver, stepInto, stepOut }
    public var breakpoints: [SourceLocationVM: Bool] = [:]
    public var stepMode: StepMode = .none

    public init() {}

    public func onLineReached(location: SourceLocationVM, fiber: VMFiber) {
        if breakpoints[location] == true || stepMode != .none {
            // Scaffold: pause by suspending with nil; a real DAP implementation would block on requests.
            fiber.state = .suspended(yieldedValue: .nil_)
        }
    }
}

