import Foundation

public struct BuildConfig: Codable, Sendable {
    public enum Optimization: String, Codable, Sendable { case debug, release }
    public enum ExecutionMode: String, Codable, Sendable { case hybrid, native, runtime }

    public var optimization: Optimization
    public var hotReload: Bool
    public var incrementalBuild: Bool
    public var executionMode: ExecutionMode

    public init(
        optimization: Optimization = .debug,
        hotReload: Bool = true,
        incrementalBuild: Bool = true,
        executionMode: ExecutionMode = .hybrid
    ) {
        self.optimization = optimization
        self.hotReload = hotReload
        self.incrementalBuild = incrementalBuild
        self.executionMode = executionMode
    }
}

