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
    let comparisonSessionCount: Int
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
            "Evidence (Lab build 4.1+ when build metadata is available):",
            "- Sessions: \(sessionCount)",
            "- Sessions with A/B comparisons: \(comparisonSessionCount)",
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

private struct LabDecisionConfidenceEvidence {
    let scorePercent: Double?
    let coveragePercent: Double?
    let routeSignature: String?
}

enum LabGoNoGoAnalytics {
    static let minimumComparisonCount =
        10
    static let minimumSessionCount =
        3
    static let minimumConfidenceScorePercent =
        OverallConfidenceMath
            .moderateThreshold
    static let minimumEvidenceCoveragePercent =
        OverallConfidenceMath
            .minimumCoverageForAssessment *
        100
    static let minimumPositiveFrequenciesForBroadEvidence =
        2

    static func snapshot(
        events: [StructuredLogEvent],
        currentSessionID: UUID
    ) -> LabGoNoGoSnapshot {
        let decisionEvents =
            ExperimentEvidenceQuality
                .decisionEligibleEvents(
                    events
                )
        let dashboard =
            TestDashboardAnalytics
                .snapshot(
                    events:
                        decisionEvents,
                    scope: .allSaved,
                    currentSessionID:
                        currentSessionID
                )
        let repeatability =
            RepeatabilityAnalytics
                .snapshot(
                    events:
                        decisionEvents
                )
        let headPosition =
            HeadPositionSensitivityAnalytics
                .snapshot(
                    events:
                        decisionEvents
                )
        let frequency =
            FrequencyCoverageAnalytics
                .snapshot(
                    events:
                        decisionEvents
                )
        let eligibleComparisons =
            decisionEvents.filter {
                ExperimentEvidenceQuality
                    .isEligibleComparison($0)
            }
        let comparisonSessionCount =
            Set(
                eligibleComparisons
                    .map {
                        $0.sessionID
                    }
            ).count

        let qualifyingBroad =
            frequency.series.filter {
                $0.assessment == .broad &&
                $0.repeatedPositiveFrequencyCount >=
                    minimumPositiveFrequenciesForBroadEvidence
            }

        let coherentQualifyingBroad =
            qualifyingBroad.filter { series in
                guard
                    let position =
                        series.context
                            .headPosition
                else {
                    return false
                }

                let hasRepeatableReduction =
                    repeatability.groups
                        .contains {
                            $0.assessment ==
                                .consistentReduction &&
                            $0.condition
                                .routeSignature ==
                                series.context
                                    .routeSignature &&
                            $0.condition
                                .headPosition ==
                                position
                        }

                let hasSafePositionEvidence =
                    headPosition.groups
                        .contains {
                            $0.condition
                                .routeSignature ==
                                series.context
                                    .routeSignature &&
                            $0.positionCount >= 2 &&
                            $0.assessment !=
                                .directionReversal &&
                            $0.assessment !=
                                .high
                        }

                return hasRepeatableReduction &&
                    hasSafePositionEvidence
            }

        let coherentRoutes =
            Set(
                coherentQualifyingBroad
                    .map {
                        $0.context
                            .routeSignature
                    }
            )
        let confidenceEvidence =
            latestConfidenceEvidence(
                events:
                    decisionEvents,
                preferredRoutes:
                    coherentRoutes
            )

        let gates = [
            evidenceVolumeGate(
                comparisonCount:
                    eligibleComparisons.count,
                comparisonSessionCount:
                    comparisonSessionCount
            ),
            confidenceGate(
                confidenceEvidence,
                requiresPreferredRoute:
                    !coherentRoutes.isEmpty
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
                    coherentQualifyingBroad.count,
                repeatedBroadCount:
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
                eligibleComparisons.count,
            sessionCount:
                dashboard.sessionCount,
            comparisonSessionCount:
                comparisonSessionCount,
            latestConfidenceScorePercent:
                confidenceEvidence?
                    .scorePercent,
            latestEvidenceCoveragePercent:
                confidenceEvidence?
                    .coveragePercent,
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
                coherentQualifyingBroad.count
        )
    }

    private static func evidenceVolumeGate(
        comparisonCount: Int,
        comparisonSessionCount: Int
    ) -> LabDecisionGate {
        let comparisonsReady =
            comparisonCount >=
                minimumComparisonCount
        let sessionsReady =
            comparisonSessionCount >=
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
                "\(comparisonCount)/\(minimumComparisonCount) eligible A/B comparisons • \(comparisonSessionCount)/\(minimumSessionCount) comparison sessions",
            detail:
                "The final decision counts only saved A/B comparisons that have a measured reduction and are not flagged for microphone clipping or likely program interference. Those comparisons must also span separate measurement sessions."
        )
    }

