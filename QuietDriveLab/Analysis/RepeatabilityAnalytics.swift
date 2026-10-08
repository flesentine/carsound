import Foundation

enum RepeatabilityAssessment: String, Equatable, Sendable {
    case noCrossSessionEvidence =
        "No cross-session evidence"
    case earlyEvidence =
        "Early cross-session evidence"
    case consistentReduction =
        "Consistent reduction"
    case consistentNeutral =
        "Consistent near-zero result"
    case consistentWorsening =
        "Consistent worsening"
    case variable =
        "Variable result"
    case mixedDirection =
        "Mixed direction"

    var isMature: Bool {
        switch self {
        case .consistentReduction,
             .consistentNeutral,
             .consistentWorsening,
             .variable,
             .mixedDirection:
            return true

        case .noCrossSessionEvidence,
             .earlyEvidence:
            return false
        }
    }
}

struct RepeatabilityCondition:
    Hashable,
    Identifiable,
    Sendable
{
    let routeSignature: String
    let frequencyTenthsHz: Int
    let phaseDegrees: Int
    let outputPercent: Int
    let headPosition:
        HeadPositionPreset?

    var id: String {
        [
            routeSignature,
            String(frequencyTenthsHz),
            String(phaseDegrees),
            String(outputPercent),
            headPosition?.rawValue ??
                "unlabeled"
        ]
        .joined(separator: "|")
    }

    var targetFrequencyHz: Double {
        Double(frequencyTenthsHz) /
            10
    }
}

struct RepeatabilitySessionResult:
    Equatable,
    Identifiable,
    Sendable
{
    let sessionID: UUID
    let comparisonCount: Int
    let meanReductionDB: Double
    let minimumReductionDB: Double
    let maximumReductionDB: Double
    let latestAt: Date

    var id: UUID {
        sessionID
    }
}

struct RepeatabilityGroup:
    Equatable,
    Identifiable,
    Sendable
{
    let condition: RepeatabilityCondition
    let comparisonCount: Int
    let sessionResults:
        [RepeatabilitySessionResult]
    let meanReductionDB: Double
    let standardDeviationDB: Double
    let minimumReductionDB: Double
    let maximumReductionDB: Double
    let rangeDB: Double
    let positiveSessionCount: Int
    let neutralSessionCount: Int
    let negativeSessionCount: Int
    let assessment: RepeatabilityAssessment
    let latestAt: Date

    var id: String {
        condition.id
    }

    var sessionCount: Int {
        sessionResults.count
    }
}

struct RepeatabilitySnapshot:
    Equatable,
    Sendable
{
    let comparisonEventCount: Int
    let analyzableComparisonCount: Int
    let excludedComparisonCount: Int
    let matchedConditionCount: Int
    let crossSessionConditionCount: Int
    let matureConditionCount: Int
    let consistentReductionCount: Int
    let groups: [RepeatabilityGroup]
}

enum RepeatabilityAnalytics {
    static let neutralDeadbandDB =
        0.5
    static let maximumStableStandardDeviationDB =
        1.0
    static let maximumStableRangeDB =
        2.0
    static let minimumMatureSessionCount =
        3

    static func snapshot(
        events: [StructuredLogEvent]
    ) -> RepeatabilitySnapshot {
        let comparisons =
            events.filter {
                $0.kind ==
                    .comparisonSaved
            }

        var grouped:
            [
                RepeatabilityCondition:
                    [StructuredLogEvent]
            ] = [:]
        var excluded = 0

        for event in comparisons {
            guard
                !ExperimentEvidenceQuality
                    .isContaminated(event),
                event.metrics[
                    "measured_reduction_db"
                ] != nil,
                let condition =
                    condition(for: event)
            else {
                excluded += 1
                continue
            }

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
                    $0.sessionCount ==
                        $1.sessionCount
                {
                    if
                        $0.comparisonCount ==
                            $1.comparisonCount
                    {
                        return $0.latestAt >
                            $1.latestAt
                    }

                    return $0.comparisonCount >
                        $1.comparisonCount
                }

                return $0.sessionCount >
                    $1.sessionCount
            }

        return RepeatabilitySnapshot(
            comparisonEventCount:
                comparisons.count,
            analyzableComparisonCount:
                comparisons.count -
                excluded,
            excludedComparisonCount:
                excluded,
            matchedConditionCount:
                groups.count,
            crossSessionConditionCount:
                groups.filter {
                    $0.sessionCount >= 2
                }.count,
            matureConditionCount:
                groups.filter {
                    $0.assessment
                        .isMature
                }.count,
            consistentReductionCount:
                groups.filter {
                    $0.assessment ==
                        .consistentReduction
                }.count,
            groups: groups
        )
    }

