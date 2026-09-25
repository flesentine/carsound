import Foundation

struct DominantFrequency: Equatable, Sendable, Identifiable {
    let frequencyHz: Double
    let magnitudeDBFS: Double
    let temporalExcessDB: Double
    let localProminenceDB: Double
    let scoreDB: Double

    var id: String {
        String(format: "%.3f", frequencyHz)
    }
}

struct DominantFrequencySnapshot: Equatable, Sendable {
    let frequencies: [DominantFrequency]
    let analyzedBinCount: Int

    static let empty = DominantFrequencySnapshot(
        frequencies: [],
        analyzedBinCount: 0
    )
}

final class DominantFrequencyDetector {
    static let minimumFrequencyHz = 20.0
    static let maximumFrequencyHz = 200.0

    private let maximumResults: Int
    private let minimumSeparationHz: Double
    private let minimumLocalProminenceDB: Double
    private let minimumScoreDB: Double

    init(
        maximumResults: Int = 5,
        minimumSeparationHz: Double = 18.0,
        minimumLocalProminenceDB: Double = 2.5,
        minimumScoreDB: Double = 3.0
    ) {
        precondition(maximumResults > 0)
        precondition(minimumSeparationHz >= 0)
        precondition(minimumLocalProminenceDB >= 0)
        precondition(minimumScoreDB >= 0)

        self.maximumResults = maximumResults
        self.minimumSeparationHz = minimumSeparationHz
        self.minimumLocalProminenceDB = minimumLocalProminenceDB
        self.minimumScoreDB = minimumScoreDB
    }

    func detect(
        spectrum: [SpectrumBin],
        noiseFloor: [SpectrumBin]
    ) -> DominantFrequencySnapshot {
        let analysisBins = spectrum.filter {
            $0.frequencyHz >= Self.minimumFrequencyHz &&
            $0.frequencyHz <= Self.maximumFrequencyHz
        }

        guard analysisBins.count >= 3 else {
            return DominantFrequencySnapshot(
                frequencies: [],
                analyzedBinCount: analysisBins.count
            )
        }

        let floorByFrequency = Dictionary(
            uniqueKeysWithValues: noiseFloor.map {
                (frequencyKey($0.frequencyHz), $0.magnitudeDBFS)
            }
        )

        var candidates: [DominantFrequency] = []
        candidates.reserveCapacity(analysisBins.count / 2)

        for index in 1..<(analysisBins.count - 1) {
            let previous = analysisBins[index - 1]
            let current = analysisBins[index]
            let next = analysisBins[index + 1]

            guard
                current.magnitudeDBFS > previous.magnitudeDBFS,
                current.magnitudeDBFS >= next.magnitudeDBFS
            else {
                continue
            }

            let localFloorDB = localBaselineDB(
                bins: analysisBins,
                peakIndex: index
            )
            let localProminence = max(
                0,
                current.magnitudeDBFS - localFloorDB
            )

            let temporalFloorDB = floorByFrequency[
                frequencyKey(current.frequencyHz)
            ] ?? localFloorDB
            let temporalExcess = max(
                0,
                current.magnitudeDBFS - temporalFloorDB
            )

            // Local prominence is required so a broad elevated band is not
            // reported as a narrow dominant tone. Temporal excess increases
            // the ranking when a peak rises above the tracked background.
            guard localProminence >= minimumLocalProminenceDB else {
                continue
            }

            let score =
                localProminence +
                0.5 * temporalExcess

            guard score >= minimumScoreDB else {
                continue
            }

            candidates.append(
                DominantFrequency(
                    frequencyHz: interpolatedFrequency(
                        bins: analysisBins,
                        peakIndex: index
                    ),
                    magnitudeDBFS: current.magnitudeDBFS,
                    temporalExcessDB: temporalExcess,
                    localProminenceDB: localProminence,
                    scoreDB: score
                )
            )
        }

        let ranked = candidates.sorted {
            if abs($0.scoreDB - $1.scoreDB) > 0.0001 {
                return $0.scoreDB > $1.scoreDB
            }

            return $0.magnitudeDBFS > $1.magnitudeDBFS
        }

        var selected: [DominantFrequency] = []
        selected.reserveCapacity(min(maximumResults, ranked.count))

        for candidate in ranked {
            let tooClose = selected.contains {
                abs($0.frequencyHz - candidate.frequencyHz) <
                    minimumSeparationHz
            }

            guard !tooClose else { continue }

            selected.append(candidate)

            if selected.count == maximumResults {
                break
            }
        }

        return DominantFrequencySnapshot(
            frequencies: selected,
            analyzedBinCount: analysisBins.count
        )
    }

    private func localBaselineDB(
        bins: [SpectrumBin],
        peakIndex: Int
    ) -> Double {
        let radius = 3
        let excludedRadius = 1
        let lower = max(0, peakIndex - radius)
        let upper = min(bins.count - 1, peakIndex + radius)

        let neighbors = (lower...upper)
            .filter {
                abs($0 - peakIndex) > excludedRadius
            }
            .map {
                bins[$0].magnitudeDBFS
            }
            .sorted()

        guard !neighbors.isEmpty else {
            return min(
                bins[peakIndex - 1].magnitudeDBFS,
                bins[peakIndex + 1].magnitudeDBFS
            )
        }

        let middle = neighbors.count / 2

        if neighbors.count.isMultiple(of: 2) {
            return (neighbors[middle - 1] + neighbors[middle]) / 2
        }

        return neighbors[middle]
    }

    private func interpolatedFrequency(
        bins: [SpectrumBin],
        peakIndex: Int
    ) -> Double {
        let left = bins[peakIndex - 1]
        let center = bins[peakIndex]
        let right = bins[peakIndex + 1]
        let denominator =
            left.magnitudeDBFS -
            2.0 * center.magnitudeDBFS +
            right.magnitudeDBFS

        guard abs(denominator) > 0.000001 else {
            return center.frequencyHz
        }

        let offset = 0.5 *
            (left.magnitudeDBFS - right.magnitudeDBFS) /
            denominator
        let clampedOffset = min(0.5, max(-0.5, offset))
        let binWidth = (
            right.frequencyHz -
            left.frequencyHz
        ) / 2.0

        return center.frequencyHz + clampedOffset * binWidth
    }

    private func frequencyKey(_ frequencyHz: Double) -> Int64 {
        Int64((frequencyHz * 1_000).rounded())
    }
}