    private static func confidenceGate(
        _ evidence:
            LabDecisionConfidenceEvidence?,
        requiresPreferredRoute: Bool
    ) -> LabDecisionGate {
        guard let evidence else {
            return LabDecisionGate(
                id: "overall_confidence",
                title: "Overall confidence",
                status:
                    .needsEvidence,
                summary:
                    requiresPreferredRoute
                    ? "No confidence snapshot for the coherent route"
                    : "No explicit confidence snapshot",
                detail:
                    requiresPreferredRoute
                    ? "Log a Confidence Snapshot while testing the same route that supplies the coherent repeatability, head-position, and frequency evidence."
                    : "Use Log Confidence Snapshot before making the final Lab decision. Incidental confidence context on other events does not count."
            )
        }

        guard
            let coverage =
                evidence.coveragePercent
        else {
            return LabDecisionGate(
                id: "overall_confidence",
                title: "Overall confidence",
                status:
                    .needsEvidence,
                summary:
                    "Snapshot coverage unavailable",
                detail:
                    "The selected confidence snapshot does not contain usable evidence-coverage data."
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
                            "Snapshot coverage %.0f%% • need %.0f%%",
                        coverage,
                        minimumEvidenceCoveragePercent
                    ),
                detail:
                    "Coverage below the existing confidence-assessment floor is treated as incomplete rather than as a negative result."
            )
        }

        guard
            let score =
                evidence.scorePercent
        else {
            return LabDecisionGate(
                id: "overall_confidence",
                title: "Overall confidence",
                status:
                    .needsEvidence,
                summary:
                    "Snapshot score unavailable",
                detail:
                    "The selected confidence snapshot does not contain a usable confidence score."
            )
        }

        let pass =
            score >=
                minimumConfidenceScorePercent
        let routeSuffix =
            evidence.routeSignature
                .map {
                    " • route " + $0
                } ??
            ""

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
                ) +
                routeSuffix,
            detail:
                pass
                ? "The explicit confidence snapshot meets the existing moderate-confidence threshold."
                : "With adequate evidence coverage, an explicit confidence snapshot below the existing 55% moderate threshold is a blocker for continuing the current approach unchanged."
        )
    }

    private static func latestConfidenceEvidence(
        events: [StructuredLogEvent],
        preferredRoutes: Set<String>
    ) -> LabDecisionConfidenceEvidence? {
        let snapshots =
            events
                .filter {
                    guard
                        $0.kind ==
                            .confidenceSnapshot
                    else {
                        return false
                    }

                    guard
                        !preferredRoutes.isEmpty
                    else {
                        return true
                    }

                    guard
                        let route =
                            $0.context
                                .routeSignature
                    else {
                        return false
                    }

                    return preferredRoutes
                        .contains(route)
                }
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

        guard
            let event =
                snapshots.last
        else {
            return nil
        }

        return LabDecisionConfidenceEvidence(
            scorePercent:
                event.metrics[
                    "score_percent"
                ] ??
                event.context
                    .confidenceScorePercent,
            coveragePercent:
                event.metrics[
                    "evidence_coverage_percent"
                ] ??
                event.context
                    .evidenceCoveragePercent,
            routeSignature:
                event.context
                    .routeSignature
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
        qualifyingBroadCount: Int,
        repeatedBroadCount: Int
    ) -> LabDecisionGate {
        if qualifyingBroadCount > 0 {
            return LabDecisionGate(
                id: "frequency_coverage",
                title: "Frequency breadth",
                status: .pass,
                summary:
                    "\(qualifyingBroadCount) coherent broad series with \(minimumPositiveFrequenciesForBroadEvidence)+ repeated-positive targets",
                detail:
                    "At least one labeled route/head-position series spans low, mid, and high ANC bands, repeats positive best-per-session evidence at multiple targets across sessions, and shares that route/position with mature repeatable reduction plus safe multi-position evidence."
            )
        }

        if repeatedBroadCount > 0 {
            return LabDecisionGate(
                id: "frequency_coverage",
                title: "Frequency breadth",
                status: .warning,
                summary:
                    "\(repeatedBroadCount) repeated-positive broad series, but evidence is not coherent",
                detail:
                    "Broad repeated-positive frequency evidence exists, but it does not share one labeled route/head-position context with both mature repeatable reduction and safe multi-position evidence."
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
                    "\(frequency.broadCoverageSeriesCount) broad series, but repeated positive breadth is weak",
                detail:
                    "Three-band coverage exists, but no broad series repeats positive best-per-session evidence at two or more target frequencies across separate sessions."
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
