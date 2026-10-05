import Foundation

enum OverallConfidenceLevel: String, Equatable, Sendable {
    case insufficientEvidence = "Insufficient evidence"
    case low = "Low confidence"
    case moderate = "Moderate confidence"
    case high = "High confidence"
}

enum ConfidenceComponentID: String, Equatable, Sendable {
    case toneEvidence = "Tone evidence"
    case measurementQuality = "Measurement quality"
    case measuredReduction = "Measured reduction"
    case adaptiveStability = "Adaptive stability"
    case routeTiming = "Route timing"
    case soundVibration = "Sound-vibration evidence"
    case interferenceSafety = "Interference / safety"
}

struct ConfidenceComponent: Equatable, Sendable, Identifiable {
    let id: ConfidenceComponentID
    let weight: Double
    let score: Double?
    let detail: String

    var weightedPoints: Double {
        guard let score else {
            return 0
        }

        return weight *
            min(
                1,
                max(
                    0,
                    score
                )
            )
    }

    var isAvailable: Bool {
        score != nil
    }
}

struct OverallConfidenceInput: Equatable, Sendable {
    let persistentToneUpdateCount: UInt64
    let persistentTones: [PersistentTone]

    let comparison: BeforeAfterComparison?

    let adaptiveEvidencePresent: Bool
    let adaptiveFailed: Bool
    let adaptiveIterations: Int
    let adaptiveRollbacks: Int
    let adaptiveStabilityHoldCount: Int
    let adaptivePhaseReversalStreak: Int
    let adaptiveAmplitudeReversalStreak: Int
    let adaptiveTreatmentStandardDeviationDB: Double?

    let processingCallbackJitterMilliseconds: Double?
    let bluetoothActive: Bool
    let bluetoothJitter: BluetoothJitterSnapshot?

    let soundVibration:
        SoundVibrationCorrelationSummary

    let musicInterference:
        MusicInterferenceSnapshot
    let microphoneIsClipping: Bool
}

struct OverallConfidenceSnapshot: Equatable, Sendable {
    let scorePercent: Double
    let evidenceCoveragePercent: Double
    let level: OverallConfidenceLevel
    let components: [ConfidenceComponent]
    let limitingFactors: [String]

    static let empty = OverallConfidenceSnapshot(
        scorePercent: 0,
        evidenceCoveragePercent: 0,
        level: .insufficientEvidence,
        components: [],
        limitingFactors: []
    )
}

enum OverallConfidenceMath {
    static let minimumCoverageForAssessment = 0.60
    static let highThreshold = 80.0
    static let moderateThreshold = 55.0

    static let toneWeight = 18.0
    static let measurementQualityWeight = 16.0
    static let measuredReductionWeight = 14.0
    static let adaptiveStabilityWeight = 14.0
    static let routeTimingWeight = 14.0
    static let soundVibrationWeight = 12.0
    static let interferenceSafetyWeight = 12.0
    static let expectedMeasurementSamples = 20

