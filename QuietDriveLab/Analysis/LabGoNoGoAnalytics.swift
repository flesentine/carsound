import Foundation

enum LabDecisionVerdict:
    String,
    Equatable,
    Sendable
{
    case go = "GO"
    case hold = "HOLD"
    case noGo = "NO-GO"

    var title: String {
        switch self {
        case .go:
            return "GO — continue prototyping"
        case .hold:
            return "HOLD — gather more evidence"
        case .noGo:
            return "NO-GO — current approach has a blocker"
        }
    }
}

enum LabDecisionGateStatus:
    String,
    Equatable,
    Sendable
{
    case pass = "Pass"
    case needsEvidence = "Needs evidence"
    case warning = "Warning"
    case blocker = "Blocker"
}

struct LabDecisionGate:
    Equatable,
    Identifiable,
    Sendable
{
    let id: String
    let title: String
    let status:
        LabDecisionGateStatus
    let summary: String
    let detail: String
}

struct LabGoNoGoSnapshot:
    Equatable,
    Sendable
{
    let verdict:
        LabDecisionVerdict
    let gates:
        [LabDecisionGate]
    let comparisonCount: Int
    let sessionCount: Int
    let latestConfidenceScorePercent:
        Double?
    let latestEvidenceCoveragePercent:
        Double?
    let matureRepeatabilityCount: Int
    let consistentReductionCount: Int
    let multiPositionConditionCount: Int
    let directionReversalCount: Int
    let broadFrequencySeriesCount: Int
    let qualifyingBroadFrequencySeriesCount:
        Int

    var passedGateCount: Int {
        gates.filter {
            $0.status == .pass
        }.count
    }

    var needsEvidenceGateCount: Int {
        gates.filter {
            $0.status ==
                .needsEvidence
        }.count
    }

    var warningGateCount: Int {
        gates.filter {
            $0.status == .warning
        }.count
    }

    var blockerGateCount: Int {
        gates.filter {
            $0.status == .blocker
        }.count
    }

    var reportText: String {
        var lines = [
            "QuietDrive Lab go/no-go report",
            "",
            "Verdict: " + verdict.title,
            "",
            "Evidence:",
            "- Sessions: \(sessionCount)",
            "- Saved A/B comparisons: \(comparisonCount)",
            "- Latest confidence: " +
                optionalPercent(
                    latestConfidenceScorePercent
                ),
            "- Latest evidence coverage: " +
                optionalPercent(
                    latestEvidenceCoveragePercent
                ),
            "- Mature repeatability groups: \(matureRepeatabilityCount)",
            "- Consistent-reduction groups: \(consistentReductionCount)",
            "- Multi-position conditions: \(multiPositionConditionCount)",
            "- Head-position direction reversals: \(directionReversalCount)",
            "- Broad frequency series: \(broadFrequencySeriesCount)",
            "- Qualifying broad frequency series: \(qualifyingBroadFrequencySeriesCount)",
            "",
            "Decision gates:"
        ]

        for gate in gates {
            lines.append(
                "- [\(gate.status.rawValue)] \(gate.title): \(gate.summary)"
            )
        }

        lines.append("")
        lines.append(
            "Interpretation: GO means the saved Lab evidence is strong enough to justify continued prototype engineering. It does not establish production-ready active noise cancellation, regulatory compliance, safe unattended use, or performance across unmeasured vehicles and occupants."
        )

        return lines.joined(
            separator: "\n"
        )
    }

    private func optionalPercent(
        _ value: Double?
    ) -> String {
        guard let value else {
            return "unavailable"
        }

        return String(
            format: "%.0f%%",
            value
        )
    }
}

enum LabGoNoGoAnalytics {
    static let minimumComparisonCount =
        10
    static let minimumSessionCount =
        3
    static let minimumConfidenceScorePercent =
        55.0
    static let minimumEvidenceCoveragePercent =
        60.0
    static let minimumPositiveFrequenciesForBroadEvidence =
        2

