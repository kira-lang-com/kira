import Foundation

public final class HotReloadManager: @unchecked Sendable {
    public struct Config: Sendable {
        public var enabled: Bool
        public init(enabled: Bool) { self.enabled = enabled }
    }

    private let config: Config
    private let compiler: CompilerDriver
    private let watcher = FileWatcher()

    public init(config: Config, compiler: CompilerDriver = CompilerDriver()) {
        self.config = config
        self.compiler = compiler
    }

    public func startWatching(sources: [URL], target: PlatformTarget, onRebuild: @escaping @Sendable (Result<CompilerOutput, Error>) -> Void) -> AnyObject? {
        guard config.enabled else { return nil }
        return watcher.watch(urls: sources) { [compiler] event in
            do {
                let text = try String(contentsOf: event.url, encoding: .utf8)
                let output = try compiler.compile(source: SourceText(file: event.url.path, text: text), target: target)
                onRebuild(.success(output))
            } catch {
                onRebuild(.failure(error))
            }
        }
    }
}