    static func condition(
        for event: StructuredLogEvent
    ) -> RepeatabilityCondition? {
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

        return RepeatabilityCondition(
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
                ),
            headPosition:
                HeadPositionSensitivityAnalytics
                    .position(
                        for: event
                    )
        )
    }

    static func assessment(
        sessionMeanReductionsDB:
            [Double]
    ) -> RepeatabilityAssessment {
        guard
            sessionMeanReductionsDB
                .count >= 2
        else {
            return .noCrossSessionEvidence
        }

        guard
            sessionMeanReductionsDB
                .count >=
                minimumMatureSessionCount
        else {
            return .earlyEvidence
        }

        let positive =
            sessionMeanReductionsDB
                .filter {
                    $0 >
                        neutralDeadbandDB
                }
                .count
        let negative =
            sessionMeanReductionsDB
                .filter {
                    $0 <
                        -neutralDeadbandDB
                }
                .count
        let neutral =
            sessionMeanReductionsDB.count -
                positive -
                negative

        if
            positive > 0 &&
            negative > 0
        {
            return .mixedDirection
        }

        let standardDeviation =
            sampleStandardDeviation(
                sessionMeanReductionsDB
            )
        let minimum =
            sessionMeanReductionsDB
                .min() ?? 0
        let maximum =
            sessionMeanReductionsDB
                .max() ?? 0
        let range =
            maximum - minimum

        guard
            standardDeviation <=
                maximumStableStandardDeviationDB,
            range <=
                maximumStableRangeDB
        else {
            return .variable
        }

        if
            positive ==
                sessionMeanReductionsDB
                    .count
        {
            return .consistentReduction
        }

        if
            negative ==
                sessionMeanReductionsDB
                    .count
        {
            return .consistentWorsening
        }

        if
            neutral ==
                sessionMeanReductionsDB
                    .count
        {
            return .consistentNeutral
        }

        return .variable
    }

    static func sampleStandardDeviation(
        _ values: [Double]
    ) -> Double {
        guard values.count > 1 else {
            return 0
        }

        let mean =
            values.reduce(0, +) /
            Double(values.count)
        let squaredDeviationSum =
            values.reduce(0) {
                partial,
                value in

                let difference =
                    value - mean

                return partial +
                    difference *
                    difference
            }

        return sqrt(
            squaredDeviationSum /
            Double(
                values.count - 1
            )
        )
    }

    private static func makeGroup(
        condition: RepeatabilityCondition,
        events: [StructuredLogEvent]
    ) -> RepeatabilityGroup {
        let bySession =
            Dictionary(
                grouping: events,
                by: {
                    $0.sessionID
                }
            )

        let sessionResults =
            bySession.compactMap {
                sessionID,
                sessionEvents ->
                    RepeatabilitySessionResult?
                in

                let ordered =
                    sessionEvents.sorted {
                        if
                            $0.recordedAt ==
                                $1.recordedAt
                        {
                            return $0.sequence <
                                $1.sequence
                        }

                        return $0.recordedAt <
                            $1.recordedAt
                    }

                let reductions =
                    ordered.compactMap {
                        $0.metrics[
                            "measured_reduction_db"
                        ]
                    }

                guard
                    !reductions.isEmpty
                else {
                    return nil
                }

                return RepeatabilitySessionResult(
                    sessionID:
                        sessionID,
                    comparisonCount:
                        reductions.count,
                    meanReductionDB:
                        average(reductions),
                    minimumReductionDB:
                        reductions.min() ?? 0,
                    maximumReductionDB:
                        reductions.max() ?? 0,
                    latestAt:
                        ordered.last?
                            .recordedAt ??
                        .distantPast
                )
            }
            .sorted {
                $0.latestAt >
                    $1.latestAt
            }

        let sessionMeans =
            sessionResults.map {
                $0.meanReductionDB
            }
        let mean =
            sessionMeans.isEmpty
            ? 0
            : average(
                sessionMeans
            )
        let minimum =
            sessionMeans.min() ?? 0
        let maximum =
            sessionMeans.max() ?? 0
        let positive =
            sessionMeans.filter {
                $0 >
                    neutralDeadbandDB
            }.count
        let negative =
            sessionMeans.filter {
                $0 <
                    -neutralDeadbandDB
            }.count
        let neutral =
            sessionMeans.count -
                positive -
                negative

        return RepeatabilityGroup(
            condition: condition,
            comparisonCount:
                events.count,
            sessionResults:
                sessionResults,
            meanReductionDB:
                mean,
            standardDeviationDB:
                sampleStandardDeviation(
                    sessionMeans
                ),
            minimumReductionDB:
                minimum,
            maximumReductionDB:
                maximum,
            rangeDB:
                maximum -
                minimum,
            positiveSessionCount:
                positive,
            neutralSessionCount:
                neutral,
            negativeSessionCount:
                negative,
            assessment:
                assessment(
                    sessionMeanReductionsDB:
                        sessionMeans
                ),
            latestAt:
                sessionResults
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
        let normalized =
            ((rounded % 360) + 360) %
                360

        return normalized
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
