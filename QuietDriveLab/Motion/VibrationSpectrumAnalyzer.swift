import Foundation

struct VibrationSpectrumBin: Equatable, Sendable {
    let frequencyHz: Double
    let amplitudeG: Double

    var amplitudeMilliG: Double {
        amplitudeG * 1_000
    }
}

struct VibrationPeak: Equatable, Sendable, Identifiable {
    let frequencyHz: Double
    let amplitudeG: Double

    var id: String {
        String(
            format: "%.3f",
            frequencyHz
        )
    }

    var amplitudeMilliG: Double {
        amplitudeG * 1_000
    }
}

struct VibrationSpectrumSnapshot: Equatable, Sendable {
    let sampleCount: Int
    let observedSampleRateHz: Double
    let nyquistFrequencyHz: Double
    let maximumAnalyzedFrequencyHz: Double
    let frequencyResolutionHz: Double
    let highPassCutoffHz: Double
    let dynamicRMSG: Double
    let bins: [VibrationSpectrumBin]
    let dominantPeaks: [VibrationPeak]

    static let empty = VibrationSpectrumSnapshot(
        sampleCount: 0,
        observedSampleRateHz: 0,
        nyquistFrequencyHz: 0,
        maximumAnalyzedFrequencyHz: 0,
        frequencyResolutionHz: 0,
        highPassCutoffHz:
            VibrationSpectrumAnalyzer
                .highPassCutoffHz,
        dynamicRMSG: 0,
        bins: [],
        dominantPeaks: []
    )

    var canResolveSeventyTwoHz: Bool {
        maximumAnalyzedFrequencyHz >= 72
    }
}

enum VibrationSpectrumAnalyzer {
    static let preferredFFTSize = 512
    static let minimumFFTSize = 256
    static let highPassCutoffHz = 1.5
    static let minimumAnalyzedFrequencyHz = 2.0
    static let maximumTargetFrequencyHz = 100.0
    static let nyquistSafetyFraction = 0.90
    static let maximumPeakCount = 5
    static let minimumPeakSeparationHz = 2.0
    static let minimumPeakAmplitudeG = 0.000_05

    static func analyze(
        samples: [AccelerometerSample]
    ) -> VibrationSpectrumSnapshot {
        guard samples.count >= minimumFFTSize else {
            return .empty
        }

        let fftSize = selectedFFTSize(
            availableSamples: samples.count
        )
        let selected = Array(
            samples.suffix(fftSize)
        )

        guard
            let first = selected.first,
            let last = selected.last,
            last.timestampSeconds >
                first.timestampSeconds
        else {
            return .empty
        }

        let duration =
            last.timestampSeconds -
            first.timestampSeconds
        let observedSampleRate =
            Double(fftSize - 1) / duration

        guard observedSampleRate > 0 else {
            return .empty
        }

        let uniform = resampleUniformly(
            samples: selected,
            sampleCount: fftSize
        )

        guard uniform.count == fftSize else {
            return .empty
        }

        let dt = 1.0 / observedSampleRate

        let x = highPass(
            uniform.map(\.xG),
            cutoffHz: highPassCutoffHz,
            dt: dt
        )
        let y = highPass(
            uniform.map(\.yG),
            cutoffHz: highPassCutoffHz,
            dt: dt
        )
        let z = highPass(
            uniform.map(\.zG),
            cutoffHz: highPassCutoffHz,
            dt: dt
        )

        let dynamicRMS = vectorRMS(
            x: x,
            y: y,
            z: z
        )

        let xSpectrum = fftAmplitudes(
            samples: x
        )
        let ySpectrum = fftAmplitudes(
            samples: y
        )
        let zSpectrum = fftAmplitudes(
            samples: z
        )

        let resolution =
            observedSampleRate /
            Double(fftSize)
        let nyquist =
            observedSampleRate / 2.0
        let maximumAnalyzed =
            min(
                maximumTargetFrequencyHz,
                nyquist *
                    nyquistSafetyFraction
            )

        let maximumBin = min(
            fftSize / 2,
            Int(
                floor(
                    maximumAnalyzed /
                    resolution
                )
            )
        )

        guard maximumBin >= 1 else {
            return .empty
        }

        var bins: [VibrationSpectrumBin] = []
        bins.reserveCapacity(maximumBin + 1)

        for index in 0...maximumBin {
            let frequency =
                Double(index) *
                resolution

            guard
                frequency >=
                    minimumAnalyzedFrequencyHz
            else {
                continue
            }

            let amplitude = sqrt(
                xSpectrum[index] *
                    xSpectrum[index] +
                ySpectrum[index] *
                    ySpectrum[index] +
                zSpectrum[index] *
                    zSpectrum[index]
            )

            bins.append(
                VibrationSpectrumBin(
                    frequencyHz: frequency,
                    amplitudeG: amplitude
                )
            )
        }

        return VibrationSpectrumSnapshot(
            sampleCount: fftSize,
            observedSampleRateHz:
                observedSampleRate,
            nyquistFrequencyHz: nyquist,
            maximumAnalyzedFrequencyHz:
                maximumAnalyzed,
            frequencyResolutionHz:
                resolution,
            highPassCutoffHz:
                highPassCutoffHz,
            dynamicRMSG: dynamicRMS,
            bins: bins,
            dominantPeaks:
                dominantPeaks(
                    from: bins
                )
        )
    }

