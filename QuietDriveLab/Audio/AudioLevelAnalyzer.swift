import AVFAudio
import Foundation

struct AudioLevelMeasurement: Equatable, Sendable {
    let rmsLinear: Float
    let peakLinear: Float
    let clippedSampleCount: UInt64

    static let silent = AudioLevelMeasurement(
        rmsLinear: 0,
        peakLinear: 0,
        clippedSampleCount: 0
    )
}

enum AudioLevelAnalyzer {
    static let clippingThreshold: Float = 0.99
    static let meterFloorDBFS = -80.0
    static let silenceFloorDBFS = -120.0

    static func analyze(buffer: AVAudioPCMBuffer) -> AudioLevelMeasurement {
        guard
            buffer.frameLength > 0,
            let channelData = buffer.floatChannelData
        else {
            return .silent
        }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        guard frameCount > 0, channelCount > 0 else {
            return .silent
        }

        var sumSquares: Double = 0
        var peak: Float = 0
        var clippedSamples: UInt64 = 0
        var totalSamples = 0

        if buffer.format.isInterleaved {
            let samples = channelData[0]
            let sampleCount = frameCount * channelCount

            for index in 0..<sampleCount {
                let sample = samples[index]
                let magnitude = abs(sample)

                sumSquares += Double(sample * sample)
                peak = max(peak, magnitude)
                if magnitude >= clippingThreshold {
                    clippedSamples += 1
                }
            }

            totalSamples = sampleCount
        } else {
            for channel in 0..<channelCount {
                let samples = channelData[channel]

                for frame in 0..<frameCount {
                    let sample = samples[frame]
                    let magnitude = abs(sample)

                    sumSquares += Double(sample * sample)
                    peak = max(peak, magnitude)
                    if magnitude >= clippingThreshold {
                        clippedSamples += 1
                    }
                }

                totalSamples += frameCount
            }
        }

        guard totalSamples > 0 else {
            return .silent
        }

        let rms = Float(sqrt(sumSquares / Double(totalSamples)))

        return AudioLevelMeasurement(
            rmsLinear: rms,
            peakLinear: peak,
            clippedSampleCount: clippedSamples
        )
    }

    static func decibelsFS(forAmplitude amplitude: Float) -> Double {
        guard amplitude > 0 else { return silenceFloorDBFS }
        return max(silenceFloorDBFS, 20.0 * log10(Double(amplitude)))
    }

    static func meterPosition(forDBFS dbFS: Double) -> Double {
        let clamped = min(0, max(meterFloorDBFS, dbFS))
        return (clamped - meterFloorDBFS) / -meterFloorDBFS
    }
}
