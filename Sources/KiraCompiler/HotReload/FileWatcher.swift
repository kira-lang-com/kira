import Foundation
import Dispatch

public struct FileWatcher: Sendable {
    public struct Event: Sendable {
        public var url: URL
        public var timestamp: Date
    }

    private let pollInterval: TimeInterval

    public init(pollInterval: TimeInterval = 0.25) {
        self.pollInterval = pollInterval
    }

    public func watch(urls: [URL], onEvent: @escaping @Sendable (Event) -> Void) -> AnyObject {
        let state = PollState(urls: urls, interval: pollInterval, onEvent: onEvent)
        state.start()
        return state
    }
}

private final class PollState: @unchecked Sendable {
    let urls: [URL]
    let interval: TimeInterval
    let onEvent: @Sendable (FileWatcher.Event) -> Void
    var timer: DispatchSourceTimer?
    var last: [URL: Date] = [:]

    init(urls: [URL], interval: TimeInterval, onEvent: @escaping @Sendable (FileWatcher.Event) -> Void) {
        self.urls = urls
        self.interval = interval
        self.onEvent = onEvent
    }

    func start() {
        for u in urls {
            last[u] = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        let t = DispatchSource.makeTimerSource(queue: .global())
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            for u in self.urls {
                let ts = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if let prev = self.last[u], ts > prev {
                    self.last[u] = ts
                    self.onEvent(.init(url: u, timestamp: ts))
                }
            }
        }
        t.resume()
        timer = t
    }

    deinit { timer?.cancel() }
}
