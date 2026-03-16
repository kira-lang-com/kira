import Foundation

public enum KiraStdlib {
    public static func resourceURL(_ relativePath: String) -> URL? {
        Bundle.module.url(forResource: relativePath, withExtension: nil)
    }

    public static var rootURL: URL {
        Bundle.module.resourceURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    public static func listKiraFiles() -> [URL] {
        let fm = FileManager.default
        guard let base = Bundle.module.resourceURL else { return [] }
        let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey])!
        var result: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "kira" { result.append(url) }
        }
        return result.sorted { $0.path < $1.path }
    }
}

