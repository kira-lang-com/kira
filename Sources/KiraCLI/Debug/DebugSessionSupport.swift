import Foundation
import KiraCompiler

enum DebugSessionSupport {
    struct StartedSession {
        let server: PatchServer
        let runtimeSession: PatchServer.RuntimeSession
    }

    static func start(
        projectRoot: URL,
        appName: String,
        targetAppIdentifier: String,
        target: PlatformTarget,
        localhostOnly: Bool = false,
        port: UInt16? = nil,
        statusHandler: @escaping PatchServer.StatusHandler = { message in
            print("[debug] \(message.kind.rawValue) generation \(message.generation): \(message.detail)")
        }
    ) throws -> StartedSession {
        let workspace = try PatchWorkspace(projectRoot: projectRoot, target: target)
        try workspace.syncInitialSources()

        let sessionID = UUID().uuidString.lowercased()
        let sessionToken = makeSessionToken()
        let compiler = PatchCompiler(config: .init(
            sessionID: sessionID,
            sessionToken: sessionToken,
            projectName: appName,
            targetAppIdentifier: targetAppIdentifier,
            target: target
        ))

        let server = PatchServer(
            config: .init(
                appName: appName,
                projectName: appName,
                runtimeVersion: KiraCLIInfo.version,
                localhostOnly: localhostOnly,
                advertiseOnLocalNetwork: !localhostOnly,
                port: port
            ),
            compiler: compiler,
            watchedFiles: workspace.watchURLs,
            prepareForBuild: { events in
                try workspace.apply(events: events)
            },
            sourceFileProvider: {
                try collectSourceFiles(at: workspace.compileRoot)
            },
            sourceProvider: {
                try loadPrimarySourceTexts(at: workspace.compileRoot)
            },
            statusHandler: statusHandler
        )
        let runtimeSession = try server.start()
        return StartedSession(server: server, runtimeSession: runtimeSession)
    }

    static func loadPrimarySourceTexts(at projectRoot: URL) throws -> [SourceText] {
        try collectPrimarySourceFiles(at: projectRoot).map { url in
            SourceText(file: url.path, text: try String(contentsOf: url, encoding: .utf8))
        }
    }

    static func loadSourceTexts(at projectRoot: URL) throws -> [SourceText] {
        try collectSourceFiles(at: projectRoot).map { url in
            SourceText(file: url.path, text: try String(contentsOf: url, encoding: .utf8))
        }
    }

    static func collectPrimarySourceFiles(at projectRoot: URL) throws -> [URL] {
        let projectSources = projectRoot.appendingPathComponent("Sources", isDirectory: true)
        guard FileManager.default.fileExists(atPath: projectSources.path) else {
            return []
        }
        return try collectKiraFiles(in: projectSources)
    }

    static func collectSourceFiles(at projectRoot: URL) throws -> [URL] {
        var files: [URL] = []
        let fm = FileManager.default

        let projectSources = projectRoot.appendingPathComponent("Sources", isDirectory: true)
        if fm.fileExists(atPath: projectSources.path) {
            files.append(contentsOf: try collectKiraFiles(in: projectSources))
        }

        let packagesRoot = projectRoot.appendingPathComponent("KiraPackages", isDirectory: true)
        if let packageDirs = try? fm.contentsOfDirectory(at: packagesRoot, includingPropertiesForKeys: nil) {
            for packageDir in packageDirs {
                let sourcesDir = packageDir.appendingPathComponent("Sources", isDirectory: true)
                if fm.fileExists(atPath: sourcesDir.path) {
                    files.append(contentsOf: try collectKiraFiles(in: sourcesDir))
                }
            }
        }

        return uniqueSorted(files)
    }

    static func collectWatchURLs(at projectRoot: URL) throws -> [URL] {
        let fm = FileManager.default
        var urls: [URL] = try collectSourceFiles(at: projectRoot)

        let projectSources = projectRoot.appendingPathComponent("Sources", isDirectory: true)
        if fm.fileExists(atPath: projectSources.path) {
            urls.append(projectSources)
        }

        let packagesRoot = projectRoot.appendingPathComponent("KiraPackages", isDirectory: true)
        if let packageDirs = try? fm.contentsOfDirectory(at: packagesRoot, includingPropertiesForKeys: nil) {
            for packageDir in packageDirs {
                let sourcesDir = packageDir.appendingPathComponent("Sources", isDirectory: true)
                if fm.fileExists(atPath: sourcesDir.path) {
                    urls.append(sourcesDir)
                }
            }
        }

        return uniqueSorted(urls)
    }

    private static func collectKiraFiles(in dir: URL) throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        var urls: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "kira" {
            urls.append(url)
        }
        return uniqueSorted(urls)
    }

    private static func uniqueSorted(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        return urls
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
            .sorted { $0.path < $1.path }
    }

    private static func makeSessionToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
}

private final class PatchWorkspace: @unchecked Sendable {
    let compileRoot: URL
    let watchURLs: [URL]

    private let projectRoot: URL
    private let liveProjectSourcesRoot: URL
    private let livePackagesRoot: URL?
    private let stagedProjectSourcesRoot: URL?
    private let stagedPackagesRoot: URL?
    private let preservedPatchedPackagePaths: Set<String>
    private let fileManager = FileManager.default

