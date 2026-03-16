import Foundation

public struct ShaderMacro: Sendable {
    public enum Stage: String, Sendable { case vertex, fragment, compute, rayGeneration, closestHit, anyHit, miss, task, mesh }

    public init() {}

    /// Produces a deterministic embedded shader blob for the given function name and stage.
    /// This scaffold stores a small self-describing payload; real implementations would cross-compile to MSL/GLSL/HLSL/WGSL.
    public func compile(functionName: String, stage: Stage?) -> Data {
        var header = "kira.shader.v1\n"
        header += "name=\(functionName)\n"
        if let stage { header += "stage=\(stage.rawValue)\n" }
        return Data(header.utf8)
    }
}

