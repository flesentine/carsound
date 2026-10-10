import AVFAudio
import Foundation

final class RealtimeAudioFrameHandoff: @unchecked Sendable {
    final class FrameSlot: @unchecked Sendable {
        fileprivate enum State {
            case empty
            case writing
            case ready
            case processing
        }

        fileprivate var state: State = .empty

        let monoSamples: [Float]
        fileprivate var writableMonoSamples: [Float]

        fileprivate(set) var frameCount = 0
        fileprivate(set) var sampleRate = 0.0
        fileprivate(set) var channelCount: AVAudioChannelCount = 0
        fileprivate(set) var commonFormat: AVAudioCommonFormat = .otherFormat
        fileprivate(set) var isInterleaved = false
        fileprivate(set) var callbackStartedNanoseconds: UInt64 = 0
        fileprivate(set) var durationMilliseconds = 0.0
        fileprivate(set) var levelMeasurement: AudioLevelMeasurement = .silent

        fileprivate init(maxFrameCount: Int) {
            let samples = Array(repeating: Float.zero, count: maxFrameCount)
            monoSamples = samples
            writableMonoSamples = samples
        }

        fileprivate func synchronizeReadBuffer() {
            // Array is copy-on-write. This assignment keeps the public read
            // view aligned with storage without allocating after init.
        }
    }

    private let lock = NSLock()
    private let maxFrameCount: Int
    private var slots: [FrameSlot]

    init(
        capacity: Int = 4,
        maxFrameCount: Int = 8_192
    ) {
        precondition(capacity > 0)
        precondition(maxFrameCount > 0)

        self.maxFrameCount = maxFrameCount
        slots = (0..<capacity).map { _ in
            FrameSlot(maxFrameCount: maxFrameCount)
        }
    }

    var capacity: Int {
        slots.count
    }

    func enqueue(
        buffer: AVAudioPCMBuffer,
        callbackStartedNanoseconds: UInt64
    ) -> Int? {
        guard
            buffer.frameLength > 0,
            buffer.format.commonFormat == .pcmFormatFloat32,
            let channelData = buffer.floatChannelData
        else {
            return nil
        }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let sampleRate = buffer.format.sampleRate

        guard
            frameCount > 0,
            frameCount <= maxFrameCount,
            channelCount > 0,
            sampleRate.isFinite,
            sampleRate > 0
        else {
            return nil
        }

        let slotIndex: Int

        lock.lock()
        if let availableIndex = slots.firstIndex(where: { $0.state == .empty }) {
            slotIndex = availableIndex
            slots[availableIndex].state = .writing
            lock.unlock()
        } else {
            lock.unlock()
            return nil
        }

        let slot = slots[slotIndex]
        var sumSquares = 0.0
        var peak: Float = 0
        var clippedSamples: UInt64 = 0
        var totalSamples = 0

        if buffer.format.isInterleaved {
            let samples = channelData[0]

            for frame in 0..<frameCount {
                let base = frame * channelCount
                var monoSum: Float = 0

                for channel in 0..<channelCount {
                    let sample = samples[base + channel]
                    let magnitude = abs(sample)

                    monoSum += sample
                    sumSquares += Double(sample * sample)
                    peak = max(peak, magnitude)
                    if magnitude >= AudioLevelAnalyzer.clippingThreshold {
                        clippedSamples += 1
                    }
                }

                slot.writableMonoSamples[frame] =
                    monoSum / Float(channelCount)
            }

            totalSamples = frameCount * channelCount
        } else {
            for frame in 0..<frameCount {
                var monoSum: Float = 0

                for channel in 0..<channelCount {
                    let sample = channelData[channel][frame]
                    let magnitude = abs(sample)

                    monoSum += sample
                    sumSquares += Double(sample * sample)
                    peak = max(peak, magnitude)
                    if magnitude >= AudioLevelAnalyzer.clippingThreshold {
                        clippedSamples += 1
                    }
                }

                slot.writableMonoSamples[frame] =
                    monoSum / Float(channelCount)
            }

            totalSamples = frameCount * channelCount
        }

        let rms: Float
        if totalSamples > 0 {
            rms = Float(
                sqrt(sumSquares / Double(totalSamples))
            )
        } else {
            rms = 0
        }

        slot.frameCount = frameCount
        slot.sampleRate = sampleRate
        slot.channelCount = buffer.format.channelCount
        slot.commonFormat = buffer.format.commonFormat
        slot.isInterleaved = buffer.format.isInterleaved
        slot.callbackStartedNanoseconds =
            callbackStartedNanoseconds
        slot.durationMilliseconds =
            Double(frameCount) / sampleRate * 1_000
        slot.levelMeasurement =
            AudioLevelMeasurement(
                rmsLinear: rms,
                peakLinear: peak,
                clippedSampleCount: clippedSamples
            )

        lock.lock()
        slot.state = .ready
        lock.unlock()

        return slotIndex
    }

    func nextReadyIndex() -> Int? {
        lock.lock()
        defer { lock.unlock() }

        return slots.firstIndex {
            $0.state == .ready
        }
    }

    func consume(
        slotAt index: Int,
        _ body: (FrameSlot) -> Void
    ) {
        lock.lock()

        guard
            slots.indices.contains(index),
            slots[index].state == .ready
        else {
            lock.unlock()
            return
        }

        let slot = slots[index]
        slot.state = .processing
        lock.unlock()

        body(slot)

        lock.lock()
        slot.state = .empty
        lock.unlock()
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        for slot in slots {
            slot.state = .empty
            slot.frameCount = 0
            slot.sampleRate = 0
            slot.channelCount = 0
            slot.commonFormat = .otherFormat
            slot.isInterleaved = false
            slot.callbackStartedNanoseconds = 0
            slot.durationMilliseconds = 0
            slot.levelMeasurement = .silent
        }
    }
}