    static func score(
        input: OverallConfidenceInput
    ) -> OverallConfidenceSnapshot {
        var limitingFactors: [String] = []

        let tone =
            toneComponent(input)
        let quality =
            measurementQualityComponent(input)
        let reduction =
            measuredReductionComponent(input)
        let adaptive =
            adaptiveStabilityComponent(input)
        let route =
            routeTimingComponent(input)
        let correlation =
            soundVibrationComponent(input)
        let interference =
            interferenceSafetyComponent(input)

        let components = [
            tone,
            quality,
            reduction,
            adaptive,
            route,
            correlation,
            interference
        ]

        let totalWeight =
            components
                .map { $0.weight }
                .reduce(0, +)
        let availableWeight =
            components
                .filter { $0.isAvailable }
                .map { $0.weight }
                .reduce(0, +)

        let coverage =
            totalWeight > 0
            ? availableWeight /
                totalWeight
            : 0

        let normalizedScore: Double

        if availableWeight > 0 {
            normalizedScore =
                components
                    .map {
                        $0.weightedPoints
                    }
                    .reduce(0, +) /
                availableWeight *
                100.0
        } else {
            normalizedScore = 0
        }

        var cappedScore =
            min(
                100,
                max(
                    0,
                    normalizedScore
                )
            )

        if input.microphoneIsClipping {
            cappedScore =
                min(
                    cappedScore,
                    20
                )
            limitingFactors.append(
                "Microphone clipping is active."
            )
        }

        if
            let comparison =
                input.comparison,
            comparison
                .treatmentMinusBaselineDB >=
                AdaptiveControllerMath
                    .maximumAmplificationDB
        {
            cappedScore =
                min(
                    cappedScore,
                    20
                )
            limitingFactors.append(
                "Treatment amplified the target by 3 dB or more."
            )
        }

        if input.adaptiveFailed {
            cappedScore =
                min(
                    cappedScore,
                    35
                )
            limitingFactors.append(
                "Adaptive controller entered a fail-safe state."
            )
        }

        if
            input.bluetoothActive,
            let jitter =
                input.bluetoothJitter,
            jitter.stability == .unstable
        {
            cappedScore =
                min(
                    cappedScore,
                    55
                )
            limitingFactors.append(
                "Bluetooth timing was unstable during the live jitter run."
            )
        }

        if
            input.musicInterference.level ==
                .likely
        {
            cappedScore =
                min(
                    cappedScore,
                    60
                )
            limitingFactors.append(
                "Likely program-audio interference is contaminating the microphone spectrum."
            )
        }

        if coverage <
            minimumCoverageForAssessment
        {
            limitingFactors.append(
                "Evidence coverage is below 60%."
            )
        }

        if
            input.comparison == nil
        {
            limitingFactors.append(
                "No complete baseline/treatment comparison is available."
            )
        }

        if
            input.persistentToneUpdateCount >= 8,
            !input.persistentTones.contains(
                where: {
                    $0.isPersistent
                }
            )
        {
            limitingFactors.append(
                "No persistent target-like tone has been established."
            )
        }

        let level: OverallConfidenceLevel

        if
            coverage <
                minimumCoverageForAssessment
        {
            level = .insufficientEvidence
        } else if
            cappedScore >=
                highThreshold
        {
            level = .high
        } else if
            cappedScore >=
                moderateThreshold
        {
            level = .moderate
        } else {
            level = .low
        }

        return OverallConfidenceSnapshot(
            scorePercent: cappedScore,
            evidenceCoveragePercent:
                coverage * 100.0,
            level: level,
            components: components,
            limitingFactors:
                limitingFactors
        )
    }

    static func toneComponent(
        _ input: OverallConfidenceInput
    ) -> ConfidenceComponent {
        guard
            input.persistentToneUpdateCount >= 8
        else {
            return ConfidenceComponent(
                id: .toneEvidence,
                weight: toneWeight,
                score: nil,
                detail:
                    "Need more microphone tone observations."
            )
        }

        guard
            let best =
                input.persistentTones
                    .max(by: {
                        $0.confidence <
                        $1.confidence
                    })
        else {
            return ConfidenceComponent(
                id: .toneEvidence,
                weight: toneWeight,
                score: 0,
                detail:
                    "No persistent tone candidate is present."
            )
        }

        let persistenceMultiplier =
            best.isPersistent
            ? 1.0
            : 0.55
        let score =
            clamp01(
                best.confidence *
                persistenceMultiplier
            )

        return ConfidenceComponent(
            id: .toneEvidence,
            weight: toneWeight,
            score: score,
            detail: String(
                format:
                    "%.1f Hz • %.0f%% tone confidence • %.0f%% presence",
                best.frequencyHz,
                best.confidence * 100,
                best.presenceRatio * 100
            )
        )
    }

    static func measurementQualityComponent(
        _ input: OverallConfidenceInput
    ) -> ConfidenceComponent {
        guard
            let comparison =
                input.comparison
        else {
            return ConfidenceComponent(
                id: .measurementQuality,
                weight:
                    measurementQualityWeight,
                score: nil,
                detail:
                    "Capture baseline and treatment windows."
            )
        }

        let baseline =
            comparison.baseline
        let treatment =
            comparison.treatment

        let expectedSamples =
            Double(
                expectedMeasurementSamples
            )
        let completeness =
            min(
                1,
                Double(
                    min(
                        baseline.sampleCount,
                        treatment.sampleCount
                    )
                ) /
                max(
                    1,
                    expectedSamples
                )
            )

        let worstDeviation =
            max(
                baseline.standardDeviationDB,
                treatment.standardDeviationDB
            )
        let stability =
            standardDeviationScore(
                worstDeviation
            )
        let score =
            clamp01(
                0.35 * completeness +
                0.65 * stability
            )

        return ConfidenceComponent(
            id: .measurementQuality,
            weight:
                measurementQualityWeight,
            score: score,
            detail: String(
                format:
                    "%d/%d samples • worst σ %.2f dB",
                min(
                    baseline.sampleCount,
                    treatment.sampleCount
                ),
                Int(expectedSamples),
                worstDeviation
            )
        )
    }

