import Foundation
import Dispatch
import KiraCompiler

enum WatchCommand {
    static func run(args: [String]) throws {
        _ = args
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let sourcesDir = cwd.appendingPathComponent("Sources", isDirectory: true)
        let files = try fm.contentsOfDirectory(at: sourcesDir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "kira" }
        let mgr = HotReloadManager(config: .init(enabled: true))
        _ = mgr.startWatching(sources: files, target: .macOS(arch: .arm64)) { result in
            switch result {
            case .success:
                print("Rebuilt at \(Date())")
            case .failure(let e):
                print(String(describing: e))
            }
        }
        dispatchMain()
    }
}