    static func selectedFFTSize(
        availableSamples: Int
    ) -> Int {
        guard
            availableSamples >=
                minimumFFTSize
        else {
            return 0
        }

        var size =
            min(
                preferredFFTSize,
                availableSamples
            )

        while
            size > minimumFFTSize,
            size.nonzeroBitCount != 1
        {
            size -= 1
        }

        if size.nonzeroBitCount == 1 {
            return size
        }

        return minimumFFTSize
    }

    static func resampleUniformly(
        samples: [AccelerometerSample],
        sampleCount: Int
    ) -> [AccelerometerSample] {
        guard
            sampleCount > 1,
            samples.count >= 2,
            let first = samples.first,
            let last = samples.last,
            last.timestampSeconds >
                first.timestampSeconds
        else {
            return []
        }

        let start = first.timestampSeconds
        let duration =
            last.timestampSeconds - start
        let interval =
            duration /
            Double(sampleCount - 1)

        var result:
            [AccelerometerSample] = []
        result.reserveCapacity(sampleCount)

        var sourceIndex = 0

        for targetIndex in 0..<sampleCount {
            let timestamp =
                start +
                Double(targetIndex) *
                interval

            while
                sourceIndex + 1 <
                    samples.count - 1,
                samples[sourceIndex + 1]
                    .timestampSeconds <
                    timestamp
            {
                sourceIndex += 1
            }

            let left = samples[sourceIndex]
            let right = samples[
                min(
                    sourceIndex + 1,
                    samples.count - 1
                )
            ]

            let span =
                right.timestampSeconds -
                left.timestampSeconds

            let fraction: Double
            if span > 0 {
                fraction =
                    min(
                        1,
                        max(
                            0,
                            (
                                timestamp -
                                left.timestampSeconds
                            ) / span
                        )
                    )
            } else {
                fraction = 0
            }

            result.append(
                AccelerometerSample(
                    timestampSeconds: timestamp,
                    xG: interpolate(
                        left.xG,
                        right.xG,
                        fraction: fraction
                    ),
                    yG: interpolate(
                        left.yG,
                        right.yG,
                        fraction: fraction
                    ),
                    zG: interpolate(
                        left.zG,
                        right.zG,
                        fraction: fraction
                    )
                )
            )
        }

        return result
    }

    static func highPass(
        _ samples: [Double],
        cutoffHz: Double,
        dt: Double
    ) -> [Double] {
        guard
            samples.count > 1,
            cutoffHz > 0,
            dt > 0
        else {
            return samples
        }

        let rc =
            1.0 /
            (2.0 * .pi * cutoffHz)
        let alpha =
            rc / (rc + dt)

        var output =
            Array(
                repeating: 0.0,
                count: samples.count
            )

        var previousInput =
            samples[0]
        var previousOutput = 0.0

        for index in 1..<samples.count {
            let current =
                alpha *
                (
                    previousOutput +
                    samples[index] -
                    previousInput
                )

            output[index] = current
            previousOutput = current
            previousInput = samples[index]
        }

        return output
    }

    static func vectorRMS(
        x: [Double],
        y: [Double],
        z: [Double]
    ) -> Double {
        let count =
            min(
                x.count,
                min(
                    y.count,
                    z.count
                )
            )

        guard count > 0 else {
            return 0
        }

        var sum = 0.0

        for index in 0..<count {
            sum +=
                x[index] * x[index] +
                y[index] * y[index] +
                z[index] * z[index]
        }

        return sqrt(
            sum /
            Double(count)
        )
    }

