import Foundation

enum AdaptiveAdjustmentDirection: Int, Equatable, Sendable {
    case negative = -1
    case positive = 1
}

struct AdaptiveStabilityGuard: Equatable, Sendable {
    static let maximumPhaseExcursionDegrees = 20.0
    static let maximumOutputExcursionPercent = 8.0
    static let cooldownIterationsAfterAcceptance = 1
    static let rollbackStreakBeforeHold = 4
    static let holdIterationsAfterRollbackStreak = 3
    static let maximumConsecutiveDirectionReversals = 3

    private(set) var seed: AdaptiveControllerSettings
    private(set) var rollbackStreak = 0
    private(set) var holdIterationsRemaining = 0
    private(set) var holdCount = 0
    private(set) var phaseDirectionReversalStreak = 0
    private(set) var amplitudeDirectionReversalStreak = 0

    private var lastPhaseDirection: AdaptiveAdjustmentDirection?
    private var lastAmplitudeDirection: AdaptiveAdjustmentDirection?

    init(seed: AdaptiveControllerSettings) {
        self.seed = AdaptiveControllerSettings(
            phaseDegrees:
                ToneGeneratorMath.normalizedPhaseDegrees(
                    seed.phaseDegrees
                ),
            outputPercent:
                ToneGeneratorMath.sanitizedOutputPercent(
                    seed.outputPercent
                )
        )
    }

    var phaseReversalStreak: Int {
        phaseDirectionReversalStreak
    }

    var amplitudeReversalStreak: Int {
        amplitudeDirectionReversalStreak
    }

    func phaseExcursionDegrees(
        for settings: AdaptiveControllerSettings
    ) -> Double {
        abs(
            Self.signedPhaseDeltaDegrees(
                from: seed.phaseDegrees,
                to: settings.phaseDegrees
            )
        )
    }

    func outputExcursionPercent(
        for settings: AdaptiveControllerSettings
    ) -> Double {
        abs(
            settings.outputPercent -
            seed.outputPercent
        )
    }

    func allows(
        _ settings: AdaptiveControllerSettings,
        ceilingPercent: Double
    ) -> Bool {
        let ceiling =
            ToneGeneratorMath.sanitizedOutputPercent(
                ceilingPercent
            )

        return
            phaseExcursionDegrees(for: settings) <=
                Self.maximumPhaseExcursionDegrees +
                0.0001 &&
            outputExcursionPercent(for: settings) <=
                Self.maximumOutputExcursionPercent +
                0.0001 &&
            settings.outputPercent >=
                AdaptiveControllerMath.minimumOutputPercent &&
            settings.outputPercent <= ceiling + 0.0001
    }

    mutating func recordAcceptance(
        from previous: AdaptiveControllerSettings,
        to accepted: AdaptiveControllerSettings,
        dimension: AdaptiveAdjustmentDimension
    ) -> String? {
        rollbackStreak = 0
        holdIterationsRemaining =
            Self.cooldownIterationsAfterAcceptance

        let delta: Double
        switch dimension {
        case .phase:
            delta = Self.signedPhaseDeltaDegrees(
                from: previous.phaseDegrees,
                to: accepted.phaseDegrees
            )

        case .amplitude:
            delta =
                accepted.outputPercent -
                previous.outputPercent
        }

        guard
            let direction =
                Self.direction(for: delta)
        else {
            return nil
        }

        switch dimension {
        case .phase:
            if
                let previousDirection = lastPhaseDirection,
                previousDirection != direction
            {
                phaseDirectionReversalStreak += 1
            } else {
                phaseDirectionReversalStreak = 0
            }

            lastPhaseDirection = direction

            if
                phaseDirectionReversalStreak >=
                    Self
                        .maximumConsecutiveDirectionReversals
            {
                return "Adaptive phase adjustments oscillated direction repeatedly."
            }

        case .amplitude:
            if
                let previousDirection =
                    lastAmplitudeDirection,
                previousDirection != direction
            {
                amplitudeDirectionReversalStreak += 1
            } else {
                amplitudeDirectionReversalStreak = 0
            }

            lastAmplitudeDirection = direction

            if
                amplitudeDirectionReversalStreak >=
                    Self
                        .maximumConsecutiveDirectionReversals
            {
                return "Adaptive amplitude adjustments oscillated direction repeatedly."
            }
        }

        return nil
    }

    mutating func recordRollback() {
        rollbackStreak += 1

        if
            rollbackStreak >=
                Self.rollbackStreakBeforeHold
        {
            rollbackStreak = 0
            holdIterationsRemaining =
                max(
                    holdIterationsRemaining,
                    Self
                        .holdIterationsAfterRollbackStreak
                )
            holdCount += 1
        }
    }

    mutating func consumeHoldIteration() -> Bool {
        guard holdIterationsRemaining > 0 else {
            return false
        }

        holdIterationsRemaining -= 1
        return true
    }

    static func signedPhaseDeltaDegrees(
        from start: Double,
        to end: Double
    ) -> Double {
        var delta =
            normalizedPhaseForDelta(end) -
            normalizedPhaseForDelta(start)

        if delta > 180 {
            delta -= 360
        } else if delta < -180 {
            delta += 360
        }

        return delta
    }

    private static func normalizedPhaseForDelta(
        _ degrees: Double
    ) -> Double {
        ToneGeneratorMath.normalizedPhaseDegrees(
            degrees
        )
    }

    private static func direction(
        for delta: Double
    ) -> AdaptiveAdjustmentDirection? {
        if delta > 0.0001 {
            return .positive
        }

        if delta < -0.0001 {
            return .negative
        }

        return nil
    }
}
