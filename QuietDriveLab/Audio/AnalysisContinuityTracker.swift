import Foundation

struct AnalysisContinuityTracker: Sendable {
    private(set) var nextExpectedSequence: UInt64?

    mutating func reset(
        startingAt sequence: UInt64
    ) {
        nextExpectedSequence = sequence
    }

    mutating func record(
        sequence: UInt64
    ) -> Bool {
        guard
            let expected =
                nextExpectedSequence
        else {
            nextExpectedSequence =
                sequence &+ 1
            return false
        }

        guard sequence >= expected else {
            return false
        }

        let continuityWasBroken =
            sequence > expected

        nextExpectedSequence =
            sequence &+ 1

        return continuityWasBroken
    }
}
