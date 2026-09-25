import AVFAudio
import Foundation

struct SpectrumBin: Equatable, Sendable {
    let frequencyHz: Double
    let magnitudeDBFS: Double
}

struct FFTSnapshot: Equatable, Sendable {
    let sampleCount: Int
    let sampleRate: Double
    let frequencyResolutionHz: Double
    let windowName: String
    let transformCount: UInt64
    let bins: [SpectrumBin]

    static let empty = FFTSnapshot(
        sampleCount: 0,
        sampleRate: 0,
        frequencyResolutionHz: 0,
        windowName: "Hann",
        transformCount: 0,
        bins: []
    )
}

final class FFTAnalyzer {
    static let fftSize = 4_096
    static let windowName = "Hann"
    static let magnitudeFloorDBFS = -140.0

    private let size: Int
    private var ring: [Float]
    private var writeIndex = 0
    private var samplesWritten = 0

    private var real: [Double]
    private var imag: [Double]
    private let window: [Double]
    private let windowSum: Double

    private(set) var transformCount: UInt64 = 0

    init(size: Int = FFTAnalyzer.fftSize) {
        precondition(size > 1 && size.nonzeroBitCount == 1, "FFT size must be a power of two")

        self.size = size
        self.ring = Array(repeating: 0, count: size)
        self.real = Array(repeating: 0, count: size)
        self.imag = Array(repeating: 0, count: size)

        let denominator = Double(size - 1)
        self.window = (0..<size).map { index in
            0.5 - 0.5 * cos(2.0 * .pi * Double(index) / denominator)
        }
        self.windowSum = window.reduce(0, +)
    }

    func reset() {
        ring = Array(repeating: 0, count: size)
        writeIndex = 0
        samplesWritten = 0
        transformCount = 0
        real = Array(repeating: 0, count: size)
        imag = Array(repeating: 0, count: size)
    }

    func ingest(buffer: AVAudioPCMBuffer) -> FFTSnapshot? {
        guard
            buffer.frameLength > 0,
            buffer.format.commonFormat == .pcmFormatFloat32,
            let channelData = buffer.floatChannelData
        else {
            return nil
        }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        guard frameCount > 0, channelCount > 0, buffer.format.sampleRate > 0 else {
            return nil
        }

        var mono = Array(repeating: Float.zero, count: frameCount)

        if buffer.format.isInterleaved {
            let samples = channelData[0]

            for frame in 0..<frameCount {
                var sum: Float = 0
                let base = frame * channelCount

                for channel in 0..<channelCount {
                    sum += samples[base + channel]
                }

                mono[frame] = sum / Float(channelCount)
            }
        } else {
            for frame in 0..<frameCount {
                var sum: Float = 0

                for channel in 0..<channelCount {
                    sum += channelData[channel][frame]
                }

                mono[frame] = sum / Float(channelCount)
            }
        }

        return ingest(samples: mono, sampleRate: buffer.format.sampleRate)
    }

    func ingest(samples: [Float], sampleRate: Double) -> FFTSnapshot? {
        guard !samples.isEmpty, sampleRate > 0 else { return nil }

        for sample in samples {
            ring[writeIndex] = sample
            writeIndex += 1

            if writeIndex == size {
                writeIndex = 0
            }

            samplesWritten = min(size, samplesWritten + 1)
        }

        guard samplesWritten == size else { return nil }

        prepareWindowedInput()
        fftInPlace(real: &real, imag: &imag)

        transformCount += 1

        let resolution = sampleRate / Double(size)
        let nyquistBin = size / 2
        var bins = [SpectrumBin]()
        bins.reserveCapacity(nyquistBin + 1)

        for bin in 0...nyquistBin {
            let magnitude = hypot(real[bin], imag[bin])
            let scale = (bin == 0 || bin == nyquistBin) ? 1.0 : 2.0
            let amplitude = scale * magnitude / windowSum
            let dbFS: Double

            if amplitude > 0 {
                dbFS = max(Self.magnitudeFloorDBFS, 20.0 * log10(amplitude))
            } else {
                dbFS = Self.magnitudeFloorDBFS
            }

            bins.append(
                SpectrumBin(
                    frequencyHz: Double(bin) * resolution,
                    magnitudeDBFS: dbFS
                )
            )
        }

        return FFTSnapshot(
            sampleCount: size,
            sampleRate: sampleRate,
            frequencyResolutionHz: resolution,
            windowName: Self.windowName,
            transformCount: transformCount,
            bins: bins
        )
    }

    private func prepareWindowedInput() {
        for index in 0..<size {
            let ringIndex = (writeIndex + index) % size
            real[index] = Double(ring[ringIndex]) * window[index]
            imag[index] = 0
        }
    }

    private func fftInPlace(real: inout [Double], imag: inout [Double]) {
        let count = real.count
        var j = 0

        if count > 1 {
            for i in 1..<(count - 1) {
                var bit = count >> 1

                while j & bit != 0 {
                    j ^= bit
                    bit >>= 1
                }

                j ^= bit

                if i < j {
                    real.swapAt(i, j)
                    imag.swapAt(i, j)
                }
            }
        }

        var length = 2

        while length <= count {
            let angle = -2.0 * Double.pi / Double(length)
            let wLengthReal = cos(angle)
            let wLengthImag = sin(angle)
            let halfLength = length / 2
            var start = 0

            while start < count {
                var wReal = 1.0
                var wImag = 0.0

                for offset in 0..<halfLength {
                    let evenIndex = start + offset
                    let oddIndex = evenIndex + halfLength

                    let oddReal = real[oddIndex] * wReal - imag[oddIndex] * wImag
                    let oddImag = real[oddIndex] * wImag + imag[oddIndex] * wReal
                    let evenReal = real[evenIndex]
                    let evenImag = imag[evenIndex]

                    real[evenIndex] = evenReal + oddReal
                    imag[evenIndex] = evenImag + oddImag
                    real[oddIndex] = evenReal - oddReal
                    imag[oddIndex] = evenImag - oddImag

                    let nextWReal = wReal * wLengthReal - wImag * wLengthImag
                    wImag = wReal * wLengthImag + wImag * wLengthReal
                    wReal = nextWReal
                }

                start += length
            }

            length <<= 1
        }
    }
}
