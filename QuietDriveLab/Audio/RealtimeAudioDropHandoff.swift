import Foundation

final class RealtimeAudioDropHandoff: @unchecked Sendable {
    final class DropSlot: @unchecked Sendable {
        fileprivate enum State {
            case empty
            case writing
            case ready
            case processing
        }

        fileprivate let stateLock = NSLock()
        fileprivate var state: State = .empty

        fileprivate(set) var frameCount: UInt64 = 0
        fileprivate(set) var callbackStartedNanoseconds: UInt64 = 0
        fileprivate(set) var callbackSequence: UInt64 = 0
        fileprivate(set) var enqueueSequence: UInt64 = 0
        fileprivate(set) var captureGeneration: UInt64 = 0
    }

    private var slots: [DropSlot]

    // The AVAudioEngine tap invokes this producer serially. Reset is allowed
    // only after capture has stopped and the analysis queue has drained.
    private var nextEnqueueSequence: UInt64 = 1

    init(capacity: Int = 256) {
        precondition(capacity > 0)
        slots = (0..<capacity).map { _ in
            DropSlot()
        }
    }

    var capacity: Int {
        slots.count
    }

    func enqueue(
        frameCount: UInt64,
        callbackStartedNanoseconds: UInt64,
        callbackSequence: UInt64,
        captureGeneration: UInt64
    ) -> Int? {
        var claimedIndex: Int?

        for index in slots.indices {
            let slot = slots[index]

            guard slot.stateLock.try() else {
                continue
            }

            if slot.state == .empty {
                slot.state = .writing
                slot.enqueueSequence =
                    nextEnqueueSequence
                nextEnqueueSequence &+= 1
                claimedIndex = index
                break
            }

            slot.stateLock.unlock()
        }

        guard let index = claimedIndex else {
            return nil
        }

        let slot = slots[index]
        slot.frameCount = frameCount
        slot.callbackStartedNanoseconds =
            callbackStartedNanoseconds
        slot.callbackSequence =
            callbackSequence
        slot.captureGeneration =
            captureGeneration
        slot.state = .ready
        slot.stateLock.unlock()

        return index
    }

    func nextReadyIndex() -> Int? {
        var candidate:
            (index: Int, sequence: UInt64)?

        for index in slots.indices {
            let slot = slots[index]

            guard slot.stateLock.try() else {
                continue
            }

            if slot.state == .ready {
                let sequence = slot.enqueueSequence

                if
                    candidate == nil ||
                    sequence <
                        candidate!.sequence
                {
                    candidate =
                        (index, sequence)
                }
            }

            slot.stateLock.unlock()
        }

        return candidate?.index
    }

    func consume(
        slotAt index: Int,
        _ body: (DropSlot) -> Void
    ) {
        guard slots.indices.contains(index) else {
            return
        }

        let slot = slots[index]

        guard slot.stateLock.try() else {
            return
        }

        guard slot.state == .ready else {
            slot.stateLock.unlock()
            return
        }

        slot.state = .processing
        slot.stateLock.unlock()

        body(slot)

        slot.stateLock.lock()
        slot.state = .empty
        slot.stateLock.unlock()
    }

    func reset() {
        nextEnqueueSequence = 1

        for slot in slots {
            slot.stateLock.lock()
            slot.state = .empty
            slot.frameCount = 0
            slot.callbackStartedNanoseconds = 0
            slot.callbackSequence = 0
            slot.enqueueSequence = 0
            slot.captureGeneration = 0
            slot.stateLock.unlock()
        }
    }
}
