import Foundation
import Observation

struct AmplitudeSearchResult: Equatable, Sendable, Identifiable {
    let outputPercent: Double
    let phaseDegrees: Double
    let treatment: TargetEnergyWindowSummary
    let comparison: BeforeAfterComparison

    var id: Double { outputPercent }
}

struct AmplitudeSearchStageResult: Equatable, Sendable {
    let stage: Int
    let levelsPercent: [Double]
    let results: [AmplitudeSearchResult]

    var bestResult: AmplitudeSearchResult? {
        AmplitudeSearchMath.bestResult(from: results)
    }
}

enum AmplitudeSearchMath {
    static let minimumSearchPercent = 2.0
    static let coarseStepPercent = 10.0
    static let fineRadiusPercent = 10.0
    static let fineStepPercent = 2.0

    static func coarseLevels(
        ceilingPercent: Double
    ) -> [Double] {
        let ceiling =
            ToneGeneratorMath.sanitizedOutputPercent(
                ceilingPercent
            )

        guard ceiling >= minimumSearchPercent else {
            return []
        }

        var levels: [Double] = []
        var value = min(
            coarseStepPercent,
            ceiling
        )

        while value <= ceiling + 0.0001 {
            levels.append(value)
            value += coarseStepPercent
        }

        if
            let last = levels.last,
            abs(last - ceiling) > 0.0001
        {
            levels.append(ceiling)
        } else if levels.isEmpty {
            levels.append(ceiling)
        }

        return normalizedUniqueLevels(
            levels,
            ceilingPercent: ceiling
        )
    }

    static func fineLevels(
        centeredAt centerPercent: Double,
        ceilingPercent: Double
    ) -> [Double] {
        let ceiling =
            ToneGeneratorMath.sanitizedOutputPercent(
                ceilingPercent
            )

        guard ceiling >= minimumSearchPercent else {
            return []
        }

        let center = min(
            ceiling,
            max(
                minimumSearchPercent,
                centerPercent
            )
        )
        let lower = max(
            minimumSearchPercent,
            center - fineRadiusPercent
        )
        let upper = min(
            ceiling,
            center + fineRadiusPercent
        )

        var levels: [Double] = []
        var value = lower

        while value <= upper + 0.0001 {
            levels.append(value)
            value += fineStepPercent
        }

        if
            let last = levels.last,
            abs(last - upper) > 0.0001
        {
            levels.append(upper)
        }

        return normalizedUniqueLevels(
            levels,
            ceilingPercent: ceiling
        )
    }

    static func normalizedUniqueLevels(
        _ levels: [Double],
        ceilingPercent: Double
    ) -> [Double] {
        let ceiling =
            ToneGeneratorMath.sanitizedOutputPercent(
                ceilingPercent
            )
        var seen: Set<Int> = []
        var result: [Double] = []

        for level in levels {
            let clamped = min(
                ceiling,
                max(
                    minimumSearchPercent,
                    level
                )
            )
            let rounded =
                (clamped * 1_000).rounded() /
                1_000
            let key = Int(
                (rounded * 1_000).rounded()
            )

            if seen.insert(key).inserted {
                result.append(rounded)
            }
        }

        return result.sorted()
    }

    static func bestResult(
        from results: [AmplitudeSearchResult]
    ) -> AmplitudeSearchResult? {
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

            return $0.outputPercent < $1.outputPercent
        }
    }

    static func bestResult(
        from stages: [AmplitudeSearchStageResult]
    ) -> AmplitudeSearchResult? {
        bestResult(
            from: stages.flatMap(\.results)
        )
    }
}

@MainActor
@Observable
final class AmplitudeSearchModel {
    enum State: Equatable {
        case idle
        case coarse
        case fine
        case completed
        case failed(String)

