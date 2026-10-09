import Foundation
import Observation

struct MeasurementCondition: Equatable, Sendable {
    let targetFrequencyHz: Double
    let phaseDegrees: Double
    let outputPercent: Double
    let toneAudible: Bool
}

struct TargetEnergyWindowSummary: Equatable, Sendable {
    let condition: MeasurementCondition
    let sampleCount: Int
    let durationSeconds: Double
    let averageBandEnergyDBFS: Double
    let minimumBandEnergyDBFS: Double
    let maximumBandEnergyDBFS: Double
    let averageCenterLevelDBFS: Double
    let standardDeviationDB: Double
}

struct BeforeAfterComparison: Equatable, Sendable {
    let baseline: TargetEnergyWindowSummary
    let treatment: TargetEnergyWindowSummary
    let treatmentMinusBaselineDB: Double
    let measuredReductionDB: Double

    var improved: Bool {
        measuredReductionDB > 0
    }
}

enum BeforeAfterMeasurementMath {
    static func summarize(
        _ measurements: [TargetFrequencyEnergyMeasurement],
        condition: MeasurementCondition,
        sampleIntervalSeconds: Double
    ) -> TargetEnergyWindowSummary? {
        guard
            !measurements.isEmpty,
            sampleIntervalSeconds > 0,
            measurements.allSatisfy({
                abs(
                    $0.targetFrequencyHz -
                    condition.targetFrequencyHz
                ) <= 0.5
            })
        else {
            return nil
        }

        let bandLevels = measurements.map(\.bandEnergyDBFS)
        let centerLevels = measurements.map(\.centerLevelDBFS)

        let averageBand =
            averageDBFromPower(levelsDB: bandLevels)
        let averageCenter =
            averageDBFromPower(levelsDB: centerLevels)

        let variance =
            bandLevels.reduce(0.0) { partial, level in
                let delta = level - averageBand
                return partial + delta * delta
            } /
            Double(bandLevels.count)

        return TargetEnergyWindowSummary(
            condition: condition,
            sampleCount: measurements.count,
            durationSeconds:
                Double(max(0, measurements.count - 1)) *
                sampleIntervalSeconds,
            averageBandEnergyDBFS: averageBand,
            minimumBandEnergyDBFS:
                bandLevels.min() ??
                FFTAnalyzer.magnitudeFloorDBFS,
            maximumBandEnergyDBFS:
                bandLevels.max() ??
                FFTAnalyzer.magnitudeFloorDBFS,
            averageCenterLevelDBFS: averageCenter,
            standardDeviationDB: sqrt(max(0, variance))
        )
    }

    static func compare(
        baseline: TargetEnergyWindowSummary,
        treatment: TargetEnergyWindowSummary
    ) -> BeforeAfterComparison? {
        guard
            abs(
                baseline.condition.targetFrequencyHz -
                treatment.condition.targetFrequencyHz
            ) <= 0.5
        else {
            return nil
        }

        let delta =
            treatment.averageBandEnergyDBFS -
            baseline.averageBandEnergyDBFS

        return BeforeAfterComparison(
            baseline: baseline,
            treatment: treatment,
            treatmentMinusBaselineDB: delta,
            measuredReductionDB: -delta
        )
    }

    static func averageDBFromPower(
        levelsDB: [Double]
    ) -> Double {
        guard !levelsDB.isEmpty else {
            return FFTAnalyzer.magnitudeFloorDBFS
        }

        let averagePower =
            levelsDB
                .map { pow(10.0, $0 / 10.0) }
                .reduce(0, +) /
                Double(levelsDB.count)

        guard averagePower > 0 else {
            return FFTAnalyzer.magnitudeFloorDBFS
        }

        return max(
            FFTAnalyzer.magnitudeFloorDBFS,
            10.0 * log10(averagePower)
        )
    }
}

@MainActor
@Observable
final class BeforeAfterMeasurementModel {
    enum Window: String, Equatable {
        case baseline = "Baseline"
        case treatment = "Treatment"
    }

    enum State: Equatable {
        case idle
        case settling(Window)
        case capturing(
            Window,
            collected: Int,
            required: Int
        )
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .settling, .capturing:
                true
            case .idle, .failed:
                false
            }
        }
    }

    static let requiredSamples = 20
    static let sampleIntervalSeconds = 0.10
    static let settleDurationSeconds = 0.35
    static let maximumAttempts = 50

    private(set) var state: State = .idle
    private(set) var baseline: TargetEnergyWindowSummary?
    private(set) var treatment: TargetEnergyWindowSummary?

    private var captureGeneration: UInt64 = 0

    var comparison: BeforeAfterComparison? {
        guard let baseline, let treatment else {
            return nil
        }

        return BeforeAfterMeasurementMath.compare(
            baseline: baseline,
            treatment: treatment
        )
    }

    func reset() {
        captureGeneration += 1
        baseline = nil
        treatment = nil
        state = .idle
    }

    func cancelCapture() {
        captureGeneration += 1
        state = .idle
    }

    func capture(
        window: Window,
        condition: MeasurementCondition,
        measurementProvider:
            @escaping @MainActor
            () -> SequencedTargetEnergyMeasurement?
    ) async {
        guard !state.isBusy else { return }

        captureGeneration += 1
        let generation = captureGeneration
        var lastMeasurementSequence =
            measurementProvider()?.sequence ??
            0
        state = .settling(window)

        try? await Task.sleep(
            nanoseconds: UInt64(
                Self.settleDurationSeconds *
                1_000_000_000
            )
        )

        guard
            !Task.isCancelled,
            generation == captureGeneration
        else {
            if generation == captureGeneration {
                state = .idle
            }
            return
        }

        var measurements:
            [TargetFrequencyEnergyMeasurement] = []
        measurements.reserveCapacity(
            Self.requiredSamples
        )

        var attempts = 0

        while
            measurements.count < Self.requiredSamples,
            attempts < Self.maximumAttempts,
            !Task.isCancelled,
            generation == captureGeneration
        {
            attempts += 1

            if
                let sample =
                    measurementProvider(),
                sample.sequence >
                    lastMeasurementSequence,
                abs(
                    sample.measurement
                        .targetFrequencyHz -
                    condition.targetFrequencyHz
                ) <= 0.5
            {
                lastMeasurementSequence =
                    sample.sequence
                measurements.append(
                    sample.measurement
                )
            }

            state = .capturing(
                window,
                collected: measurements.count,
                required: Self.requiredSamples
            )

            try? await Task.sleep(
                nanoseconds: UInt64(
                    Self.sampleIntervalSeconds *
                    1_000_000_000
                )
            )
        }

        guard
            !Task.isCancelled,
            generation == captureGeneration
        else {
            if generation == captureGeneration {
                state = .idle
            }
            return
        }

        guard
            let summary = BeforeAfterMeasurementMath.summarize(
                measurements,
                condition: condition,
                sampleIntervalSeconds:
                    Self.sampleIntervalSeconds
            ),
            summary.sampleCount == Self.requiredSamples
        else {
            state = .failed(
                "Not enough stable target-energy samples were available."
            )
            return
        }

        switch window {
        case .baseline:
            baseline = summary
            treatment = nil
        case .treatment:
            guard let baseline else {
                state = .failed(
                    "Capture a baseline before treatment."
                )
                return
            }

            guard
                abs(
                    baseline.condition.targetFrequencyHz -
                    summary.condition.targetFrequencyHz
                ) <= 0.5
            else {
                state = .failed(
                    "Target frequency changed. Capture a new baseline."
                )
                return
            }

            treatment = summary
        }

        state = .idle
    }
}
