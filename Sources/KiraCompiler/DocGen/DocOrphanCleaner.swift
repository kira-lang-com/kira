import Foundation

public struct DocOrphanCleaner: Sendable {
    public init() {}

    public func clean(orphanableRoot: URL, expectedFiles: Set<String>) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: orphanableRoot, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for case let url as URL in enumerator {
            guard url.pathExtension == "md" else { continue }
            let rel = url.path.replacingOccurrences(of: orphanableRoot.path + "/", with: "")
            if !expectedFiles.contains(rel) {
                try fm.removeItem(at: url)
            }
        }
    }
}

