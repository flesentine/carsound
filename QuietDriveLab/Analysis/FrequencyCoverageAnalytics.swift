import Foundation

enum FrequencyCoverageBand:
    String,
    CaseIterable,
    Hashable,
    Identifiable,
    Sendable
{
    case low
    case mid
    case high

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .low:
            return "Low"
        case .mid:
            return "Mid"
        case .high:
            return "High"
        }
    }

    var rangeText: String {
        switch self {
        case .low:
            return "30–69 Hz"
        case .mid:
            return "70–119 Hz"
        case .high:
            return "120–200 Hz"
        }
    }

    static func band(
        for frequencyHz: Double
    ) -> FrequencyCoverageBand? {
        guard
            frequencyHz >= 30,
            frequencyHz <= 200
        else {
            return nil
        }

        if frequencyHz < 70 {
            return .low
        }

        if frequencyHz < 120 {
            return .mid
        }

        return .high
    }
}

enum FrequencyCoverageAssessment:
    String,
    Equatable,
    Sendable
{
    case singleTarget =
        "Single target"
    case narrow =
        "Narrow coverage"
    case partial =
        "Partial coverage"
    case broad =
        "Broad coverage"
}

struct FrequencyCoverageContext:
    Hashable,
    Identifiable,
    Sendable
{
    let routeSignature: String
    let headPosition:
        HeadPositionPreset?

    var id: String {
        routeSignature +
            "|" +
            (
                headPosition?
                    .rawValue ??
                "unlabeled"
            )
    }
}

struct FrequencyCoverageSessionResult:
    Equatable,
    Identifiable,
    Sendable
{
    let sessionID: UUID
    let comparisonCount: Int
    let bestReductionDB: Double
    let averageReductionDB: Double
    let latestAt: Date

    var id: UUID {
        sessionID
    }
}

struct FrequencyCoverageTargetResult:
    Equatable,
    Identifiable,
    Sendable
{
    let frequencyHz: Double
    let band: FrequencyCoverageBand
    let comparisonCount: Int
    let sessionResults:
        [FrequencyCoverageSessionResult]
    let sessionBalancedBestReductionDB:
        Double
    let sessionBalancedAverageReductionDB:
        Double
    let bestObservedReductionDB: Double
    let positiveBestSessionCount: Int
    let neutralBestSessionCount: Int
    let negativeBestSessionCount: Int
    let latestAt: Date

    var id: Int {
        Int(frequencyHz.rounded())
    }

    var sessionCount: Int {
        sessionResults.count
    }
}

struct FrequencyCoverageSeries:
    Equatable,
    Identifiable,
    Sendable
{
    let context:
        FrequencyCoverageContext
    let frequencyResults:
        [FrequencyCoverageTargetResult]
    let comparisonCount: Int
    let sessionCount: Int
    let bandsCovered:
        Set<FrequencyCoverageBand>
    let minimumFrequencyHz: Double
    let maximumFrequencyHz: Double
    let positiveFrequencyCount: Int
    let crossSessionFrequencyCount: Int
    let assessment:
        FrequencyCoverageAssessment
    let latestAt: Date

    var id: String {
        context.id
    }

    var frequencyCount: Int {
        frequencyResults.count
    }

    var frequencySpanHz: Double {
        maximumFrequencyHz -
            minimumFrequencyHz
    }
}

struct FrequencyCoverageSnapshot:
    Equatable,
    Sendable
{
    let comparisonEventCount: Int
    let analyzableComparisonCount: Int
    let excludedComparisonCount: Int
    let distinctFrequencyCount: Int
    let seriesCount: Int
    let multiFrequencySeriesCount: Int
    let broadCoverageSeriesCount: Int
    let maximumFrequencySpanHz: Double?
    let series:
        [FrequencyCoverageSeries]
}

enum FrequencyCoverageAnalytics {
    static let recommendedTargetsHz:
        [Double] = [
            40,
            60,
            80,
            100,
            120,
            160,
            200
        ]

