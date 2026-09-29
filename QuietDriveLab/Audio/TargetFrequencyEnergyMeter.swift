import Foundation

struct TargetFrequencyEnergyMeasurement: Equatable, Sendable {
    let targetFrequencyHz: Double
    let nearestBinFrequencyHz: Double
    let centerLevelDBFS: Double
    let bandEnergyDBFS: Double
    let floorBandEnergyDBFS: Double?
    let excessDB: Double?
    let lowerFrequencyHz: Double
    let upperFrequencyHz: Double
    let binCount: Int
    let frequencyResolutionHz: Double
}

enum TargetFrequencyEnergyMeter {
    static let minimumHalfWidthHz = 8.0
    static let resolutionMultiplier = 1.5

    static func measure(
        spectrum: [SpectrumBin],
        noiseFloor: [SpectrumBin],
        targetFrequencyHz: Double,
        frequencyResolutionHz: Double
    ) -> TargetFrequencyEnergyMeasurement? {
        guard
            !spectrum.isEmpty,
            targetFrequencyHz.isFinite,
            frequencyResolutionHz > 0
        else {
            return nil
        }

        let halfWidth = max(
            minimumHalfWidthHz,
            frequencyResolutionHz * resolutionMultiplier
        )
        let lower = targetFrequencyHz - halfWidth
        let upper = targetFrequencyHz + halfWidth

        let bandBins = spectrum.filter {
            $0.frequencyHz >= lower &&
            $0.frequencyHz <= upper
        }

        guard
            !bandBins.isEmpty,
            let nearest = spectrum.min(by: {
                abs($0.frequencyHz - targetFrequencyHz) <
                abs($1.frequencyHz - targetFrequencyHz)
            })
        else {
            return nil
        }

        let bandEnergy = bandEnergyDBFS(bandBins)

        let floorByFrequency = Dictionary(
            uniqueKeysWithValues: noiseFloor.map {
                (frequencyKey($0.frequencyHz), $0)
            }
        )

        let floorBins = bandBins.compactMap {
            floorByFrequency[frequencyKey($0.frequencyHz)]
        }

        let floorEnergy: Double?
        let excess: Double?

        if floorBins.count == bandBins.count {
            let value = bandEnergyDBFS(floorBins)
            floorEnergy = value
            excess = max(0, bandEnergy - value)
        } else {
            floorEnergy = nil
            excess = nil
        }

        return TargetFrequencyEnergyMeasurement(
            targetFrequencyHz: targetFrequencyHz,
            nearestBinFrequencyHz: nearest.frequencyHz,
            centerLevelDBFS: interpolatedPowerDBFS(
                bins: spectrum,
                targetFrequencyHz: targetFrequencyHz
            ) ?? nearest.magnitudeDBFS,
            bandEnergyDBFS: bandEnergy,
            floorBandEnergyDBFS: floorEnergy,
            excessDB: excess,
            lowerFrequencyHz: bandBins.first?.frequencyHz ?? lower,
            upperFrequencyHz: bandBins.last?.frequencyHz ?? upper,
            binCount: bandBins.count,
            frequencyResolutionHz: frequencyResolutionHz
        )
    }

    static func bandEnergyDBFS(
        _ bins: [SpectrumBin]
    ) -> Double {
        guard !bins.isEmpty else {
            return FFTAnalyzer.magnitudeFloorDBFS
        }

        let power = bins.reduce(0.0) {
            $0 + linearPower(fromDBFS: $1.magnitudeDBFS)
        }

        return dbFS(fromLinearPower: power)
    }

    static func interpolatedPowerDBFS(
        bins: [SpectrumBin],
        targetFrequencyHz: Double
    ) -> Double? {
        guard !bins.isEmpty else { return nil }

        if let exact = bins.first(where: {
            abs($0.frequencyHz - targetFrequencyHz) < 0.0001
        }) {
            return exact.magnitudeDBFS
        }

        guard
            let upperIndex = bins.firstIndex(where: {
                $0.frequencyHz > targetFrequencyHz
            }),
            upperIndex > 0
        else {
            return bins.min(by: {
                abs($0.frequencyHz - targetFrequencyHz) <
                abs($1.frequencyHz - targetFrequencyHz)
            })?.magnitudeDBFS
        }

        let lowerBin = bins[upperIndex - 1]
        let upperBin = bins[upperIndex]
        let span =
            upperBin.frequencyHz -
            lowerBin.frequencyHz

        guard span > 0 else {
            return lowerBin.magnitudeDBFS
        }

        let fraction =
            (targetFrequencyHz - lowerBin.frequencyHz) /
            span

        let lowerPower =
            linearPower(fromDBFS: lowerBin.magnitudeDBFS)
        let upperPower =
            linearPower(fromDBFS: upperBin.magnitudeDBFS)
        let interpolatedPower =
            lowerPower +
            (upperPower - lowerPower) *
            fraction

        return dbFS(fromLinearPower: interpolatedPower)
    }

    private static func linearPower(
        fromDBFS dbFS: Double
    ) -> Double {
        pow(10.0, dbFS / 10.0)
    }

    private static func dbFS(
        fromLinearPower power: Double
    ) -> Double {
        guard power > 0 else {
            return FFTAnalyzer.magnitudeFloorDBFS
        }

        return max(
            FFTAnalyzer.magnitudeFloorDBFS,
            10.0 * log10(power)
        )
    }

    private static func frequencyKey(
        _ frequencyHz: Double
    ) -> Int64 {
        Int64((frequencyHz * 1_000).rounded())
    }
}
