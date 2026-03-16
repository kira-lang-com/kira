import Foundation

public enum LLVMAvailabilityError: Error, CustomStringConvertible, Sendable {
    case unavailable

    public var description: String {
        "error: LLVM codegen is not available in this build. Install llvm-c and rebuild Kira with the system LLVM headers available."
    }
}

public final class LLVMCodegen: @unchecked Sendable {
    public init() {}

    public func emitObjectFile(from ir: KiraIRModule, to url: URL, target: PlatformTarget) throws {
        _ = ir
        _ = target
        // This scaffold keeps the llvm-c integration optional. When available, this method can be
        // expanded to lower KiraIR into LLVM IR and emit an object file via LLVMTargetMachineEmitToFile.
        throw LLVMAvailabilityError.unavailable
    }
}

