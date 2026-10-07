import Foundation

enum MusicInterferenceLevel: String, Equatable, Sendable {
    case clear = "Clear"
    case possible = "Possible interference"
    case likely = "Likely interference"
}

struct MusicInterferenceSnapshot: Equatable, Sendable {
    let level: MusicInterferenceLevel
    let instantaneousScore: Double
    let smoothedScore: Double

    let programBandLevelDBFS: Double
    let lowBandLevelDBFS: Double
    let programToLowRatioDB: Double

    let occupiedBinRatio: Double
    let spectralFlatness: Double
    let spectralFlux: Double
    let analyzedBinCount: Int
    let updateCount: UInt64

    static let empty = MusicInterferenceSnapshot(
        level: .clear,
        instantaneousScore: 0,
        smoothedScore: 0,
        programBandLevelDBFS:
            FFTAnalyzer.magnitudeFloorDBFS,
        lowBandLevelDBFS:
            FFTAnalyzer.magnitudeFloorDBFS,
        programToLowRatioDB: 0,
        occupiedBinRatio: 0,
        spectralFlatness: 0,
        spectralFlux: 0,
        analyzedBinCount: 0,
        updateCount: 0
    )
}

enum MusicInterferenceMath {
    static let lowBandHz = 30.0...200.0
    static let programBandHz =
        200.0.nextUp...4_000.0

    static let likelyThreshold = 0.62
    static let possibleThreshold = 0.38

    static func bandLevelDBFS(
        bins: [SpectrumBin],
        range: ClosedRange<Double>
    ) -> Double {
        let values = bins
            .filter {
                range.contains(
                    $0.frequencyHz
                )
            }
            .map {
                power(
                    dbFS: $0.magnitudeDBFS
                )
            }

        guard !values.isEmpty else {
            return FFTAnalyzer
                .magnitudeFloorDBFS
        }

        let average =
            values.reduce(0, +) /
            Double(values.count)

        return decibels(
            power: average
        )
    }

    static func occupiedBinRatio(
        bins: [SpectrumBin],
        range: ClosedRange<Double>
    ) -> Double {
        let band = bins.filter {
            range.contains(
                $0.frequencyHz
            )
        }

        let magnitudes =
            band.map {
                $0.magnitudeDBFS
            }

        guard
            !magnitudes.isEmpty,
            let peak = magnitudes.max()
        else {
            return 0
        }

        let threshold = max(
            -82.0,
            peak - 28.0
        )

        let occupied = band.filter {
            $0.magnitudeDBFS >=
                threshold
        }.count

        return Double(occupied) /
            Double(band.count)
    }

    static func spectralFlatness(
        bins: [SpectrumBin],
        range: ClosedRange<Double>
    ) -> Double {
        let powers = bins
            .filter {
                range.contains(
                    $0.frequencyHz
                )
            }
            .map {
                max(
                    power(
                        dbFS:
                            $0.magnitudeDBFS
                    ),
                    1e-14
                )
            }

        guard !powers.isEmpty else {
            return 0
        }

        let arithmeticMean =
            powers.reduce(0, +) /
            Double(powers.count)

        guard arithmeticMean > 0 else {
            return 0
        }

        let logMean =
            powers
                .map(log)
                .reduce(0, +) /
            Double(powers.count)
        let geometricMean =
            exp(logMean)

        return min(
            1,
            max(
                0,
                geometricMean /
                    arithmeticMean
            )
        )
    }

    static func spectralFlux(
        current: [SpectrumBin],
        previous: [SpectrumBin],
        range: ClosedRange<Double>
    ) -> Double {
        guard
            !current.isEmpty,
            !previous.isEmpty
        else {
            return 0
        }

        let previousByKey =
            Dictionary(
                uniqueKeysWithValues:
                    previous.map {
                        (
                            frequencyKey(
                                $0.frequencyHz
                            ),
                            $0.magnitudeDBFS
                        )
                    }
            )

        var differences: [Double] = []

        for bin in current
        where range.contains(
            bin.frequencyHz
        ) {
            guard
                let prior =
                    previousByKey[
                        frequencyKey(
                            bin.frequencyHz
                        )
                    ]
            else {
                continue
            }

            differences.append(
                min(
                    30,
                    abs(
                        bin.magnitudeDBFS -
                        prior
                    )
                )
            )
        }

        guard !differences.isEmpty else {
            return 0
        }

        let meanDifference =
            differences.reduce(0, +) /
            Double(differences.count)

        return min(
            1,
            max(
                0,
                meanDifference / 10.0
            )
        )
    }

