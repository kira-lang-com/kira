import Foundation

public final class VMGarbageCollector: @unchecked Sendable {
    public enum Phase: Sendable { case idle, marking, sweeping }

    public var phase: Phase = .idle
    public var grayStack: [ObjectRef] = []
    public var allObjectIDs: [Int] = []
    public var sweepCursor: Int = 0
    public var lastGCCount: Int = 0

    public init() {}

    public func shouldTrigger(currentCount: Int) -> Bool {
        currentCount > max(256, lastGCCount * 2)
    }

    public func startMarkPhase(roots: [ObjectRef], heap: VMHeap) {
        phase = .marking
        grayStack.removeAll(keepingCapacity: true)
        for r in roots { mark(ref: r, heap: heap) }
    }

    public func incrementalStep(roots: [ObjectRef], heap: VMHeap, budget: Int = 200) {
        switch phase {
        case .idle:
            if shouldTrigger(currentCount: heapCount(heap)) { startMarkPhase(roots: roots, heap: heap) }
        case .marking:
            var remaining = budget
            while remaining > 0, let ref = grayStack.popLast() {
                remaining -= 1
                scan(ref: ref, heap: heap)
            }
            if grayStack.isEmpty {
                phase = .sweeping
                sweepCursor = 0
            }
        case .sweeping:
            sweep(heap: heap, budget: max(1, budget / 2))
            if sweepCursor >= allObjectIDs.count {
                phase = .idle
                lastGCCount = heapCount(heap)
            }
        }
    }

    public func writeBarrier(owner: ObjectRef, newRef: ObjectRef, heap: VMHeap) {
        // Conservative: when marking, ensure newRef is traced.
        if phase == .marking {
            mark(ref: newRef, heap: heap)
        }
        _ = owner
    }

    private func heapCount(_ heap: VMHeap) -> Int {
        // Approx: allObjectIDs contains IDs, but some may have been removed.
        allObjectIDs.count
    }

    private func mark(ref: ObjectRef, heap: VMHeap) {
        guard let obj = try? heap.get(ref) else { return }
        // We don't store color per ref id, but per object.
        if obj.gcColor == .white {
            obj.gcColor = .gray
            grayStack.append(ref)
        }
    }

    private func scan(ref: ObjectRef, heap: VMHeap) {
        guard let obj = try? heap.get(ref) else { return }
        for v in obj.fields {
            if case .reference(let r) = v {
                mark(ref: r, heap: heap)
            }
        }
        if let closure = obj as? KiraClosure {
            for v in closure.captures {
                if case .reference(let r) = v {
                    mark(ref: r, heap: heap)
                }
            }
        }
        obj.gcColor = .black
    }

    private func sweep(heap: VMHeap, budget: Int) {
        var remaining = budget
        while remaining > 0, sweepCursor < allObjectIDs.count {
            let id = allObjectIDs[sweepCursor]
            sweepCursor += 1
            remaining -= 1
            let ref = ObjectRef(id)
            guard let obj = try? heap.get(ref) else { continue }
            if obj.gcColor == .white {
                heap.remove(ref)
            } else {
                obj.gcColor = .white
            }
        }
    }
}