    init(projectRoot: URL, target: PlatformTarget) throws {
        self.projectRoot = projectRoot.standardizedFileURL
        self.liveProjectSourcesRoot = self.projectRoot.appendingPathComponent("Sources", isDirectory: true)

        let kiraRoot = Self.kiraRepositoryRoot()
        let candidatePackagesRoot = kiraRoot.appendingPathComponent("KiraPackages", isDirectory: true)
        if fileManager.fileExists(atPath: candidatePackagesRoot.path) {
            self.livePackagesRoot = candidatePackagesRoot
        } else {
            self.livePackagesRoot = nil
        }

        if target.isApple {
            let stagingRoot = self.projectRoot
                .appendingPathComponent(".kira-build", isDirectory: true)
                .appendingPathComponent(target.platformName, isDirectory: true)
                .appendingPathComponent("Staging", isDirectory: true)
                .standardizedFileURL
            if fileManager.fileExists(atPath: stagingRoot.path) {
                self.compileRoot = stagingRoot
                self.stagedProjectSourcesRoot = stagingRoot.appendingPathComponent("Sources", isDirectory: true)
                self.stagedPackagesRoot = stagingRoot.appendingPathComponent("KiraPackages", isDirectory: true)
                self.preservedPatchedPackagePaths = [
                    "Kira.Graphics/Sources/Platform/sokol.kira",
                    "Kira.Graphics/Sources/Frame/Application.kira",
                    "Kira.Graphics/Sources/Core/CommandBuffer.kira",
                    "Kira.Graphics/Sources/Core/RenderEncoder.kira",
                ]
            } else {
                self.compileRoot = self.projectRoot
                self.stagedProjectSourcesRoot = nil
                self.stagedPackagesRoot = nil
                self.preservedPatchedPackagePaths = []
            }
        } else {
            self.compileRoot = self.projectRoot
            self.stagedProjectSourcesRoot = nil
            self.stagedPackagesRoot = nil
            self.preservedPatchedPackagePaths = []
        }

        var watchURLs: [URL] = []
        if fileManager.fileExists(atPath: liveProjectSourcesRoot.path) {
            watchURLs.append(liveProjectSourcesRoot)
        }
        if let livePackagesRoot, fileManager.fileExists(atPath: livePackagesRoot.path) {
            watchURLs.append(livePackagesRoot)
        }
        self.watchURLs = Self.uniqueSorted(watchURLs)
    }

    func syncInitialSources() throws {
        guard compileRoot != projectRoot else {
            return
        }
        if fileManager.fileExists(atPath: liveProjectSourcesRoot.path) {
            try syncDirectory(from: liveProjectSourcesRoot, to: stagedProjectSourcesRoot)
        }
    }

    func apply(events: [FileWatcher.Event]) throws {
        guard compileRoot != projectRoot else {
            return
        }
        if events.isEmpty {
            try syncInitialSources()
            return
        }

        for event in events.sorted(by: { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.url.path < rhs.url.path
            }
            return lhs.timestamp < rhs.timestamp
        }) {
            if let livePackagesRoot,
               event.url.standardizedFileURL.path.hasPrefix(livePackagesRoot.path + "/") {
                let relativePath = String(event.url.standardizedFileURL.path.dropFirst(livePackagesRoot.path.count + 1))
                if preservedPatchedPackagePaths.contains(relativePath) {
                    continue
                }
                try apply(event: event, to: stagedPackagesRoot?.appendingPathComponent(relativePath))
                continue
            }

            if event.url.standardizedFileURL.path.hasPrefix(liveProjectSourcesRoot.path + "/") {
                let relativePath = String(event.url.standardizedFileURL.path.dropFirst(liveProjectSourcesRoot.path.count + 1))
                try apply(event: event, to: stagedProjectSourcesRoot?.appendingPathComponent(relativePath))
            }
        }
    }

    private func apply(event: FileWatcher.Event, to destinationURL: URL?) throws {
        guard let destinationURL else {
            return
        }
        switch event.kind {
        case .added, .modified:
            let parent = destinationURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true, attributes: nil)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: event.url, to: destinationURL)
        case .removed:
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
        }
    }

    private func syncDirectory(from sourceRoot: URL, to destinationRoot: URL?) throws {
        guard let destinationRoot else {
            return
        }
        let sourceFiles = try Self.collectKiraFiles(in: sourceRoot)
        let sourceMap = Dictionary(uniqueKeysWithValues: sourceFiles.map { sourceURL in
            let relativePath = String(sourceURL.standardizedFileURL.path.dropFirst(sourceRoot.standardizedFileURL.path.count + 1))
            return (relativePath, sourceURL)
        })

        let existingFiles = fileManager.fileExists(atPath: destinationRoot.path)
            ? try Self.collectKiraFiles(in: destinationRoot)
            : []
        let existingRelativePaths = Set(existingFiles.map { url in
            String(url.standardizedFileURL.path.dropFirst(destinationRoot.standardizedFileURL.path.count + 1))
        })

        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true, attributes: nil)

        for relativePath in existingRelativePaths.subtracting(sourceMap.keys) {
            try fileManager.removeItem(at: destinationRoot.appendingPathComponent(relativePath))
        }

        for (relativePath, sourceURL) in sourceMap {
            let destinationURL = destinationRoot.appendingPathComponent(relativePath)
            let parent = destinationURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true, attributes: nil)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func kiraRepositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func collectKiraFiles(in dir: URL) throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        var urls: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "kira" {
            urls.append(url.standardizedFileURL)
        }
        return urls.sorted { $0.path < $1.path }
    }

    private static func uniqueSorted(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        return urls
            .map(\.standardizedFileURL)
            .filter { seen.insert($0.path).inserted }
            .sorted { $0.path < $1.path }
    }
}
