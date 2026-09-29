import Foundation
import Observation

struct AdaptiveControllerSettings: Equatable, Sendable {
    let phaseDegrees: Double
    let outputPercent: Double
}

struct AdaptiveControllerObservation: Equatable, Sendable {
    let settings: AdaptiveControllerSettings
    let treatment: TargetEnergyWindowSummary
    let comparison: BeforeAfterComparison
}

enum AdaptiveAdjustmentDimension: String, Equatable, Sendable {
    case phase = "Phase"
    case amplitude = "Amplitude"
}

enum AdaptiveControllerMath {
    static let phaseStepDegrees = 5.0
    static let amplitudeStepPercent = 2.0
    static let minimumImprovementDB = 0.35
    static let maximumAmplificationDB = 3.0
    static let maximumStableStandardDeviationDB = 2.5
    static let minimumOutputPercent =
        AmplitudeSearchMath.minimumSearchPercent

    static func phaseCandidates(
        around phaseDegrees: Double
    ) -> [Double] {
        PhaseSweepMath.normalizedUniquePhases(
            [
                phaseDegrees + phaseStepDegrees,
                phaseDegrees - phaseStepDegrees
            ]
        )
    }

    static func amplitudeCandidates(
        around outputPercent: Double,
        ceilingPercent: Double
    ) -> [Double] {
        let ceiling =
            ToneGeneratorMath.sanitizedOutputPercent(
                ceilingPercent
            )

        guard ceiling >= minimumOutputPercent else {
            return []
        }

        let current = min(
            ceiling,
            max(
                minimumOutputPercent,
                outputPercent
            )
        )

        return AmplitudeSearchMath
            .normalizedUniqueLevels(
                [
                    current + amplitudeStepPercent,
                    current - amplitudeStepPercent
                ],
                ceilingPercent: ceiling
            )
            .filter {
                abs($0 - current) > 0.0001
            }
    }

    static func bestObservation(
        from observations: [AdaptiveControllerObservation]
    ) -> AdaptiveControllerObservation? {
        observations.min {
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

            return
                $0.settings.outputPercent <
                $1.settings.outputPercent
        }
    }

    static func shouldAccept(
        current: AdaptiveControllerObservation,
        candidate: AdaptiveControllerObservation
    ) -> Bool {
        let improvement =
            current.treatment.averageBandEnergyDBFS -
            candidate.treatment.averageBandEnergyDBFS

        return
            improvement >= minimumImprovementDB &&
            candidate.treatment.standardDeviationDB <=
                maximumStableStandardDeviationDB
    }

    static func isUnsafeAmplification(
        _ observation: AdaptiveControllerObservation
    ) -> Bool {
        observation.comparison.treatmentMinusBaselineDB >=
            maximumAmplificationDB
    }

    static func isStable(
        _ observation: AdaptiveControllerObservation
    ) -> Bool {
        observation.treatment.standardDeviationDB <=
            maximumStableStandardDeviationDB
    }
}

@MainActor
@Observable
final class AdaptiveControllerModel {
    enum State: Equatable {
        case idle
        case starting
        case monitoring(iteration: Int)
        case probing(
            dimension: AdaptiveAdjustmentDimension,
            value: Double,
            candidate: Int,
            total: Int
        )
        case running
        case failed(String)

        var isRunning: Bool {
            switch self {
            case .starting, .monitoring, .probing, .running:
                true
            case .idle, .failed:
                false
            }
        }
    }

    static let requiredSamples = 10
    static let sampleIntervalSeconds = 0.10
    static let settleDurationSeconds = 0.25
    static let betweenIterationsSeconds = 0.40
    static let maximumAttemptsPerWindow = 25
    static let maximumConsecutiveUnstableWindows = 2

