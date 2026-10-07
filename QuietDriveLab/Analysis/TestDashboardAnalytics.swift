import Foundation

enum TestDashboardScope: String, CaseIterable, Identifiable, Sendable {
    case allSaved
    case currentSession

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .allSaved:
            return "All saved"
        case .currentSession:
            return "Current session"
        }
    }
}

struct TestDashboardWorkflowSummary: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let completedCount: Int
    let failedCount: Int
}

struct TestDashboardSessionSummary: Equatable, Identifiable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: TimeInterval
    let eventCount: Int
    let comparisonCount: Int
    let bestReductionDB: Double?
    let failureCount: Int
    let safetyMuteCount: Int
    let distinctRouteCount: Int
    let distinctFrequencyCount: Int
    let latestConfidenceScorePercent: Double?
    let latestEvidenceCoveragePercent: Double?
    let latestConfidenceLevel: String?
    let appBuild: String?
    let isCurrentSession: Bool
}

struct TestDashboardSnapshot: Equatable, Sendable {
    let scope: TestDashboardScope
    let eventCount: Int
    let sessionCount: Int
    let distinctRouteCount: Int
    let distinctFrequencyCount: Int

    let comparisonCount: Int
    let positiveReductionCount: Int
    let averageReductionDB: Double?
    let bestReductionDB: Double?

    let confidenceSnapshotCount: Int
    let averageConfidenceSnapshotScorePercent: Double?
    let latestConfidenceScorePercent: Double?
    let latestEvidenceCoveragePercent: Double?
    let latestConfidenceLevel: String?

    let failureCount: Int
    let safetyMuteCount: Int
    let workflowSummaries: [TestDashboardWorkflowSummary]
    let recentSessions: [TestDashboardSessionSummary]
}

enum TestDashboardAnalytics {
    static func snapshot(
        events: [StructuredLogEvent],
        scope: TestDashboardScope,
        currentSessionID: UUID
    ) -> TestDashboardSnapshot {
        let selected =
            selectedEvents(
                events,
                scope: scope,
                currentSessionID:
                    currentSessionID
            )
            .sorted {
                if
                    $0.recordedAt ==
                        $1.recordedAt
                {
                    if
                        $0.sessionID ==
                            $1.sessionID
                    {
                        return $0.sequence <
                            $1.sequence
                    }

                    return $0.sessionID
                        .uuidString <
                        $1.sessionID
                            .uuidString
                }

                return $0.recordedAt <
                    $1.recordedAt
            }

        let comparisons =
            selected.filter {
                $0.kind ==
                    .comparisonSaved
            }
        let reductions =
            comparisons.compactMap {
                $0.metrics[
                    "measured_reduction_db"
                ]
            }

        let confidenceSnapshots =
            selected.filter {
                $0.kind ==
                    .confidenceSnapshot
            }
        let confidenceScores =
            confidenceSnapshots.compactMap {
                $0.metrics[
                    "score_percent"
                ] ??
                $0.context
                    .confidenceScorePercent
            }

        let latestConfidenceEvent =
            selected.reversed()
                .first {
                    $0.context
                        .confidenceScorePercent != nil
                }

        let sessionGroups =
            Dictionary(
                grouping: selected,
                by: {
                    $0.sessionID
                }
            )

        let sessions =
            sessionGroups
                .map {
                    makeSessionSummary(
                        sessionID: $0.key,
                        events: $0.value,
                        currentSessionID:
                            currentSessionID
                    )
                }
                .sorted {
                    if
                        $0.endedAt ==
                            $1.endedAt
                    {
                        return $0.startedAt >
                            $1.startedAt
                    }

                    return $0.endedAt >
                        $1.endedAt
                }

        return TestDashboardSnapshot(
            scope: scope,
            eventCount:
                selected.count,
            sessionCount:
                sessionGroups.count,
            distinctRouteCount:
                distinctRoutes(
                    in: selected
                ).count,
            distinctFrequencyCount:
                distinctFrequencies(
                    in: selected
                ).count,
            comparisonCount:
                comparisons.count,
            positiveReductionCount:
                reductions.filter {
                    $0 > 0
                }.count,
            averageReductionDB:
                average(reductions),
            bestReductionDB:
                reductions.max(),
            confidenceSnapshotCount:
                confidenceSnapshots.count,
            averageConfidenceSnapshotScorePercent:
                average(
                    confidenceScores
                ),
            latestConfidenceScorePercent:
                latestConfidenceEvent?
                    .context
                    .confidenceScorePercent,
            latestEvidenceCoveragePercent:
                latestConfidenceEvent?
                    .context
                    .evidenceCoveragePercent,
            latestConfidenceLevel:
                latestConfidenceEvent?
                    .context
                    .confidenceLevel,
            failureCount:
                failureCount(
                    in: selected
                ),
            safetyMuteCount:
                selected.filter {
                    $0.kind ==
                        .safetyMute
                }.count,
            workflowSummaries:
                workflowSummaries(
                    events: selected
                ),
            recentSessions:
                Array(
                    sessions.prefix(8)
                )
        )
    }

    static func selectedEvents(
        _ events: [StructuredLogEvent],
        scope: TestDashboardScope,
        currentSessionID: UUID
    ) -> [StructuredLogEvent] {
        switch scope {
        case .allSaved:
            return events
        case .currentSession:
            return events.filter {
                $0.sessionID ==
                    currentSessionID
            }
        }
    }

