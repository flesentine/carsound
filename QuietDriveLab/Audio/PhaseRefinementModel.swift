import Foundation
import Observation

struct PhaseRefinementStageResult: Equatable, Sendable {
    let stage: Int
    let centerPhaseDegrees: Double
    let stepDegrees: Double
    let results: [PhaseSweepResult]

    var bestResult: PhaseSweepResult? {
        PhaseSweepMath.bestResult(from: results)
    }
}

enum PhaseRefinementMath {
    static let stageOneStepDegrees = 15.0
    static let stageOneRadiusDegrees = 30.0
    static let stageTwoStepDegrees = 5.0
    static let stageTwoRadiusDegrees = 10.0

    static func phases(
        centeredAt centerPhaseDegrees: Double,
        radiusDegrees: Double,
        stepDegrees: Double
    ) -> [Double] {
        guard
            radiusDegrees >= 0,
            stepDegrees > 0
        else {
            return []
        }

        let center =
            ToneGeneratorMath.normalizedPhaseDegrees(
                centerPhaseDegrees
            )
        let stepCount = Int(
            floor(radiusDegrees / stepDegrees)
        )

        let raw = (-stepCount...stepCount).map { offset in
            center + Double(offset) * stepDegrees
        }

        return PhaseSweepMath.normalizedUniquePhases(raw)
    }

    static func stageOnePhases(
        coarseCenterPhaseDegrees: Double
    ) -> [Double] {
        phases(
            centeredAt: coarseCenterPhaseDegrees,
            radiusDegrees: stageOneRadiusDegrees,
            stepDegrees: stageOneStepDegrees
        )
    }

    static func stageTwoPhases(
        fineCenterPhaseDegrees: Double
    ) -> [Double] {
        phases(
            centeredAt: fineCenterPhaseDegrees,
            radiusDegrees: stageTwoRadiusDegrees,
            stepDegrees: stageTwoStepDegrees
        )
    }

    static func bestResult(
        from stages: [PhaseRefinementStageResult]
    ) -> PhaseSweepResult? {
        PhaseSweepMath.bestResult(
            from: stages.flatMap(\.results)
        )
    }
}

@MainActor
@Observable
final class PhaseRefinementModel {
    enum State: Equatable {
        case idle
        case stageOne
        case stageTwo
        case completed
        case failed(String)

        var isRunning: Bool {
            switch self {
            case .stageOne, .stageTwo:
                true
            case .idle, .completed, .failed:
                false
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var stages: [PhaseRefinementStageResult] = []

    private var generation: UInt64 = 0

    var bestResult: PhaseSweepResult? {
        PhaseRefinementMath.bestResult(from: stages)
    }

    func reset() {
        generation += 1
        stages = []
        state = .idle
    }

    func cancel() {
        generation += 1
        state = .idle
    }

    func run(
        coarseBestPhaseDegrees: Double,
        baseline: TargetEnergyWindowSummary,
        outputPercent: Double,
        applyPhase:
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
                _ phaseDegrees: Double,
                _ index: Int,
                _ total: Int,
                _ collected: Int?,
                _ required: Int?
            ) -> Void
    ) async {
        guard !state.isRunning else { return }

        generation += 1
        let currentGeneration = generation
        stages = []

        let stageOnePhases =
            PhaseRefinementMath.stageOnePhases(
                coarseCenterPhaseDegrees:
                    coarseBestPhaseDegrees
            )

        state = .stageOne

        guard
            let stageOne = await runStage(
                stage: 1,
                centerPhaseDegrees:
                    coarseBestPhaseDegrees,
                stepDegrees:
                    PhaseRefinementMath
                        .stageOneStepDegrees,
                phases: stageOnePhases,
                baseline: baseline,
                outputPercent: outputPercent,
                generation: currentGeneration,
                applyPhase: applyPhase,
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
                    "Fine phase stage 1 could not complete."
                )
            }
            return
        }

        guard currentGeneration == generation else {
            return
        }

        stages.append(stageOne)

        guard let stageOneBest = stageOne.bestResult else {
            state = .failed(
                "Fine phase stage 1 produced no usable result."
            )
            return
        }

        let stageTwoPhases =
            PhaseRefinementMath.stageTwoPhases(
                fineCenterPhaseDegrees:
                    stageOneBest.phaseDegrees
            )

        state = .stageTwo

        guard
            let stageTwo = await runStage(
                stage: 2,
                centerPhaseDegrees:
                    stageOneBest.phaseDegrees,
                stepDegrees:
                    PhaseRefinementMath
                        .stageTwoStepDegrees,
                phases: stageTwoPhases,
                baseline: baseline,
                outputPercent: outputPercent,
                generation: currentGeneration,
                applyPhase: applyPhase,
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
                    "Fine phase stage 2 could not complete."
                )
            }
            return
        }

        guard currentGeneration == generation else {
            return
        }

        stages.append(stageTwo)
        state = .completed
    }

    private func runStage(
        stage: Int,
        centerPhaseDegrees: Double,
        stepDegrees: Double,
        phases: [Double],
        baseline: TargetEnergyWindowSummary,
        outputPercent: Double,
        generation currentGeneration: UInt64,
        applyPhase:
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
                _ phaseDegrees: Double,
                _ index: Int,
                _ total: Int,
                _ collected: Int?,
                _ required: Int?
            ) -> Void
    ) async -> PhaseRefinementStageResult? {
        guard !phases.isEmpty else { return nil }

        var stageResults: [PhaseSweepResult] = []

        for (offset, phase) in phases.enumerated() {
            guard
                currentGeneration == generation,
                !Task.isCancelled
            else {
                return nil
            }

            let index = offset + 1
            onProgress(
                stage,
                phase,
                index,
                phases.count,
                nil,
                nil
            )

            applyPhase(phase)
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
                    phase,
                    index,
                    phases.count,
                    measurements.count,
                    PhaseSweepModel.requiredSamples
                )

                try? await Task.sleep(
                    nanoseconds: UInt64(
                        PhaseSweepModel
                            .sampleIntervalSeconds *
                        1_000_000_000
                    )
                )
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
                            PhaseSweepModel
                                .sampleIntervalSeconds
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

            let result = PhaseSweepResult(
                phaseDegrees: phase,
                treatment: treatment,
                comparison: comparison
            )

            stageResults.append(result)
            onComparison(comparison)
        }

        return PhaseRefinementStageResult(
            stage: stage,
            centerPhaseDegrees:
                ToneGeneratorMath
                    .normalizedPhaseDegrees(
                        centerPhaseDegrees
                    ),
            stepDegrees: stepDegrees,
            results: stageResults
        )
    }
}