    private(set) var state: State = .idle
    private(set) var acceptedSettings:
        AdaptiveControllerSettings?
    private(set) var lastObservation:
        AdaptiveControllerObservation?
    private(set) var iterationCount = 0
    private(set) var acceptedAdjustmentCount = 0
    private(set) var rollbackCount = 0
    private(set) var searchCeilingPercent: Double = 0
    private(set) var lastAction = "Not running"

    private var generation: UInt64 = 0
    private var nextDimension:
        AdaptiveAdjustmentDimension = .phase
    private var consecutiveUnstableWindows = 0

    func reset() {
        generation += 1
        state = .idle
        acceptedSettings = nil
        lastObservation = nil
        iterationCount = 0
        acceptedAdjustmentCount = 0
        rollbackCount = 0
        searchCeilingPercent = 0
        lastAction = "Not running"
        nextDimension = .phase
        consecutiveUnstableWindows = 0
    }

    func cancel() {
        generation += 1
        state = .idle
        lastAction = "Stopped by user"
    }

    func run(
        seedSettings: AdaptiveControllerSettings,
        ceilingPercent: Double,
        baseline: TargetEnergyWindowSummary,
        applySettings:
            @escaping @MainActor
            (AdaptiveControllerSettings) -> Void,
        measurementProvider:
            @escaping @MainActor
            () -> TargetFrequencyEnergyMeasurement?,
        safetyCheck:
            @escaping @MainActor () -> String?,
        onAcceptedComparison:
            @escaping @MainActor
            (BeforeAfterComparison) -> Void,
        onFailSafe:
            @escaping @MainActor (String) -> Void
    ) async {
        guard !state.isRunning else { return }

        let ceiling =
            ToneGeneratorMath.sanitizedOutputPercent(
                ceilingPercent
            )
        let seed = AdaptiveControllerSettings(
            phaseDegrees:
                ToneGeneratorMath.normalizedPhaseDegrees(
                    seedSettings.phaseDegrees
                ),
            outputPercent: min(
                ceiling,
                max(
                    AdaptiveControllerMath
                        .minimumOutputPercent,
                    seedSettings.outputPercent
                )
            )
        )

        guard
            ceiling >=
                AdaptiveControllerMath.minimumOutputPercent
        else {
            failSafe(
                "Adaptive output ceiling is below the 2% minimum.",
                onFailSafe: onFailSafe
            )
            return
        }

        generation += 1
        let currentGeneration = generation

        searchCeilingPercent = ceiling
        acceptedSettings = seed
        lastObservation = nil
        iterationCount = 0
        acceptedAdjustmentCount = 0
        rollbackCount = 0
        nextDimension = .phase
        consecutiveUnstableWindows = 0
        state = .starting
        lastAction = "Applying optimized starting point"

        if let reason = safetyCheck() {
            failSafe(
                reason,
                onFailSafe: onFailSafe
            )
            return
        }

        applySettings(seed)

        guard
            let seedObservation = await measure(
                settings: seed,
                baseline: baseline,
                generation: currentGeneration,
                safetyCheck: safetyCheck,
                measurementProvider:
                    measurementProvider,
                onFailSafe: onFailSafe
            )
        else {
            return
        }

        guard
            validateAcceptedObservation(
                seedObservation,
                onFailSafe: onFailSafe
            )
        else {
            return
        }

        lastObservation = seedObservation
        lastAction = "Optimized starting point verified"
        state = .running

        while
            currentGeneration == generation,
            !Task.isCancelled
        {
            iterationCount += 1
            let iteration = iterationCount
            state = .monitoring(iteration: iteration)

            guard
                let settings = acceptedSettings
            else {
                failSafe(
                    "Adaptive controller lost its accepted settings.",
                    onFailSafe: onFailSafe
                )
                return
            }

            if let reason = safetyCheck() {
                failSafe(
                    reason,
                    onFailSafe: onFailSafe
                )
                return
            }

            applySettings(settings)

            guard
                let current = await measure(
                    settings: settings,
                    baseline: baseline,
                    generation: currentGeneration,
                    safetyCheck: safetyCheck,
                    measurementProvider:
                        measurementProvider,
                    onFailSafe: onFailSafe
                )
            else {
                return
            }

            guard
                validateAcceptedObservation(
                    current,
                    onFailSafe: onFailSafe
                )
            else {
                return
            }

            lastObservation = current

            let dimension = nextDimension
            nextDimension =
                dimension == .phase
                    ? .amplitude
                    : .phase

            let candidates =
                candidateSettings(
                    around: settings,
                    dimension: dimension
                )

            if candidates.isEmpty {
                lastAction =
                    "\(dimension.rawValue) held at boundary"
                state = .running
                await pauseBetweenIterations(
                    generation: currentGeneration
                )
                continue
            }

            var candidateObservations:
                [AdaptiveControllerObservation] = []

            for (offset, candidate)
                in candidates.enumerated()
            {
                guard
                    currentGeneration == generation,
                    !Task.isCancelled
                else {
                    return
                }

                let displayedValue =
                    dimension == .phase
                        ? candidate.phaseDegrees
                        : candidate.outputPercent

                state = .probing(
                    dimension: dimension,
                    value: displayedValue,
                    candidate: offset + 1,
                    total: candidates.count
                )

                if let reason = safetyCheck() {
                    failSafe(
                        reason,
                        onFailSafe: onFailSafe
                    )
                    return
                }

                applySettings(candidate)

                guard
                    let observation = await measure(
                        settings: candidate,
                        baseline: baseline,
                        generation:
                            currentGeneration,
                        safetyCheck: safetyCheck,
                        measurementProvider:
                            measurementProvider,
                        onFailSafe: onFailSafe
                    )
                else {
                    return
                }

                if
                    AdaptiveControllerMath
                        .isUnsafeAmplification(
                            observation
                        )
                {
                    failSafe(
                        String(
                            format:
                                "Adaptive probe amplified the target by %.2f dB versus baseline.",
                            observation.comparison
                                .treatmentMinusBaselineDB
                        ),
                        onFailSafe: onFailSafe
                    )
                    return
                }

                if AdaptiveControllerMath.isStable(
                    observation
                ) {
                    candidateObservations.append(
                        observation
                    )
                }
            }

            guard
                currentGeneration == generation,
                !Task.isCancelled
            else {
                return
            }

            let bestCandidate =
                AdaptiveControllerMath.bestObservation(
                    from: candidateObservations
                )

            if
                let bestCandidate,
                AdaptiveControllerMath.shouldAccept(
                    current: current,
                    candidate: bestCandidate
                )
            {
                acceptedSettings =
                    bestCandidate.settings
                lastObservation = bestCandidate
                acceptedAdjustmentCount += 1
                consecutiveUnstableWindows = 0

                let improvement =
                    current.treatment
                        .averageBandEnergyDBFS -
                    bestCandidate.treatment
                        .averageBandEnergyDBFS

                lastAction = String(
                    format:
                        "%@ accepted • %.2f dB better",
                    dimension.rawValue,
                    improvement
                )

                applySettings(
                    bestCandidate.settings
                )
                onAcceptedComparison(
                    bestCandidate.comparison
                )
            } else {
                rollbackCount += 1
                acceptedSettings = settings
                lastObservation = current
                lastAction =
                    "\(dimension.rawValue) probe rolled back"
                applySettings(settings)
            }

            state = .running
            await pauseBetweenIterations(
                generation: currentGeneration
            )
        }
    }