    private static func makeSessionSummary(
        sessionID: UUID,
        events: [StructuredLogEvent],
        currentSessionID: UUID
    ) -> TestDashboardSessionSummary {
        let ordered =
            events.sorted {
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

        let startedAt =
            ordered.first?
                .recordedAt ??
            .distantPast
        let endedAt =
            ordered.last?
                .recordedAt ??
            startedAt
        let comparisons =
            ordered.filter {
                $0.kind ==
                    .comparisonSaved
            }
        let reductions =
            comparisons.compactMap {
                $0.metrics[
                    "measured_reduction_db"
                ]
            }
        let latestConfidence =
            ordered.reversed()
                .first {
                    $0.context
                        .confidenceScorePercent != nil
                }
        let sessionStart =
            ordered.first {
                $0.kind ==
                    .sessionStarted
            }

        return TestDashboardSessionSummary(
            id: sessionID,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds:
                max(
                    0,
                    endedAt
                        .timeIntervalSince(
                            startedAt
                        )
                ),
            eventCount:
                ordered.count,
            comparisonCount:
                comparisons.count,
            bestReductionDB:
                reductions.max(),
            failureCount:
                failureCount(
                    in: ordered
                ),
            safetyMuteCount:
                ordered.filter {
                    $0.kind ==
                        .safetyMute
                }.count,
            distinctRouteCount:
                distinctRoutes(
                    in: ordered
                ).count,
            distinctFrequencyCount:
                distinctFrequencies(
                    in: ordered
                ).count,
            latestConfidenceScorePercent:
                latestConfidence?
                    .context
                    .confidenceScorePercent,
            latestEvidenceCoveragePercent:
                latestConfidence?
                    .context
                    .evidenceCoveragePercent,
            latestConfidenceLevel:
                latestConfidence?
                    .context
                    .confidenceLevel,
            appBuild:
                sessionStart?
                    .text["app_build"],
            isCurrentSession:
                sessionID ==
                    currentSessionID
        )
    }

    private static func workflowSummaries(
        events: [StructuredLogEvent]
    ) -> [TestDashboardWorkflowSummary] {
        [
            workflow(
                id: "route_tests",
                title: "Route tests",
                events: events,
                completionKind:
                    .routeTestCaptured
            ),
            workflow(
                id: "calibration",
                title: "Calibration",
                events: events,
                completionKind:
                    .calibrationCompleted,
                directFailureKind:
                    .calibrationFailed
            ),
            workflow(
                id: "comparisons",
                title: "A/B comparisons",
                events: events,
                completionKind:
                    .comparisonSaved
            ),
            workflow(
                id: "phase_sweep",
                title: "Phase sweeps",
                events: events,
                completionKind:
                    .phaseSweepCompleted,
                workflowFailureName:
                    "phase_sweep"
            ),
            workflow(
                id: "phase_refinement",
                title: "Fine phase",
                events: events,
                completionKind:
                    .phaseRefinementCompleted,
                workflowFailureName:
                    "phase_refinement"
            ),
            workflow(
                id: "amplitude_search",
                title: "Amplitude search",
                events: events,
                completionKind:
                    .amplitudeSearchCompleted,
                workflowFailureName:
                    "amplitude_search"
            ),
            workflow(
                id: "adaptive",
                title: "Adaptive control",
                events: events,
                completionKind:
                    .adaptiveStopped,
                directFailureKind:
                    .adaptiveFailed
            ),
            workflow(
                id: "bluetooth_jitter",
                title: "Bluetooth jitter",
                events: events,
                completionKind:
                    .bluetoothJitterCompleted,
                workflowFailureName:
                    "bluetooth_jitter"
            ),
            workflow(
                id: "sound_vibration",
                title: "Sound/vibration",
                events: events,
                completionKind:
                    .soundVibrationCorrelationCompleted,
                workflowFailureName:
                    "sound_vibration_correlation"
            )
        ]
    }

    private static func workflow(
        id: String,
        title: String,
        events: [StructuredLogEvent],
        completionKind: StructuredLogEventKind,
        directFailureKind: StructuredLogEventKind? = nil,
        workflowFailureName: String? = nil
    ) -> TestDashboardWorkflowSummary {
        let completed =
            events.filter {
                $0.kind ==
                    completionKind
            }.count

        let directFailures =
            directFailureKind.map { kind in
                events.filter {
                    $0.kind == kind
                }.count
            } ?? 0

        let genericFailures =
            workflowFailureName.map { name in
                events.filter {
                    $0.kind ==
                        .workflowFailed &&
                    $0.text[
                        "workflow"
                    ] == name
                }.count
            } ?? 0

        return TestDashboardWorkflowSummary(
            id: id,
            title: title,
            completedCount:
                completed,
            failedCount:
                directFailures +
                genericFailures
        )
    }

    private static func failureCount(
        in events: [StructuredLogEvent]
    ) -> Int {
        events.filter {
            switch $0.kind {
            case .calibrationFailed,
                 .adaptiveFailed,
                 .workflowFailed:
                return true

            default:
                return false
            }
        }.count
    }

    private static func distinctRoutes(
        in events: [StructuredLogEvent]
    ) -> Set<String> {
        Set(
            events.compactMap {
                $0.context
                    .routeSignature
            }
        )
    }

    private static func distinctFrequencies(
        in events: [StructuredLogEvent]
    ) -> Set<Double> {
        Set(
            events.compactMap {
                $0.context
                    .targetFrequencyHz
            }
        )
    }

    private static func average(
        _ values: [Double]
    ) -> Double? {
        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(
            0,
            +
        ) /
        Double(values.count)
    }
}
