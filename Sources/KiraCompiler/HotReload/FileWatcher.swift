import Dispatch
import Foundation

public struct FileWatcher: Sendable {
    public enum EventKind: String, Sendable {
        case added
        case modified
        case removed
    }

    public struct Event: Sendable {
        public var url: URL
        public var kind: EventKind
        public var timestamp: Date

        public init(url: URL, kind: EventKind, timestamp: Date) {
            self.url = url
            self.kind = kind
            self.timestamp = timestamp
        }
    }

    private let pollInterval: TimeInterval
    private let watchedExtension: String

    public init(pollInterval: TimeInterval = 0.25, watchedExtension: String = "kira") {
        self.pollInterval = pollInterval
        self.watchedExtension = watchedExtension
    }

    public func watch(urls: [URL], onEvent: @escaping @Sendable (Event) -> Void) -> AnyObject {
        let state = PollState(
            urls: urls,
            interval: pollInterval,
            watchedExtension: watchedExtension,
            onEvent: onEvent
        )
        state.start()
        return state
    }
}

private struct WatchedEntry: Sendable {
    var path: String
    var url: URL
    var timestamp: Date
}

private final class PollState: @unchecked Sendable {
    let urls: [URL]
    let interval: TimeInterval
    let watchedExtension: String
    let onEvent: @Sendable (FileWatcher.Event) -> Void
    var timer: DispatchSourceTimer?
    var last: [String: WatchedEntry] = [:]

    init(
        urls: [URL],
        interval: TimeInterval,
        watchedExtension: String,
        onEvent: @escaping @Sendable (FileWatcher.Event) -> Void
    ) {
        self.urls = urls
        self.interval = interval
        self.watchedExtension = watchedExtension
        self.onEvent = onEvent
    }

    func start() {
        last = snapshotEntries()
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        timer.resume()
        self.timer = timer
    }

    private func poll() {
        let current = snapshotEntries()

        for (path, entry) in current {
            if let previous = last[path] {
                if entry.timestamp > previous.timestamp {
                    onEvent(.init(url: entry.url, kind: .modified, timestamp: entry.timestamp))
                }
            } else {
                onEvent(.init(url: entry.url, kind: .added, timestamp: entry.timestamp))
            }
        }

        for (path, entry) in last where current[path] == nil {
            onEvent(.init(url: entry.url, kind: .removed, timestamp: Date()))
        }

        last = current
    }

    private func snapshotEntries() -> [String: WatchedEntry] {
        var entries: [String: WatchedEntry] = [:]
        for root in urls {
            for entry in expandEntries(from: root) {
                entries[entry.path] = entry
            }
        }
        return entries
    }

    private func expandEntries(from url: URL) -> [WatchedEntry] {
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
            return []
        }

        if isDirectory.boolValue {
            return collectEntries(in: standardized)
        }

        guard standardized.pathExtension == watchedExtension else {
            return []
        }
        guard let timestamp = modificationDate(for: standardized) else {
            return []
        }
        return [
            WatchedEntry(
                path: standardized.path,
                url: standardized,
                timestamp: timestamp
            )
        ]
    }

    private func collectEntries(in directory: URL) -> [WatchedEntry] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey]
        ) else {
            return []
        }

        var entries: [WatchedEntry] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == watchedExtension else { continue }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true else {
                continue
            }
            entries.append(.init(
                path: url.standardizedFileURL.path,
                url: url.standardizedFileURL,
                timestamp: values.contentModificationDate ?? .distantPast
            ))
        }
        return entries
    }

    private func modificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    deinit {
        timer?.cancel()
    }
}