    static func score(
        programLevelDBFS: Double,
        lowLevelDBFS: Double,
        occupiedBinRatio: Double,
        spectralFlatness: Double,
        spectralFlux: Double
    ) -> Double {
        let activity =
            clamp01(
                (
                    programLevelDBFS +
                    78.0
                ) / 32.0
            )

        let occupancy =
            clamp01(
                (
                    occupiedBinRatio -
                    0.08
                ) / 0.42
            )

        let flatness =
            clamp01(
                (
                    spectralFlatness -
                    0.02
                ) / 0.28
            )

        let dynamics =
            clamp01(
                spectralFlux
            )

        let ratioDB =
            programLevelDBFS -
            lowLevelDBFS
        let programPresence =
            clamp01(
                (
                    ratioDB +
                    24.0
                ) / 24.0
            )

        var result = clamp01(
            0.34 * activity +
            0.26 * occupancy +
            0.16 * flatness +
            0.16 * dynamics +
            0.08 * programPresence
        )

        // A single strong sine/test tone can make the average
        // program-band level look high even though almost no
        // spectrum is occupied. Do not call that music.
        if
            occupiedBinRatio < 0.05 &&
            spectralFlatness < 0.02
        {
            result = min(result, 0.25)
        }

        // Broad but nearly static road/wind noise can look
        // program-like in one FFT. Require temporal movement
        // before elevating the result to "likely".
        if spectralFlux < 0.08 {
            result = min(result, 0.58)
        }

        return result
    }

    static func level(
        for smoothedScore: Double
    ) -> MusicInterferenceLevel {
        if
            smoothedScore >=
                likelyThreshold
        {
            return .likely
        }

        if
            smoothedScore >=
                possibleThreshold
        {
            return .possible
        }

        return .clear
    }

    private static func power(
        dbFS: Double
    ) -> Double {
        pow(
            10.0,
            dbFS / 10.0
        )
    }

    private static func decibels(
        power: Double
    ) -> Double {
        guard power > 0 else {
            return FFTAnalyzer
                .magnitudeFloorDBFS
        }

        return max(
            FFTAnalyzer
                .magnitudeFloorDBFS,
            10.0 * log10(power)
        )
    }

    private static func frequencyKey(
        _ frequencyHz: Double
    ) -> Int {
        Int(
            (
                frequencyHz *
                1_000
            ).rounded()
        )
    }

    private static func clamp01(
        _ value: Double
    ) -> Double {
        min(
            1,
            max(
                0,
                value
            )
        )
    }
}

final class MusicInterferenceDetector {
    private let smoothingAlpha: Double

    private var previousSpectrum:
        [SpectrumBin] = []
    private var smoothedScore = 0.0
    private var updateCount: UInt64 = 0

    init(
        smoothingAlpha: Double = 0.30
    ) {
        precondition(
            smoothingAlpha > 0 &&
            smoothingAlpha <= 1
        )

        self.smoothingAlpha =
            smoothingAlpha
    }

    func reset() {
        previousSpectrum = []
        smoothedScore = 0
        updateCount = 0
    }

    func process(
        _ bins: [SpectrumBin]
    ) -> MusicInterferenceSnapshot {
        guard !bins.isEmpty else {
            return .empty
        }

        let programLevel =
            MusicInterferenceMath
                .bandLevelDBFS(
                    bins: bins,
                    range:
                        MusicInterferenceMath
                            .programBandHz
                )
        let lowLevel =
            MusicInterferenceMath
                .bandLevelDBFS(
                    bins: bins,
                    range:
                        MusicInterferenceMath
                            .lowBandHz
                )
        let occupied =
            MusicInterferenceMath
                .occupiedBinRatio(
                    bins: bins,
                    range:
                        MusicInterferenceMath
                            .programBandHz
                )
        let flatness =
            MusicInterferenceMath
                .spectralFlatness(
                    bins: bins,
                    range:
                        MusicInterferenceMath
                            .programBandHz
                )
        let flux =
            MusicInterferenceMath
                .spectralFlux(
                    current: bins,
                    previous:
                        previousSpectrum,
                    range:
                        MusicInterferenceMath
                            .programBandHz
                )
        let score =
            MusicInterferenceMath
                .score(
                    programLevelDBFS:
                        programLevel,
                    lowLevelDBFS:
                        lowLevel,
                    occupiedBinRatio:
                        occupied,
                    spectralFlatness:
                        flatness,
                    spectralFlux:
                        flux
                )

        if updateCount == 0 {
            smoothedScore = score
        } else {
            smoothedScore =
                smoothingAlpha * score +
                (1.0 - smoothingAlpha) *
                smoothedScore
        }

        previousSpectrum = bins
        updateCount &+= 1

        return MusicInterferenceSnapshot(
            level:
                MusicInterferenceMath
                    .level(
                        for: smoothedScore
                    ),
            instantaneousScore: score,
            smoothedScore:
                smoothedScore,
            programBandLevelDBFS:
                programLevel,
            lowBandLevelDBFS:
                lowLevel,
            programToLowRatioDB:
                programLevel -
                lowLevel,
            occupiedBinRatio:
                occupied,
            spectralFlatness:
                flatness,
            spectralFlux:
                flux,
            analyzedBinCount:
                bins.filter {
                    MusicInterferenceMath
                        .programBandHz
                        .contains(
                            $0.frequencyHz
                        )
                }.count,
            updateCount:
                updateCount
        )
    }
}
