import XCTest
import KiraVM

final class VMGarbageCollectorTests: XCTestCase {
    func testSweepCompactsCollectedObjectIDs() throws {
        let heap = VMHeap()
        let root = heap.allocate(KiraArray(elements: []))

        for _ in 0..<600 {
            _ = heap.allocate(KiraArray(elements: []))
        }

        runCollection(heap: heap, roots: [root])

        XCTAssertEqual(heap.liveObjectCount, 1)
        XCTAssertEqual(heap.gc.allObjectIDs.count, 1)
    }

    func testRepeatedCollectionsDoNotAccumulateDeadObjectMetadata() throws {
        let heap = VMHeap()
        let root = heap.allocate(KiraArray(elements: []))

        for _ in 0..<8 {
            for _ in 0..<600 {
                _ = heap.allocate(KiraArray(elements: []))
            }

            runCollection(heap: heap, roots: [root])

            XCTAssertEqual(heap.liveObjectCount, 1)
            XCTAssertEqual(heap.gc.allObjectIDs.count, 1)
        }
    }

    private func runCollection(heap: VMHeap, roots: [ObjectRef], budget: Int = 10_000) {
        var steps = 0
        repeat {
            heap.gc.incrementalStep(roots: roots, heap: heap, budget: budget)
            steps += 1
        } while heap.gc.phase != .idle && steps < 32

        XCTAssertEqual(heap.gc.phase, .idle)
    }
}