    static func snapshot(
        events: [StructuredLogEvent]
    ) -> FrequencyCoverageSnapshot {
        let comparisons =
            events.filter {
                $0.kind ==
                    .comparisonSaved
            }

        var grouped:
            [
                FrequencyCoverageContext:
                    [StructuredLogEvent]
            ] = [:]
        var excluded = 0
        var distinctFrequencies =
            Set<Int>()

        for event in comparisons {
            guard
                event.metrics[
                    "measured_reduction_db"
                ] != nil,
                let context =
                    coverageContext(
                        for: event
                    ),
                let frequency =
                    normalizedFrequencyHz(
                        for: event
                    ),
                FrequencyCoverageBand
                    .band(
                        for: frequency
                    ) != nil
            else {
                excluded += 1
                continue
            }

            distinctFrequencies.insert(
                Int(frequency.rounded())
            )
            grouped[
                context,
                default: []
            ].append(event)
        }

        let series =
            grouped.map {
                makeSeries(
                    context: $0.key,
                    events: $0.value
                )
            }
            .filter {
                !$0.frequencyResults
                    .isEmpty
            }
            .sorted {
                if
                    $0.frequencyCount ==
                        $1.frequencyCount
                {
                    if
                        $0.frequencySpanHz ==
                            $1.frequencySpanHz
                    {
                        return $0.latestAt >
                            $1.latestAt
                    }

                    return $0.frequencySpanHz >
                        $1.frequencySpanHz
                }

                return $0.frequencyCount >
                    $1.frequencyCount
            }

        return FrequencyCoverageSnapshot(
            comparisonEventCount:
                comparisons.count,
            analyzableComparisonCount:
                comparisons.count -
                excluded,
            excludedComparisonCount:
                excluded,
            distinctFrequencyCount:
                distinctFrequencies
                    .count,
            seriesCount:
                series.count,
            multiFrequencySeriesCount:
                series.filter {
                    $0.frequencyCount >= 2
                }.count,
            broadCoverageSeriesCount:
                series.filter {
                    $0.assessment ==
                        .broad
                }.count,
            maximumFrequencySpanHz:
                series
                    .filter {
                        $0.frequencyCount >= 2
                    }
                    .map {
                        $0.frequencySpanHz
                    }
                    .max(),
            series: series
        )
    }

    static func assessment(
        frequencyCount: Int,
        bandsCovered:
            Set<FrequencyCoverageBand>
    ) -> FrequencyCoverageAssessment {
        guard frequencyCount >= 2 else {
            return .singleTarget
        }

        if bandsCovered.count == 1 {
            return .narrow
        }

        if
            bandsCovered.count ==
                FrequencyCoverageBand
                    .allCases
                    .count,
            frequencyCount >= 3
        {
            return .broad
        }

        return .partial
    }

    private static func coverageContext(
        for event: StructuredLogEvent
    ) -> FrequencyCoverageContext? {
        guard
            let route =
                event.context
                    .routeSignature,
            !route.isEmpty
        else {
            return nil
        }

        return FrequencyCoverageContext(
            routeSignature: route,
            headPosition:
                HeadPositionSensitivityAnalytics
                    .position(
                        for: event
                    )
        )
    }

    private static func normalizedFrequencyHz(
        for event: StructuredLogEvent
    ) -> Double? {
        guard
            let frequency =
                event.context
                    .targetFrequencyHz,
            frequency.isFinite
        else {
            return nil
        }

        return frequency.rounded()
    }