    static func snapshot(
        events: [StructuredLogEvent],
        currentSessionID: UUID
    ) -> LabGoNoGoSnapshot {
        let dashboard =
            TestDashboardAnalytics
                .snapshot(
                    events: events,
                    scope: .allSaved,
                    currentSessionID:
                        currentSessionID
                )
        let repeatability =
            RepeatabilityAnalytics
                .snapshot(
                    events: events
                )
        let headPosition =
            HeadPositionSensitivityAnalytics
                .snapshot(
                    events: events
                )
        let frequency =
            FrequencyCoverageAnalytics
                .snapshot(
                    events: events
                )

        let qualifyingBroad =
            frequency.series.filter {
                $0.assessment == .broad &&
                $0.positiveFrequencyCount >=
                    minimumPositiveFrequenciesForBroadEvidence
            }

        let gates = [
            evidenceVolumeGate(
                dashboard
            ),
            confidenceGate(
                dashboard
            ),
            repeatabilityGate(
                repeatability
            ),
            headPositionGate(
                headPosition
            ),
            frequencyCoverageGate(
                frequency,
                qualifyingBroadCount:
                    qualifyingBroad.count
            )
        ]

        let verdict:
            LabDecisionVerdict

        if
            gates.contains(
                where: {
                    $0.status ==
                        .blocker
                }
            )
        {
            verdict = .noGo
        } else if
            gates.allSatisfy({
                $0.status == .pass
            })
        {
            verdict = .go
        } else {
            verdict = .hold
        }

        return LabGoNoGoSnapshot(
            verdict: verdict,
            gates: gates,
            comparisonCount:
                dashboard.comparisonCount,
            sessionCount:
                dashboard.sessionCount,
            latestConfidenceScorePercent:
                dashboard
                    .latestConfidenceScorePercent,
            latestEvidenceCoveragePercent:
                dashboard
                    .latestEvidenceCoveragePercent,
            matureRepeatabilityCount:
                repeatability
                    .matureConditionCount,
            consistentReductionCount:
                repeatability
                    .consistentReductionCount,
            multiPositionConditionCount:
                headPosition
                    .multiPositionConditionCount,
            directionReversalCount:
                headPosition
                    .directionReversalCount,
            broadFrequencySeriesCount:
                frequency
                    .broadCoverageSeriesCount,
            qualifyingBroadFrequencySeriesCount:
                qualifyingBroad.count
        )
    }

    private static func evidenceVolumeGate(
        _ dashboard:
            TestDashboardSnapshot
    ) -> LabDecisionGate {
        let comparisonsReady =
            dashboard.comparisonCount >=
                minimumComparisonCount
        let sessionsReady =
            dashboard.sessionCount >=
                minimumSessionCount
        let status:
            LabDecisionGateStatus =
                comparisonsReady &&
                sessionsReady
                ? .pass
                : .needsEvidence

        return LabDecisionGate(
            id: "evidence_volume",
            title: "Evidence volume",
            status: status,
            summary:
                "\(dashboard.comparisonCount)/\(minimumComparisonCount) A/B comparisons • \(dashboard.sessionCount)/\(minimumSessionCount) sessions",
            detail:
                "The final decision needs enough saved comparisons and separate app sessions to avoid treating one tuning run as independent evidence."
        )
    }

    private static func confidenceGate(
        _ dashboard:
            TestDashboardSnapshot
    ) -> LabDecisionGate {
        guard
            let coverage =
                dashboard
                    .latestEvidenceCoveragePercent
        else {
            return LabDecisionGate(
                id: "overall_confidence",
                title: "Overall confidence",
                status:
                    .needsEvidence,
                summary:
                    "No saved confidence context",
                detail:
                    "Save evidence with an assessed confidence snapshot before making the final Lab decision."
            )
        }

        guard
            coverage >=
                minimumEvidenceCoveragePercent
        else {
            return LabDecisionGate(
                id: "overall_confidence",
                title: "Overall confidence",
                status:
                    .needsEvidence,
                summary:
                    String(
                        format:
                            "Evidence coverage %.0f%% • need %.0f%%",
                        coverage,
                        minimumEvidenceCoveragePercent
                    ),
                detail:
                    "Coverage below the existing confidence-assessment floor is treated as incomplete rather than as a negative result."
            )
        }

        guard
            let score =
                dashboard
                    .latestConfidenceScorePercent
        else {
            return LabDecisionGate(
                id: "overall_confidence",
                title: "Overall confidence",
                status:
                    .needsEvidence,
                summary:
                    "Confidence score unavailable",
                detail:
                    "Evidence coverage exists, but no usable latest confidence score is available."
            )
        }

        let pass =
            score >=
                minimumConfidenceScorePercent

        return LabDecisionGate(
            id: "overall_confidence",
            title: "Overall confidence",
            status:
                pass
                ? .pass
                : .blocker,
            summary:
                String(
                    format:
                        "%.0f%% confidence • %.0f%% coverage",
                    score,
                    coverage
                ),
            detail:
                pass
                ? "The latest assessed confidence meets the existing moderate-confidence threshold."
                : "With adequate evidence coverage, a confidence score below the existing 55% moderate threshold is a blocker for continuing the current approach unchanged."
        )
    }

