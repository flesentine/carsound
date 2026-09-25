import Foundation

struct NoiseFloorSnapshot: Equatable, Sendable {
    let bins: [SpectrumBin]
    let lowFrequencyFloorDBFS: Double
    let widebandFloorDBFS: Double
    let lowFrequencyExcessDB: Double
    let widebandExcessDB: Double
    let updateCount: UInt64

    static let empty = NoiseFloorSnapshot(
        bins: [],
        lowFrequencyFloorDBFS: FFTAnalyzer.magnitudeFloorDBFS,
        widebandFloorDBFS: FFTAnalyzer.magnitudeFloorDBFS,
        lowFrequencyExcessDB: 0,
        widebandExcessDB: 0,
        updateCount: 0
    )
}

final class NoiseFloorEstimator {
    static let minimumFrequencyHz = 20.0
    static let lowFrequencyMaximumHz = 200.0
    static let maximumFrequencyHz = 2_000.0

    // New quieter observations pull the floor down quickly.
    // Louder observations move the floor upward slowly so transient
    // sounds do not instantly become the new background baseline.
    private let downwardAlpha: Double
    private let upwardAlpha: Double

    private var floorPower: [Double] = []
    private var frequencies: [Double] = []
    private(set) var updateCount: UInt64 = 0

    init(
        downwardAlpha: Double = 0.30,
        upwardAlpha: Double = 0.01
    ) {
        precondition(downwardAlpha > 0 && downwardAlpha <= 1)
        precondition(upwardAlpha > 0 && upwardAlpha <= 1)
        precondition(downwardAlpha >= upwardAlpha)

        self.downwardAlpha = downwardAlpha
        self.upwardAlpha = upwardAlpha
    }

    func reset() {
        floorPower.removeAll(keepingCapacity: true)
        frequencies.removeAll(keepingCapacity: true)
        updateCount = 0
    }

    func process(_ bins: [SpectrumBin]) -> NoiseFloorSnapshot {
        let analysisBins = bins.filter {
            $0.frequencyHz >= Self.minimumFrequencyHz &&
            $0.frequencyHz <= Self.maximumFrequencyHz
        }

        guard !analysisBins.isEmpty else {
            reset()
            return .empty
        }

        if shouldReset(for: analysisBins) {
            frequencies = analysisBins.map(\.frequencyHz)
            floorPower = analysisBins.map {
                Self.power(fromDBFS: $0.magnitudeDBFS)
            }
            updateCount = 1
            return snapshot(currentBins: analysisBins)
        }

        for index in analysisBins.indices {
            let currentPower = Self.power(
                fromDBFS: analysisBins[index].magnitudeDBFS
            )
            let alpha = currentPower < floorPower[index]
                ? downwardAlpha
                : upwardAlpha

            floorPower[index] =
                alpha * currentPower +
                (1.0 - alpha) * floorPower[index]
        }

        updateCount += 1
        return snapshot(currentBins: analysisBins)
    }

    private func snapshot(
        currentBins: [SpectrumBin]
    ) -> NoiseFloorSnapshot {
        let floorBins = zip(frequencies, floorPower).map {
            SpectrumBin(
                frequencyHz: $0.0,
                magnitudeDBFS: Self.dbFS(fromPower: $0.1)
            )
        }

        let lowIndices = currentBins.indices.filter {
            currentBins[$0].frequencyHz <= Self.lowFrequencyMaximumHz
        }
        let wideIndices = Array(currentBins.indices)

        let lowFloor = medianDBFS(
            indices: lowIndices,
            powers: floorPower
        )
        let wideFloor = medianDBFS(
            indices: wideIndices,
            powers: floorPower
        )
        let lowCurrent = medianDBFS(
            indices: lowIndices,
            powers: currentBins.map {
                Self.power(fromDBFS: $0.magnitudeDBFS)
            }
        )
        let wideCurrent = medianDBFS(
            indices: wideIndices,
            powers: currentBins.map {
                Self.power(fromDBFS: $0.magnitudeDBFS)
            }
        )

        return NoiseFloorSnapshot(
            bins: floorBins,
            lowFrequencyFloorDBFS: lowFloor,
            widebandFloorDBFS: wideFloor,
            lowFrequencyExcessDB: max(0, lowCurrent - lowFloor),
            widebandExcessDB: max(0, wideCurrent - wideFloor),
            updateCount: updateCount
        )
    }

    private func shouldReset(
        for bins: [SpectrumBin]
    ) -> Bool {
        guard
            bins.count == floorPower.count,
            bins.count == frequencies.count,
            let first = bins.first,
            let last = bins.last
        else {
            return true
        }

        return abs(first.frequencyHz - frequencies[0]) > 0.0001 ||
            abs(last.frequencyHz - frequencies[frequencies.count - 1]) > 0.0001
    }

    private func medianDBFS(
        indices: [Int],
        powers: [Double]
    ) -> Double {
        guard !indices.isEmpty else {
            return FFTAnalyzer.magnitudeFloorDBFS
        }

        let sorted = indices
            .map { powers[$0] }
            .sorted()

        let middle = sorted.count / 2
        let medianPower: Double

        if sorted.count.isMultiple(of: 2) {
            medianPower = (sorted[middle - 1] + sorted[middle]) / 2
        } else {
            medianPower = sorted[middle]
        }

        return Self.dbFS(fromPower: medianPower)
    }

    private static func power(
        fromDBFS dbFS: Double
    ) -> Double {
        pow(10.0, dbFS / 10.0)
    }

    private static func dbFS(
        fromPower power: Double
    ) -> Double {
        guard power > 0 else {
            return FFTAnalyzer.magnitudeFloorDBFS
        }

        return max(
            FFTAnalyzer.magnitudeFloorDBFS,
            10.0 * log10(power)
        )
    }
}