    private func candidateSettings(
        around settings: AdaptiveControllerSettings,
        dimension: AdaptiveAdjustmentDimension
    ) -> [AdaptiveControllerSettings] {
        switch dimension {
        case .phase:
            return AdaptiveControllerMath
                .phaseCandidates(
                    around: settings.phaseDegrees
                )
                .map {
                    AdaptiveControllerSettings(
                        phaseDegrees: $0,
                        outputPercent:
                            settings.outputPercent
                    )
                }

        case .amplitude:
            return AdaptiveControllerMath
                .amplitudeCandidates(
                    around: settings.outputPercent,
                    ceilingPercent:
                        searchCeilingPercent
                )
                .map {
                    AdaptiveControllerSettings(
                        phaseDegrees:
                            settings.phaseDegrees,
                        outputPercent: $0
                    )
                }
        }
    }

    private func measure(
        settings: AdaptiveControllerSettings,
        baseline: TargetEnergyWindowSummary,
        generation currentGeneration: UInt64,
        safetyCheck:
            @escaping @MainActor () -> String?,
        measurementProvider:
            @escaping @MainActor
            () -> TargetFrequencyEnergyMeasurement?,
        onFailSafe:
            @escaping @MainActor (String) -> Void
    ) async -> AdaptiveControllerObservation? {
        if let reason = safetyCheck() {
            failSafe(
                reason,
                onFailSafe: onFailSafe
            )
            return nil
        }

        try? await Task.sleep(
            nanoseconds: UInt64(
                Self.settleDurationSeconds *
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
            Self.requiredSamples
        )

        var attempts = 0

        while
            measurements.count < Self.requiredSamples,
            attempts < Self.maximumAttemptsPerWindow,
            currentGeneration == generation,
            !Task.isCancelled
        {
            if let reason = safetyCheck() {
                failSafe(
                    reason,
                    onFailSafe: onFailSafe
                )
                return nil
            }

            attempts += 1

            if
                let measurement =
                    measurementProvider(),
                abs(
                    measurement.targetFrequencyHz -
                    baseline.condition
                        .targetFrequencyHz
                ) <= 0.5
            {
                measurements.append(measurement)
            }

            try? await Task.sleep(
                nanoseconds: UInt64(
                    Self.sampleIntervalSeconds *
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
            phaseDegrees: settings.phaseDegrees,
            outputPercent: settings.outputPercent,
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
            failSafe(
                "Target-energy measurement became unavailable.",
                onFailSafe: onFailSafe
            )
            return nil
        }

        return AdaptiveControllerObservation(
            settings: settings,
            treatment: treatment,
            comparison: comparison
        )
    }

    private func validateAcceptedObservation(
        _ observation: AdaptiveControllerObservation,
        onFailSafe:
            @escaping @MainActor (String) -> Void
    ) -> Bool {
        if
            AdaptiveControllerMath
                .isUnsafeAmplification(observation)
        {
            failSafe(
                String(
                    format:
                        "Target energy is %.2f dB above baseline.",
                    observation.comparison
                        .treatmentMinusBaselineDB
                ),
                onFailSafe: onFailSafe
            )
            return false
        }

        if AdaptiveControllerMath.isStable(
            observation
        ) {
            consecutiveUnstableWindows = 0
            return true
        }

        consecutiveUnstableWindows += 1
        lastAction = String(
            format:
                "Measurement unstable • σ %.2f dB",
            observation.treatment
                .standardDeviationDB
        )

        if
            consecutiveUnstableWindows >=
                Self.maximumConsecutiveUnstableWindows
        {
            failSafe(
                "Target-energy measurement remained unstable for two consecutive windows.",
                onFailSafe: onFailSafe
            )
            return false
        }

        return true
    }

    private func pauseBetweenIterations(
        generation currentGeneration: UInt64
    ) async {
        try? await Task.sleep(
            nanoseconds: UInt64(
                Self.betweenIterationsSeconds *
                1_000_000_000
            )
        )

        guard currentGeneration == generation else {
            return
        }
    }

    private func failSafe(
        _ reason: String,
        onFailSafe:
            @escaping @MainActor (String) -> Void
    ) {
        generation += 1
        state = .failed(reason)
        lastAction = "FAIL-SAFE • " + reason
        onFailSafe(reason)
    }
}
