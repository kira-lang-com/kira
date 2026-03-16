import Foundation

public struct IncrementalEngine: Sendable {
    public struct CacheEntry: Codable, Sendable {
        public var functionName: String
        public var astHash: String
        public var outputPath: String
    }

    public var cacheDirectory: URL

    public init(cacheDirectory: URL = URL(fileURLWithPath: ".kira-cache", isDirectory: true)) {
        self.cacheDirectory = cacheDirectory
    }

    public func hashFunctionSource(_ fn: FunctionDecl) -> String {
        // Stable-ish representation for scaffolding; avoids platform crypto deps.
        var s = fn.name
        for p in fn.parameters { s += "|\(p.name):\(p.type.kind)" }
        s += "|ret:\(String(describing: fn.returnType?.kind))"
        s += "|ann:\(fn.annotations.map(\.name).joined(separator: ","))"
        s += "|body:\(fn.body.statements.count)"
        return fnv1a64(s)
    }

    public func loadCache() -> [String: CacheEntry] {
        let url = cacheDirectory.appendingPathComponent("cache.json")
        guard let data = try? Data(contentsOf: url) else { return [:] }
        guard let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) else { return [:] }
        return decoded
    }

    public func saveCache(_ cache: [String: CacheEntry]) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let url = cacheDirectory.appendingPathComponent("cache.json")
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func fnv1a64(_ s: String) -> String {
        let prime: UInt64 = 1099511628211
        var hash: UInt64 = 14695981039346656037
        for b in s.utf8 {
            hash ^= UInt64(b)
            hash &*= prime
        }
        return String(hash, radix: 16)
    }
}

