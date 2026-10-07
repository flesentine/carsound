import Foundation

enum HeadPositionPreset:
    String,
    CaseIterable,
    Codable,
    Hashable,
    Identifiable,
    Sendable
{
    case reference
    case left
    case right
    case forward
    case back

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .reference:
            return "Reference"
        case .left:
            return "Left"
        case .right:
            return "Right"
        case .forward:
            return "Forward"
        case .back:
            return "Back"
        }
    }

    var shortTitle: String {
        switch self {
        case .reference:
            return "Ref"
        case .left:
            return "Left"
        case .right:
            return "Right"
        case .forward:
            return "Fwd"
        case .back:
            return "Back"
        }
    }

    var instruction: String {
        switch self {
        case .reference:
            return "Normal centered listening posture."
        case .left:
            return "Move your head left from the reference posture."
        case .right:
            return "Move your head right from the reference posture."
        case .forward:
            return "Move your head forward from the reference posture."
        case .back:
            return "Move your head back from the reference posture."
        }
    }
}

enum HeadPositionSensitivityAssessment:
    String,
    Equatable,
    Sendable
{
    case insufficientCoverage =
        "Need 2+ positions"
    case low =
        "Low sensitivity"
    case moderate =
        "Moderate sensitivity"
    case high =
        "High sensitivity"
    case directionReversal =
        "Direction reversal"
}

struct HeadPositionBaseCondition:
    Hashable,
    Identifiable,
    Sendable
{
    let routeSignature: String
    let frequencyTenthsHz: Int
    let phaseDegrees: Int
    let outputPercent: Int

    var id: String {
        [
            routeSignature,
            String(frequencyTenthsHz),
            String(phaseDegrees),
            String(outputPercent)
        ]
        .joined(separator: "|")
    }

    var targetFrequencyHz: Double {
        Double(frequencyTenthsHz) /
            10
    }
}

struct HeadPositionResult:
    Equatable,
    Identifiable,
    Sendable
{
    let position: HeadPositionPreset
    let sessionCount: Int
    let comparisonCount: Int
    let meanReductionDB: Double
    let minimumSessionMeanReductionDB:
        Double
    let maximumSessionMeanReductionDB:
        Double
    let latestAt: Date

    var id: String {
        position.rawValue
    }
}

struct HeadPositionSensitivityGroup:
    Equatable,
    Identifiable,
    Sendable
{
    let condition:
        HeadPositionBaseCondition
    let comparisonCount: Int
    let positionResults:
        [HeadPositionResult]
    let bestPosition:
        HeadPositionPreset?
    let worstPosition:
        HeadPositionPreset?
    let bestMeanReductionDB: Double?
    let worstMeanReductionDB: Double?
    let spreadDB: Double?
    let assessment:
        HeadPositionSensitivityAssessment
    let latestAt: Date

    var id: String {
        condition.id
    }

    var positionCount: Int {
        positionResults.count
    }
}

struct HeadPositionSensitivitySnapshot:
    Equatable,
    Sendable
{
    let comparisonEventCount: Int
    let taggedComparisonCount: Int
    let excludedComparisonCount: Int
    let conditionCount: Int
    let multiPositionConditionCount: Int
    let highSensitivityCount: Int
    let directionReversalCount: Int
    let maximumSpreadDB: Double?
    let groups:
        [HeadPositionSensitivityGroup]
}

enum HeadPositionSensitivityAnalytics {
    static let lowSensitivityMaximumSpreadDB =
        1.0
    static let moderateSensitivityMaximumSpreadDB =
        3.0

    static func snapshot(
        events: [StructuredLogEvent]
    ) -> HeadPositionSensitivitySnapshot {
        let comparisons =
            events.filter {
                $0.kind ==
                    .comparisonSaved
            }

        var grouped:
            [
                HeadPositionBaseCondition:
                    [StructuredLogEvent]
            ] = [:]
        var tagged = 0
        var excluded = 0

        for event in comparisons {
            guard
                event.metrics[
                    "measured_reduction_db"
                ] != nil,
                let position =
                    position(for: event),
                let condition =
                    baseCondition(
                        for: event
                    )
            else {
                excluded += 1
                continue
            }

            tagged += 1

            grouped[
                condition,
                default: []
            ].append(event)
        }

        let groups =
            grouped.map {
                makeGroup(
                    condition: $0.key,
                    events: $0.value
                )
            }
            .sorted {
                if
                    $0.positionCount ==
                        $1.positionCount
                {
                    let leftSpread =
                        $0.spreadDB ?? -1
                    let rightSpread =
                        $1.spreadDB ?? -1

                    if
                        leftSpread ==
                            rightSpread
                    {
                        return $0.latestAt >
                            $1.latestAt
                    }

                    return leftSpread >
                        rightSpread
                }

                return $0.positionCount >
                    $1.positionCount
            }

        let multiPosition =
            groups.filter {
                $0.positionCount >= 2
            }

        return HeadPositionSensitivitySnapshot(
            comparisonEventCount:
                comparisons.count,
            taggedComparisonCount:
                tagged,
            excludedComparisonCount:
                excluded,
            conditionCount:
                groups.count,
            multiPositionConditionCount:
                multiPosition.count,
            highSensitivityCount:
                multiPosition.filter {
                    $0.assessment ==
                        .high
                }.count,
            directionReversalCount:
                multiPosition.filter {
                    $0.assessment ==
                        .directionReversal
                }.count,
            maximumSpreadDB:
                multiPosition
                    .compactMap {
                        $0.spreadDB
                    }
                    .max(),
            groups: groups
        )
    }