    static func measuredReductionComponent(
        _ input: OverallConfidenceInput
    ) -> ConfidenceComponent {
        guard
            let comparison =
                input.comparison
        else {
            return ConfidenceComponent(
                id: .measuredReduction,
                weight:
                    measuredReductionWeight,
                score: nil,
                detail:
                    "No measured reduction yet."
            )
        }

        let reduction =
            comparison.measuredReductionDB
        let score =
            clamp01(
                reduction / 6.0
            )

        return ConfidenceComponent(
            id: .measuredReduction,
            weight:
                measuredReductionWeight,
            score: score,
            detail: String(
                format:
                    "%+.2f dB measured reduction",
                reduction
            )
        )
    }

    static func adaptiveStabilityComponent(
        _ input: OverallConfidenceInput
    ) -> ConfidenceComponent {
        guard
            input.adaptiveEvidencePresent
        else {
            return ConfidenceComponent(
                id: .adaptiveStability,
                weight:
                    adaptiveStabilityWeight,
                score: nil,
                detail:
                    "Run adaptive control to establish stability evidence."
            )
        }

        if input.adaptiveFailed {
            return ConfidenceComponent(
                id: .adaptiveStability,
                weight:
                    adaptiveStabilityWeight,
                score: 0,
                detail:
                    "Adaptive controller fail-safe."
            )
        }

        let deviationScore =
            input
                .adaptiveTreatmentStandardDeviationDB
                .map(
                    standardDeviationScore
                ) ?? 0.5

        let rollbackDenominator =
            max(
                1.0,
                Double(
                    max(
                        input.adaptiveIterations,
                        1
                    )
                ) * 0.75
            )
        let rollbackScore =
            clamp01(
                1.0 -
                Double(
                    input.adaptiveRollbacks
                ) /
                rollbackDenominator
            )

        let reversal =
            max(
                input
                    .adaptivePhaseReversalStreak,
                input
                    .adaptiveAmplitudeReversalStreak
            )
        let reversalScore =
            clamp01(
                1.0 -
                Double(reversal) / 3.0
            )
        let holdScore =
            clamp01(
                1.0 -
                Double(
                    input
                        .adaptiveStabilityHoldCount
                ) / 3.0
            )

        let score =
            clamp01(
                0.50 * deviationScore +
                0.10 * rollbackScore +
                0.25 * reversalScore +
                0.15 * holdScore
            )

        return ConfidenceComponent(
            id: .adaptiveStability,
            weight:
                adaptiveStabilityWeight,
            score: score,
            detail: String(
                format:
                    "%d iterations • %d rollbacks • %d holds",
                input.adaptiveIterations,
                input.adaptiveRollbacks,
                input
                    .adaptiveStabilityHoldCount
            )
        )
    }

    static func routeTimingComponent(
        _ input: OverallConfidenceInput
    ) -> ConfidenceComponent {
        if input.bluetoothActive {
            guard
                let jitter =
                    input.bluetoothJitter
            else {
                return ConfidenceComponent(
                    id: .routeTiming,
                    weight:
                        routeTimingWeight,
                    score: nil,
                    detail:
                        "Run Bluetooth jitter diagnostics for this route."
                )
            }

            let score: Double

            switch jitter.stability {
            case .stable:
                score = 1.0
            case .variable:
                score = 0.60
            case .unstable:
                score = 0.15
            case .insufficientData:
                score = 0.40
            }

            return ConfidenceComponent(
                id: .routeTiming,
                weight:
                    routeTimingWeight,
                score: score,
                detail: String(
                    format:
                        "%@ • callback σ %.2f ms • spectrum-age σ %.2f ms",
                    jitter.stability.rawValue,
                    jitter.callbackJitterMilliseconds,
                    jitter
                        .spectrumCenterAgeJitterMilliseconds
                )
            )
        }

        guard
            let jitter =
                input.processingCallbackJitterMilliseconds,
            jitter >= 0
        else {
            return ConfidenceComponent(
                id: .routeTiming,
                weight:
                    routeTimingWeight,
                score: nil,
                detail:
                    "Need live processing timing."
            )
        }

        let score =
            timingJitterScore(
                jitter
            )

        return ConfidenceComponent(
            id: .routeTiming,
            weight:
                routeTimingWeight,
            score: score,
            detail: String(
                format:
                    "Non-Bluetooth callback jitter σ %.3f ms",
                jitter
            )
        )
    }

