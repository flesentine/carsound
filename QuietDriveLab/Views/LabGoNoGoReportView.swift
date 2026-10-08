import Foundation
import SwiftUI

struct LabGoNoGoReportView: View {
    @Environment(StructuredLogModel.self)
    private var structuredLog

    private var snapshot:
        LabGoNoGoSnapshot
    {
        LabGoNoGoAnalytics
            .snapshot(
                events:
                    structuredLog.events,
                currentSessionID:
                    structuredLog
                        .currentSessionID
            )
    }

    private let metricColumns = [
        GridItem(
            .flexible(),
            spacing: 12
        ),
        GridItem(
            .flexible(),
            spacing: 12
        )
    ]

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                verdictCard
                evidenceCard
                gatesCard
                interpretationCard
                shareCard
            }
            .padding(20)
        }
        .navigationTitle(
            "Lab Go / No-Go"
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
    }

    private var verdictCard: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Label(
                "Final Lab Decision",
                systemImage:
                    verdictSymbol
            )
            .font(.headline)

            Text(
                snapshot.verdict.rawValue
            )
            .font(
                .largeTitle
                    .weight(.bold)
            )

            Text(
                snapshot.verdict.title
            )
            .font(
                .title3
                    .weight(.semibold)
            )

            Text(
                verdictExplanation
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            HStack {
                Label(
                    "\(snapshot.passedGateCount) pass",
                    systemImage:
                        "checkmark.circle"
                )

                Spacer()

                Label(
                    "\(snapshot.needsEvidenceGateCount) need evidence",
                    systemImage:
                        "questionmark.circle"
                )
            }
            .font(.caption)

            HStack {
                Label(
                    "\(snapshot.warningGateCount) warning",
                    systemImage:
                        "exclamationmark.triangle"
                )

                Spacer()

                Label(
                    "\(snapshot.blockerGateCount) blocker",
                    systemImage:
                        "xmark.octagon"
                )
            }
            .font(.caption)
        }
        .labDecisionCard()
    }

    private var evidenceCard: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Label(
                "Decision Evidence",
                systemImage:
                    "chart.bar.doc.horizontal"
            )
            .font(.headline)

            LazyVGrid(
                columns: metricColumns,
                spacing: 12
            ) {
                LabDecisionMetricTile(
                    title: "Sessions",
                    value:
                        "\(snapshot.sessionCount)",
                    detail:
                        "\(snapshot.comparisonSessionCount) with A/B"
                )
                LabDecisionMetricTile(
                    title: "Eligible A/B",
                    value:
                        "\(snapshot.comparisonCount)",
                    detail:
                        "decision-quality comparisons"
                )
                LabDecisionMetricTile(
                    title: "Confidence",
                    value:
                        percentText(
                            snapshot
                                .latestConfidenceScorePercent
                        ),
                    detail:
                        "latest assessed"
                )
                LabDecisionMetricTile(
                    title: "Coverage",
                    value:
                        percentText(
                            snapshot
                                .latestEvidenceCoveragePercent
                        ),
                    detail:
                        "latest evidence"
                )
                LabDecisionMetricTile(
                    title: "Repeatable reductions",
                    value:
                        "\(snapshot.consistentReductionCount)",
                    detail:
                        "\(snapshot.matureRepeatabilityCount) mature groups"
                )
                LabDecisionMetricTile(
                    title: "Position reversals",
                    value:
                        "\(snapshot.directionReversalCount)",
                    detail:
                        "\(snapshot.multiPositionConditionCount) multi-position"
                )
                LabDecisionMetricTile(
                    title: "Broad frequency",
                    value:
                        "\(snapshot.qualifyingBroadFrequencySeriesCount)",
                    detail:
                        "\(snapshot.broadFrequencySeriesCount) broad series"
                )
            }
        }
        .labDecisionCard()
    }

    private var gatesCard: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Label(
                "Decision Gates",
                systemImage:
                    "checklist.checked"
            )
            .font(.headline)

            ForEach(
                snapshot.gates
            ) { gate in
                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    HStack(
                        alignment:
                            .firstTextBaseline
                    ) {
                        Label(
                            gate.title,
                            systemImage:
                                symbol(
                                    for:
                                        gate.status
                                )
                        )
                        .font(
                            .subheadline
                                .weight(
                                    .semibold
                                )
                        )

                        Spacer()

                        Text(
                            gate.status
                                .rawValue
                        )
                        .font(
                            .caption
                                .weight(.bold)
                        )
                    }

                    Text(
                        gate.summary
                    )
                    .font(
                        .caption
                            .monospacedDigit()
                    )

                    Text(
                        gate.detail
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                if
                    gate.id !=
                        snapshot.gates
                            .last?
                            .id
                {
                    Divider()
                }
            }
        }
        .labDecisionCard()
    }

    private var interpretationCard: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            Label(
                "What this verdict means",
                systemImage:
                    "info.circle"
            )
            .font(.headline)

            Text(
                "GO means the saved Lab evidence is strong enough to justify continued engineering of the prototype. HOLD means the evidence is incomplete or still has warnings. NO-GO means at least one mature evidence gate contradicts the generalized cancellation approach."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Text(
                "None of these verdicts establish production readiness, safe unattended use, regulatory compliance, reliable cancellation across vehicles, or acoustic performance for unmeasured occupants. The report is a decision aid for the current research prototype."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .labDecisionCard()
    }

    private var shareCard: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Label(
                "Portable Report",
                systemImage:
                    "square.and.arrow.up"
            )
            .font(.headline)

            Text(
                "Share a plain-text snapshot of the current verdict, evidence counts, and gate outcomes."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            ShareLink(
                item:
                    snapshot.reportText,
                subject:
                    Text(
                        "QuietDrive Lab go/no-go report"
                    )
            ) {
                Label(
                    "Share Report",
                    systemImage:
                        "square.and.arrow.up"
                )
                .frame(
                    maxWidth: .infinity
                )
            }
            .buttonStyle(.borderedProminent)
        }
        .labDecisionCard()
    }

    private var verdictSymbol: String {
        switch snapshot.verdict {
        case .go:
            return "checkmark.seal"
        case .hold:
            return "pause.circle"
        case .noGo:
            return "xmark.octagon"
        }
    }

    private var verdictExplanation: String {
        switch snapshot.verdict {
        case .go:
            return "All five decision gates pass."
        case .hold:
            return "No blocker is present, but at least one gate still needs evidence or carries a warning."
        case .noGo:
            return "At least one decision gate is a blocker for generalized cancellation with the current approach."
        }
    }

    private func symbol(
        for status:
            LabDecisionGateStatus
    ) -> String {
        switch status {
        case .pass:
            return "checkmark.circle"
        case .needsEvidence:
            return "questionmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .blocker:
            return "xmark.octagon"
        }
    }

    private func percentText(
        _ value: Double?
    ) -> String {
        guard let value else {
            return "—"
        }

        return String(
            format: "%.0f%%",
            value
        )
    }
}

private struct LabDecisionMetricTile:
    View
{
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 4
        ) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(
                    .title3
                        .weight(.semibold)
                )
                .monospacedDigit()

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(12)
        .background(
            .quaternary,
            in:
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
        )
    }
}

private extension View {
    func labDecisionCard() -> some View {
        self
            .padding(16)
            .background(
                .thinMaterial,
                in:
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
            )
    }
}
