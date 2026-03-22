import XCTest
@testable import KiraCompiler

final class FileWatcherTests: XCTestCase {
    private final class EventRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [FileWatcher.Event] = []

        func append(_ event: FileWatcher.Event) {
            lock.lock()
            defer { lock.unlock() }
            storage.append(event)
        }

        func snapshot() -> [FileWatcher.Event] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    func testWatcherReportsModifiedAddedAndRemovedFilesInDirectory() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourcesDir = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let mainFile = sourcesDir.appendingPathComponent("main.kira")
        try "function main() -> Int { return 1 }\n".write(to: mainFile, atomically: true, encoding: .utf8)

        let expectation = expectation(description: "watcher events")
        expectation.expectedFulfillmentCount = 3

        let watcher = FileWatcher(pollInterval: 0.05)
        let recorder = EventRecorder()
        let handle = watcher.watch(urls: [sourcesDir]) { event in
            recorder.append(event)
            expectation.fulfill()
        }

        withExtendedLifetime(handle) {
            usleep(120_000)

            try? "function main() -> Int { return 2 }\n".write(to: mainFile, atomically: true, encoding: .utf8)

            let secondaryFile = sourcesDir.appendingPathComponent("secondary.kira")
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(150)) {
                try? "function helper() -> Int { return 3 }\n".write(to: secondaryFile, atomically: true, encoding: .utf8)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(300)) {
                try? FileManager.default.removeItem(at: secondaryFile)
            }

            wait(for: [expectation], timeout: 3.0)
        }

        let recordedEvents = recorder.snapshot()

        XCTAssertTrue(recordedEvents.contains { $0.url.lastPathComponent == "main.kira" && $0.kind == .modified })
        XCTAssertTrue(recordedEvents.contains { $0.url.lastPathComponent == "secondary.kira" && $0.kind == .added })
        XCTAssertTrue(recordedEvents.contains { $0.url.lastPathComponent == "secondary.kira" && $0.kind == .removed })
    }
}