    static func position(
        for event: StructuredLogEvent
    ) -> HeadPositionPreset? {
        guard
            let raw =
                event.text[
                    "head_position"
                ]
        else {
            return nil
        }

        return HeadPositionPreset(
            rawValue: raw
        )
    }

    static func assessment(
        positionMeanReductionsDB:
            [Double]
    ) -> HeadPositionSensitivityAssessment {
        guard
            positionMeanReductionsDB
                .count >= 2
        else {
            return .insufficientCoverage
        }

        let positive =
            positionMeanReductionsDB
                .contains {
                    $0 >
                        RepeatabilityAnalytics
                            .neutralDeadbandDB
                }
        let negative =
            positionMeanReductionsDB
                .contains {
                    $0 <
                        -RepeatabilityAnalytics
                            .neutralDeadbandDB
                }

        if positive && negative {
            return .directionReversal
        }

        guard
            let minimum =
                positionMeanReductionsDB
                    .min(),
            let maximum =
                positionMeanReductionsDB
                    .max()
        else {
            return .insufficientCoverage
        }

        let spread =
            maximum - minimum

        if
            spread <=
                lowSensitivityMaximumSpreadDB
        {
            return .low
        }

        if
            spread <=
                moderateSensitivityMaximumSpreadDB
        {
            return .moderate
        }

        return .high
    }

    private static func baseCondition(
        for event: StructuredLogEvent
    ) -> HeadPositionBaseCondition? {
        guard
            let route =
                event.context
                    .routeSignature,
            !route.isEmpty,
            let frequency =
                event.context
                    .targetFrequencyHz,
            let phase =
                event.context
                    .phaseDegrees,
            let output =
                event.context
                    .outputPercent,
            frequency.isFinite,
            phase.isFinite,
            output.isFinite
        else {
            return nil
        }

        return HeadPositionBaseCondition(
            routeSignature: route,
            frequencyTenthsHz:
                Int(
                    (frequency * 10)
                        .rounded()
                ),
            phaseDegrees:
                normalizedPhaseDegrees(
                    phase
                ),
            outputPercent:
                Int(
                    output.rounded()
                )
        )
    }

    private static func makeGroup(
        condition:
            HeadPositionBaseCondition,
        events: [StructuredLogEvent]
    ) -> HeadPositionSensitivityGroup {
        let byPosition =
            Dictionary(
                grouping: events
            ) {
                position(for: $0)
            }

        let results =
            byPosition.compactMap {
                position,
                positionEvents ->
                    HeadPositionResult?
                in

                guard let position else {
                    return nil
                }

                let bySession =
                    Dictionary(
                        grouping:
                            positionEvents,
                        by: {
                            $0.sessionID
                        }
                    )

                let sessionMeans =
                    bySession.compactMap {
                        _,
                        sessionEvents ->
                            (
                                mean: Double,
                                latest: Date
                            )?
                        in

                        let reductions =
                            sessionEvents
                                .compactMap {
                                    $0.metrics[
                                        "measured_reduction_db"
                                    ]
                                }

                        guard
                            !reductions
                                .isEmpty
                        else {
                            return nil
                        }

                        return (
                            mean:
                                average(
                                    reductions
                                ),
                            latest:
                                sessionEvents
                                    .map {
                                        $0.recordedAt
                                    }
                                    .max() ??
                                .distantPast
                        )
                    }

                guard
                    !sessionMeans.isEmpty
                else {
                    return nil
                }

                let means =
                    sessionMeans.map {
                        $0.mean
                    }

                return HeadPositionResult(
                    position: position,
                    sessionCount:
                        sessionMeans.count,
                    comparisonCount:
                        positionEvents.count,
                    meanReductionDB:
                        average(means),
                    minimumSessionMeanReductionDB:
                        means.min() ?? 0,
                    maximumSessionMeanReductionDB:
                        means.max() ?? 0,
                    latestAt:
                        sessionMeans
                            .map {
                                $0.latest
                            }
                            .max() ??
                        .distantPast
                )
            }
            .sorted {
                $0.position.rawValue <
                    $1.position.rawValue
            }

        let positionMeans =
            results.map {
                $0.meanReductionDB
            }
        let best =
            results.max {
                $0.meanReductionDB <
                    $1.meanReductionDB
            }
        let worst =
            results.min {
                $0.meanReductionDB <
                    $1.meanReductionDB
            }
        let spread =
            if
                let minimum =
                    positionMeans.min(),
                let maximum =
                    positionMeans.max()
            {
                maximum - minimum
            } else {
                nil
            }

        return HeadPositionSensitivityGroup(
            condition: condition,
            comparisonCount:
                events.count,
            positionResults:
                results,
            bestPosition:
                best?.position,
            worstPosition:
                worst?.position,
            bestMeanReductionDB:
                best?.meanReductionDB,
            worstMeanReductionDB:
                worst?.meanReductionDB,
            spreadDB: spread,
            assessment:
                assessment(
                    positionMeanReductionsDB:
                        positionMeans
                ),
            latestAt:
                results
                    .map {
                        $0.latestAt
                    }
                    .max() ??
                .distantPast
        )
    }

    private static func normalizedPhaseDegrees(
        _ phase: Double
    ) -> Int {
        let rounded =
            Int(phase.rounded())

        return (
            (rounded % 360) +
            360
        ) % 360
    }

    private static func average(
        _ values: [Double]
    ) -> Double {
        guard !values.isEmpty else {
            return 0
        }

        return values.reduce(0, +) /
            Double(values.count)
    }
}