    static func dominantPeaks(
        from bins: [VibrationSpectrumBin]
    ) -> [VibrationPeak] {
        guard bins.count >= 3 else {
            return []
        }

        var candidates:
            [VibrationPeak] = []

        for index in 1..<(bins.count - 1) {
            let left = bins[index - 1]
            let current = bins[index]
            let right = bins[index + 1]

            guard
                current.amplitudeG >=
                    minimumPeakAmplitudeG,
                current.amplitudeG >
                    left.amplitudeG,
                current.amplitudeG >=
                    right.amplitudeG
            else {
                continue
            }

            candidates.append(
                VibrationPeak(
                    frequencyHz:
                        current.frequencyHz,
                    amplitudeG:
                        current.amplitudeG
                )
            )
        }

        candidates.sort {
            $0.amplitudeG >
            $1.amplitudeG
        }

        var selected:
            [VibrationPeak] = []

        for candidate in candidates {
            guard
                !selected.contains(
                    where: {
                        abs(
                            $0.frequencyHz -
                            candidate.frequencyHz
                        ) <
                        minimumPeakSeparationHz
                    }
                )
            else {
                continue
            }

            selected.append(candidate)

            if selected.count ==
                maximumPeakCount
            {
                break
            }
        }

        return selected
    }

    private static func fftAmplitudes(
        samples: [Double]
    ) -> [Double] {
        let count = samples.count

        guard
            count > 1,
            count.nonzeroBitCount == 1
        else {
            return []
        }

        let denominator =
            Double(count - 1)
        let window = (0..<count).map {
            index in
            0.5 -
            0.5 *
            cos(
                2.0 *
                .pi *
                Double(index) /
                denominator
            )
        }
        let windowSum =
            window.reduce(0, +)

        var real =
            zip(samples, window)
            .map { pair in
                pair.0 * pair.1
            }
        var imag =
            Array(
                repeating: 0.0,
                count: count
            )

        fftInPlace(
            real: &real,
            imag: &imag
        )

        let nyquistBin =
            count / 2
        var amplitudes =
            Array(
                repeating: 0.0,
                count: nyquistBin + 1
            )

        for bin in 0...nyquistBin {
            let magnitude =
                hypot(
                    real[bin],
                    imag[bin]
                )
            let scale =
                (bin == 0 ||
                 bin == nyquistBin)
                ? 1.0
                : 2.0

            amplitudes[bin] =
                scale *
                magnitude /
                windowSum
        }

        return amplitudes
    }

    private static func fftInPlace(
        real: inout [Double],
        imag: inout [Double]
    ) {
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
            let angle =
                -2.0 *
                Double.pi /
                Double(length)
            let wLengthReal =
                cos(angle)
            let wLengthImag =
                sin(angle)
            let halfLength =
                length / 2
            var start = 0

            while start < count {
                var wReal = 1.0
                var wImag = 0.0

                for offset in 0..<halfLength {
                    let evenIndex =
                        start + offset
                    let oddIndex =
                        evenIndex +
                        halfLength

                    let oddReal =
                        real[oddIndex] *
                            wReal -
                        imag[oddIndex] *
                            wImag
                    let oddImag =
                        real[oddIndex] *
                            wImag +
                        imag[oddIndex] *
                            wReal
                    let evenReal =
                        real[evenIndex]
                    let evenImag =
                        imag[evenIndex]

                    real[evenIndex] =
                        evenReal +
                        oddReal
                    imag[evenIndex] =
                        evenImag +
                        oddImag
                    real[oddIndex] =
                        evenReal -
                        oddReal
                    imag[oddIndex] =
                        evenImag -
                        oddImag

                    let nextWReal =
                        wReal *
                            wLengthReal -
                        wImag *
                            wLengthImag
                    wImag =
                        wReal *
                            wLengthImag +
                        wImag *
                            wLengthReal
                    wReal =
                        nextWReal
                }

                start += length
            }

            length <<= 1
        }
    }

    private static func interpolate(
        _ left: Double,
        _ right: Double,
        fraction: Double
    ) -> Double {
        left +
        (right - left) *
        fraction
    }
}