    static func soundVibrationComponent(
        _ input: OverallConfidenceInput
    ) -> ConfidenceComponent {
        let summary =
            input.soundVibration

        guard
            summary.opportunityCount >=
                SoundVibrationCorrelationMath
                    .minimumOpportunitiesForAssessment
        else {
            return ConfidenceComponent(
                id: .soundVibration,
                weight:
                    soundVibrationWeight,
                score: nil,
                detail:
                    "Run the paired sound-vibration correlation window."
            )
        }

        let score: Double

        switch summary.level {
        case .coMoving:
            let correlation =
                max(
                    0,
                    summary
                        .amplitudeCorrelation ??
                    0
                )
            score =
                clamp01(
                    0.70 +
                    0.15 *
                    summary.matchPresenceRatio +
                    0.15 * correlation
                )

        case .frequencyAligned:
            score =
                clamp01(
                    0.55 +
                    0.25 *
                    summary.matchPresenceRatio +
                    0.20 *
                    (
                        summary
                            .averageFrequencyAgreement ??
                        0
                    )
                )

        case .noConsistentMatch:
            score = 0.35

        case .insufficientData:
            return ConfidenceComponent(
                id: .soundVibration,
                weight:
                    soundVibrationWeight,
                score: nil,
                detail:
                    "Correlation run does not yet have enough evidence."
            )
        }

        return ConfidenceComponent(
            id: .soundVibration,
            weight:
                soundVibrationWeight,
            score: score,
            detail: String(
                format:
                    "%@ • %.0f%% track presence",
                summary.level.rawValue,
                summary.matchPresenceRatio *
                    100
            )
        )
    }

    static func interferenceSafetyComponent(
        _ input: OverallConfidenceInput
    ) -> ConfidenceComponent {
        guard
            input.musicInterference
                .updateCount >= 3
        else {
            return ConfidenceComponent(
                id: .interferenceSafety,
                weight:
                    interferenceSafetyWeight,
                score: nil,
                detail:
                    "Need more microphone FFT updates."
            )
        }

        if input.microphoneIsClipping {
            return ConfidenceComponent(
                id: .interferenceSafety,
                weight:
                    interferenceSafetyWeight,
                score: 0,
                detail:
                    "Microphone clipping is active."
            )
        }

        let score: Double

        switch
            input.musicInterference.level
        {
        case .clear:
            score = 1.0
        case .possible:
            score = 0.55
        case .likely:
            score = 0.15
        }

        return ConfidenceComponent(
            id: .interferenceSafety,
            weight:
                interferenceSafetyWeight,
            score: score,
            detail: String(
                format:
                    "%@ • interference score %.0f%%",
                input
                    .musicInterference
                    .level.rawValue,
                input
                    .musicInterference
                    .smoothedScore *
                    100
            )
        )
    }

    static func standardDeviationScore(
        _ deviationDB: Double
    ) -> Double {
        if deviationDB <= 0.5 {
            return 1
        }

        if deviationDB >= 2.5 {
            return 0
        }

        return clamp01(
            1.0 -
            (
                deviationDB -
                0.5
            ) / 2.0
        )
    }

    static func timingJitterScore(
        _ jitterMilliseconds: Double
    ) -> Double {
        if jitterMilliseconds <= 1.0 {
            return 1
        }

        if jitterMilliseconds >= 4.0 {
            return 0
        }

        return clamp01(
            1.0 -
            (
                jitterMilliseconds -
                1.0
            ) / 3.0
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