        var isRunning: Bool {
            switch self {
            case .coarse, .fine:
                true
            case .idle, .completed, .failed:
                false
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var stages: [AmplitudeSearchStageResult] = []
    private(set) var searchCeilingPercent: Double = 0
    private(set) var fixedPhaseDegrees: Double = 0

    private var generation: UInt64 = 0

    var bestResult: AmplitudeSearchResult? {
        AmplitudeSearchMath.bestResult(
            from: stages
        )
    }

    func reset() {
        generation += 1
        stages = []
        searchCeilingPercent = 0
        fixedPhaseDegrees = 0
        state = .idle
    }

    func cancel() {
        generation += 1
        state = .idle
    }

    func run(
        refinedPhaseDegrees: Double,
        ceilingPercent: Double,
        baseline: TargetEnergyWindowSummary,
        applyOutputPercent:
            @escaping @MainActor (Double) -> Void,
        measurementProvider:
            @escaping @MainActor
            () -> SequencedTargetEnergyMeasurement?,
        onComparison:
            @escaping @MainActor
            (BeforeAfterComparison) -> Void,
        onProgress:
            @escaping @MainActor
            (
                _ stage: Int,
                _ outputPercent: Double,
                _ index: Int,
                _ total: Int,
                _ collected: Int?,
                _ required: Int?
            ) -> Void
    ) async {
        guard !state.isRunning else { return }

        let ceiling =
            ToneGeneratorMath.sanitizedOutputPercent(
                ceilingPercent
            )
        let phase =
            ToneGeneratorMath.normalizedPhaseDegrees(
                refinedPhaseDegrees
            )

        guard
            ceiling >=
                AmplitudeSearchMath.minimumSearchPercent
        else {
            state = .failed(
                "Set the output ceiling to at least 2% before searching."
            )
            return
        }

        generation += 1
        let currentGeneration = generation

        stages = []
        searchCeilingPercent = ceiling
        fixedPhaseDegrees = phase

        let coarseLevels =
            AmplitudeSearchMath.coarseLevels(
                ceilingPercent: ceiling
            )

        state = .coarse

        guard
            let coarse = await runStage(
                stage: 1,
                levelsPercent: coarseLevels,
                phaseDegrees: phase,
                baseline: baseline,
                generation: currentGeneration,
                applyOutputPercent:
                    applyOutputPercent,
                measurementProvider:
                    measurementProvider,
                onComparison: onComparison,
                onProgress: onProgress
            )
        else {
            if
                currentGeneration == generation,
                state.isRunning
            {
                state = .failed(
                    "Coarse amplitude search could not complete."
                )
            }
            return
        }

        guard currentGeneration == generation else {
            return
        }

        stages.append(coarse)

        guard let coarseBest = coarse.bestResult else {
            state = .failed(
                "Coarse amplitude search produced no usable result."
            )
            return
        }

        let fineLevels =
            AmplitudeSearchMath.fineLevels(
                centeredAt: coarseBest.outputPercent,
                ceilingPercent: ceiling
            )

        state = .fine

        guard
            let fine = await runStage(
                stage: 2,
                levelsPercent: fineLevels,
                phaseDegrees: phase,
                baseline: baseline,
                generation: currentGeneration,
                applyOutputPercent:
                    applyOutputPercent,
                measurementProvider:
                    measurementProvider,
                onComparison: onComparison,
                onProgress: onProgress
            )
        else {
            if
                currentGeneration == generation,
                state.isRunning
            {
                state = .failed(
                    "Fine amplitude search could not complete."
                )
            }
            return
        }

        guard currentGeneration == generation else {
            return
        }

        stages.append(fine)
        state = .completed
    }

    private func runStage(
        stage: Int,
        levelsPercent: [Double],
        phaseDegrees: Double,
        baseline: TargetEnergyWindowSummary,
        generation currentGeneration: UInt64,
        applyOutputPercent:
            @escaping @MainActor (Double) -> Void,
        measurementProvider:
            @escaping @MainActor
            () -> SequencedTargetEnergyMeasurement?,
        onComparison:
            @escaping @MainActor
            (BeforeAfterComparison) -> Void,
        onProgress:
            @escaping @MainActor
            (
                _ stage: Int,
                _ outputPercent: Double,
                _ index: Int,
                _ total: Int,
                _ collected: Int?,
                _ required: Int?
            ) -> Void
    ) async -> AmplitudeSearchStageResult? {
        guard !levelsPercent.isEmpty else {
            return nil
        }

        var stageResults: [AmplitudeSearchResult] = []

        for (offset, outputPercent)
            in levelsPercent.enumerated()
        {
            guard
                currentGeneration == generation,
                !Task.isCancelled
            else {
                return nil
            }

            let index = offset + 1

            onProgress(
                stage,
                outputPercent,
                index,
                levelsPercent.count,
                nil,
                nil
            )

            applyOutputPercent(outputPercent)
            var sampleGate =
                FreshTargetEnergySampleGate(
                    watermark:
                        measurementProvider()?
                            .sequence ?? 0
                )

            try? await Task.sleep(
                nanoseconds: UInt64(
                    PhaseSweepModel
                        .phaseSettleDurationSeconds *
                    1_000_000_000
                )
            )

            guard
                currentGeneration == generation,
                !Task.isCancelled
            else {
                return nil
            }

            var measurements:
                [TargetFrequencyEnergyMeasurement] = []
            measurements.reserveCapacity(
                PhaseSweepModel.requiredSamples
            )

            let measurementStartedAt =
                ProcessInfo.processInfo
                    .systemUptime
            var attempts = 0

            while
                measurements.count <
                    PhaseSweepModel.requiredSamples,
                attempts <
                    PhaseSweepModel
                        .maximumAttemptsPerPhase,
                currentGeneration == generation,
                !Task.isCancelled
            {
                attempts += 1

                if
                    let sample =
                        measurementProvider(),
                    let measurement =
                        sampleGate.accept(
                            sample,
                            targetFrequencyHz:
                                baseline.condition
                                    .targetFrequencyHz
                        )
                {
                    measurements.append(
                        measurement
                    )
                }

                onProgress(
                    stage,
                    outputPercent,
                    index,
                    levelsPercent.count,
                    measurements.count,
                    PhaseSweepModel.requiredSamples
                )

                if
                    measurements.count <
                        PhaseSweepModel
                            .requiredSamples
                {
                    try? await Task.sleep(
                        nanoseconds: UInt64(
                            PhaseSweepModel
                                .sampleIntervalSeconds *
                            1_000_000_000
                        )
                    )
                }
            }

            guard
                currentGeneration == generation,
                !Task.isCancelled
            else {
                return nil
            }

            let condition = MeasurementCondition(
                targetFrequencyHz:
                    baseline.condition.targetFrequencyHz,
                phaseDegrees: phaseDegrees,
                outputPercent: outputPercent,
                toneAudible: true
            )

            guard
                let treatment =
                    BeforeAfterMeasurementMath.summarize(
                        measurements,
                        condition: condition,
                        sampleIntervalSeconds:
                            PhaseSweepModel
                                .sampleIntervalSeconds,
                        durationSeconds:
                            max(
                                0,
                                ProcessInfo.processInfo
                                    .systemUptime -
                                measurementStartedAt
                            )
                    ),
                treatment.sampleCount ==
                    PhaseSweepModel.requiredSamples,
                let comparison =
                    BeforeAfterMeasurementMath.compare(
                        baseline: baseline,
                        treatment: treatment
                    )
            else {
                return nil
            }

            let result = AmplitudeSearchResult(
                outputPercent: outputPercent,
                phaseDegrees: phaseDegrees,
                treatment: treatment,
                comparison: comparison
            )

            stageResults.append(result)
            onComparison(comparison)
        }

        return AmplitudeSearchStageResult(
            stage: stage,
            levelsPercent: levelsPercent,
            results: stageResults
        )
    }
}