    private static func repeatabilityGate(
        _ repeatability:
            RepeatabilitySnapshot
    ) -> LabDecisionGate {
        if
            repeatability
                .consistentReductionCount >
                0
        {
            return LabDecisionGate(
                id: "repeatability",
                title: "Cross-session repeatability",
                status: .pass,
                summary:
                    "\(repeatability.consistentReductionCount) mature consistent-reduction group(s)",
                detail:
                    "At least one matched condition produced a tight positive reduction across three or more separate sessions."
            )
        }

        if
            repeatability
                .matureConditionCount ==
                0
        {
            return LabDecisionGate(
                id: "repeatability",
                title: "Cross-session repeatability",
                status:
                    .needsEvidence,
                summary:
                    "No mature 3-session condition",
                detail:
                    "Repeatability cannot pass until at least one matched condition reaches the existing three-session maturity threshold."
            )
        }

        return LabDecisionGate(
            id: "repeatability",
            title: "Cross-session repeatability",
            status: .blocker,
            summary:
                "\(repeatability.matureConditionCount) mature group(s), none consistently reduce",
            detail:
                "Mature repeatability evidence exists but none of those conditions qualify as a consistent reduction. That is a blocker for the current cancellation approach."
        )
    }

    private static func headPositionGate(
        _ headPosition:
            HeadPositionSensitivitySnapshot
    ) -> LabDecisionGate {
        guard
            headPosition
                .multiPositionConditionCount >
                0
        else {
            return LabDecisionGate(
                id: "head_position",
                title: "Head-position robustness",
                status:
                    .needsEvidence,
                summary:
                    "No matched 2+ position condition",
                detail:
                    "Measure at least one matched setting at two or more listener positions before generalizing beyond one listening spot."
            )
        }

        if
            headPosition
                .directionReversalCount >
                0
        {
            return LabDecisionGate(
                id: "head_position",
                title: "Head-position robustness",
                status: .blocker,
                summary:
                    "\(headPosition.directionReversalCount) direction reversal(s)",
                detail:
                    "At least one matched setting reduces the target at one head position but worsens it at another beyond the ±0.5 dB deadband. That blocks a generalized cabin-cancellation GO."
            )
        }

        if
            headPosition
                .highSensitivityCount >
                0
        {
            return LabDecisionGate(
                id: "head_position",
                title: "Head-position robustness",
                status: .warning,
                summary:
                    "\(headPosition.highSensitivityCount) high-sensitivity condition(s)",
                detail:
                    "No direction reversal was found, but >3 dB position spread means the effect is still strongly location-dependent."
            )
        }

        return LabDecisionGate(
            id: "head_position",
            title: "Head-position robustness",
            status: .pass,
            summary:
                "\(headPosition.multiPositionConditionCount) multi-position condition(s) • no reversal",
            detail:
                "The tested matched settings do not show a head-position direction reversal or >3 dB high-sensitivity condition."
        )
    }

    private static func frequencyCoverageGate(
        _ frequency:
            FrequencyCoverageSnapshot,
        qualifyingBroadCount: Int
    ) -> LabDecisionGate {
        if qualifyingBroadCount > 0 {
            return LabDecisionGate(
                id: "frequency_coverage",
                title: "Frequency breadth",
                status: .pass,
                summary:
                    "\(qualifyingBroadCount) broad series with \(minimumPositiveFrequenciesForBroadEvidence)+ positive targets",
                detail:
                    "At least one route/head-position series spans low, mid, and high ANC bands and shows positive best-per-session evidence at multiple targets."
            )
        }

        if
            frequency
                .broadCoverageSeriesCount >
                0
        {
            return LabDecisionGate(
                id: "frequency_coverage",
                title: "Frequency breadth",
                status: .warning,
                summary:
                    "\(frequency.broadCoverageSeriesCount) broad series, but positive breadth is weak",
                detail:
                    "Three-band coverage exists, but no broad series currently has positive best-per-session evidence at two or more target frequencies."
            )
        }

        if
            frequency
                .multiFrequencySeriesCount >
                0
        {
            return LabDecisionGate(
                id: "frequency_coverage",
                title: "Frequency breadth",
                status:
                    .needsEvidence,
                summary:
                    "\(frequency.multiFrequencySeriesCount) multi-target series • none broad",
                detail:
                    "Multi-frequency evidence exists, but no single route/head-position series spans low, mid, and high bands."
            )
        }

        return LabDecisionGate(
            id: "frequency_coverage",
            title: "Frequency breadth",
            status:
                .needsEvidence,
            summary:
                "No multi-target series",
            detail:
                "The final decision needs more than one target frequency under the same route/head-position context."
        )
    }
}
