import Foundation
import Observation

struct PhaseSweepResult: Equatable, Sendable, Identifiable {
    let phaseDegrees: Double
    let treatment: TargetEnergyWindowSummary
    let comparison: BeforeAfterComparison

    var id: Double { phaseDegrees }
}

enum PhaseSweepMath {
    static let defaultPhases: [Double] = [
        0, 45, 90, 135, 180, 225, 270, 315
    ]

    static func normalizedUniquePhases(
        _ phases: [Double]
    ) -> [Double] {
        var seen: Set<Int> = []
        var result: [Double] = []

        for phase in phases {
            let normalized =
                ToneGeneratorMath.normalizedPhaseDegrees(
                    phase
                )
            let key = Int(
                (normalized * 1_000).rounded()
            )

            if seen.insert(key).inserted {
                result.append(normalized)
            }
        }

        return result
    }

    static func bestResult(
        from results: [PhaseSweepResult]
    ) -> PhaseSweepResult? {
        results.min {
            if abs(
                $0.treatment.averageBandEnergyDBFS -
                $1.treatment.averageBandEnergyDBFS
            ) > 0.0001 {
                return
                    $0.treatment.averageBandEnergyDBFS <
                    $1.treatment.averageBandEnergyDBFS
            }

            if abs(
                $0.treatment.standardDeviationDB -
                $1.treatment.standardDeviationDB
            ) > 0.0001 {
                return
                    $0.treatment.standardDeviationDB <
                    $1.treatment.standardDeviationDB
            }

            return $0.phaseDegrees < $1.phaseDegrees
        }
    }
}

@MainActor
@Observable
final class PhaseSweepModel {
    enum State: Equatable {
        case idle
        case settling(
            phaseDegrees: Double,
            index: Int,
            total: Int
        )
        case capturing(
            phaseDegrees: Double,
            index: Int,
            total: Int,
            collected: Int,
            required: Int
        )
        case completed
        case failed(String)

        var isRunning: Bool {
            switch self {
            case .settling, .capturing:
                true
            case .idle, .completed, .failed:
                false
            }
        }
    }

    static let requiredSamples = 20
    static let sampleIntervalSeconds = 0.10
    static let phaseSettleDurationSeconds = 0.35
    static let maximumAttemptsPerPhase = 50

    private(set) var state: State = .idle
    private(set) var results: [PhaseSweepResult] = []

    private var sweepGeneration: UInt64 = 0

    var bestResult: PhaseSweepResult? {
        PhaseSweepMath.bestResult(
            from: results
        )
    }

    func reset() {
        sweepGeneration += 1
        results = []
        state = .idle
    }

    func cancel() {
        sweepGeneration += 1
        state = .idle
    }

    func run(
        baseline: TargetEnergyWindowSummary,
        outputPercent: Double,
        phases: [Double] = PhaseSweepMath.defaultPhases,
        applyPhase:
            @escaping @MainActor (Double) -> Void,
        measurementProvider:
            @escaping @MainActor
            () -> SequencedTargetEnergyMeasurement?,
        onComparison:
            @escaping @MainActor
            (BeforeAfterComparison) -> Void
    ) async {
        guard !state.isRunning else { return }

        let sweepPhases =
            PhaseSweepMath.normalizedUniquePhases(
                phases
            )

        guard !sweepPhases.isEmpty else {
            state = .failed(
                "No phase values were available for the sweep."
            )
            return
        }

        sweepGeneration += 1
        let generation = sweepGeneration
        results = []

        for (offset, phase) in sweepPhases.enumerated() {
            guard generation == sweepGeneration else {
                return
            }

            let index = offset + 1
            state = .settling(
                phaseDegrees: phase,
                index: index,
                total: sweepPhases.count
            )

            applyPhase(phase)
            var lastMeasurementSequence =
                measurementProvider()?.sequence ??
                0

            try? await Task.sleep(
                nanoseconds: UInt64(
                    Self.phaseSettleDurationSeconds *
                    1_000_000_000
                )
            )

            guard
                !Task.isCancelled,
                generation == sweepGeneration
            else {
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
                attempts < Self.maximumAttemptsPerPhase,
                !Task.isCancelled,
                generation == sweepGeneration
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
                        baseline.condition.targetFrequencyHz
                    ) <= 0.5
                {
                    lastMeasurementSequence =
                        sample.sequence
                    measurements.append(
                        sample.measurement
                    )
                }

                state = .capturing(
                    phaseDegrees: phase,
                    index: index,
                    total: sweepPhases.count,
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
                generation == sweepGeneration
            else {
                return
            }

            let condition = MeasurementCondition(
                targetFrequencyHz:
                    baseline.condition.targetFrequencyHz,
                phaseDegrees: phase,
                outputPercent: outputPercent,
                toneAudible: true
            )

            guard
                let treatment =
                    BeforeAfterMeasurementMath.summarize(
                        measurements,
                        condition: condition,
                        sampleIntervalSeconds:
                            Self.sampleIntervalSeconds
                    ),
                treatment.sampleCount ==
                    Self.requiredSamples,
                let comparison =
                    BeforeAfterMeasurementMath.compare(
                        baseline: baseline,
                        treatment: treatment
                    )
            else {
                state = .failed(
                    String(
                        format:
                            "Not enough stable samples at %.0f°.",
                        phase
                    )
                )
                return
            }

            let result = PhaseSweepResult(
                phaseDegrees: phase,
                treatment: treatment,
                comparison: comparison
            )

            results.append(result)
            onComparison(comparison)
        }

        guard generation == sweepGeneration else {
            return
        }

        state = .completed
    }
}