    private static func makeSeries(
        context:
            FrequencyCoverageContext,
        events: [StructuredLogEvent]
    ) -> FrequencyCoverageSeries {
        let byFrequency =
            Dictionary(
                grouping: events
            ) {
                Int(
                    (
                        $0.context
                            .targetFrequencyHz ??
                        .nan
                    ).rounded()
                )
            }

        let frequencyResults =
            byFrequency.compactMap {
                frequencyKey,
                frequencyEvents ->
                    FrequencyCoverageTargetResult?
                in

                let frequency =
                    Double(
                        frequencyKey
                    )

                guard
                    let band =
                        FrequencyCoverageBand
                            .band(
                                for: frequency
                            )
                else {
                    return nil
                }

                let bySession =
                    Dictionary(
                        grouping:
                            frequencyEvents,
                        by: {
                            $0.sessionID
                        }
                    )

                let sessionResults =
                    bySession.compactMap {
                        sessionID,
                        sessionEvents ->
                            FrequencyCoverageSessionResult?
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

                        return FrequencyCoverageSessionResult(
                            sessionID:
                                sessionID,
                            comparisonCount:
                                reductions.count,
                            bestReductionDB:
                                reductions.max() ??
                                0,
                            averageReductionDB:
                                average(
                                    reductions
                                ),
                            latestAt:
                                sessionEvents
                                    .map {
                                        $0.recordedAt
                                    }
                                    .max() ??
                                .distantPast
                        )
                    }
                    .sorted {
                        $0.latestAt >
                            $1.latestAt
                    }

                guard
                    !sessionResults
                        .isEmpty
                else {
                    return nil
                }

                let sessionBests =
                    sessionResults.map {
                        $0.bestReductionDB
                    }
                let sessionAverages =
                    sessionResults.map {
                        $0.averageReductionDB
                    }
                let positive =
                    sessionBests.filter {
                        $0 >
                            RepeatabilityAnalytics
                                .neutralDeadbandDB
                    }.count
                let negative =
                    sessionBests.filter {
                        $0 <
                            -RepeatabilityAnalytics
                                .neutralDeadbandDB
                    }.count
                let neutral =
                    sessionBests.count -
                        positive -
                        negative

                return FrequencyCoverageTargetResult(
                    frequencyHz:
                        frequency,
                    band: band,
                    comparisonCount:
                        frequencyEvents.count,
                    sessionResults:
                        sessionResults,
                    sessionBalancedBestReductionDB:
                        average(
                            sessionBests
                        ),
                    sessionBalancedAverageReductionDB:
                        average(
                            sessionAverages
                        ),
                    bestObservedReductionDB:
                        frequencyEvents
                            .compactMap {
                                $0.metrics[
                                    "measured_reduction_db"
                                ]
                            }
                            .max() ??
                        0,
                    positiveBestSessionCount:
                        positive,
                    neutralBestSessionCount:
                        neutral,
                    negativeBestSessionCount:
                        negative,
                    latestAt:
                        sessionResults
                            .map {
                                $0.latestAt
                            }
                            .max() ??
                        .distantPast
                )
            }
            .sorted {
                $0.frequencyHz <
                    $1.frequencyHz
            }

        let bands =
            Set(
                frequencyResults.map {
                    $0.band
                }
            )
        let sessions =
            Set(
                frequencyResults
                    .flatMap {
                        $0.sessionResults
                    }
                    .map {
                        $0.sessionID
                    }
            )
        let minimum =
            frequencyResults
                .map {
                    $0.frequencyHz
                }
                .min() ??
            0
        let maximum =
            frequencyResults
                .map {
                    $0.frequencyHz
                }
                .max() ??
            0

        return FrequencyCoverageSeries(
            context: context,
            frequencyResults:
                frequencyResults,
            comparisonCount:
                frequencyResults
                    .reduce(0) {
                        $0 +
                        $1.comparisonCount
                    },
            sessionCount:
                sessions.count,
            bandsCovered:
                bands,
            minimumFrequencyHz:
                minimum,
            maximumFrequencyHz:
                maximum,
            positiveFrequencyCount:
                frequencyResults
                    .filter {
                        $0.sessionBalancedBestReductionDB >
                            RepeatabilityAnalytics
                                .neutralDeadbandDB
                    }
                    .count,
            crossSessionFrequencyCount:
                frequencyResults
                    .filter {
                        $0.sessionCount >= 2
                    }
                    .count,
            assessment:
                assessment(
                    frequencyCount:
                        frequencyResults.count,
                    bandsCovered:
                        bands
                ),
            latestAt:
                frequencyResults
                    .map {
                        $0.latestAt
                    }
                    .max() ??
                .distantPast
        )
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
