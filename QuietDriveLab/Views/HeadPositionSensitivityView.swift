import Foundation
import SwiftUI

struct HeadPositionSensitivityView: View {
    @Environment(StructuredLogModel.self)
    private var structuredLog

    @State
    private var showSinglePositionConditions =
        false

    private var snapshot:
        HeadPositionSensitivitySnapshot
    {
        HeadPositionSensitivityAnalytics
            .snapshot(
                events:
                    structuredLog.events
            )
    }

    private var visibleGroups:
        [HeadPositionSensitivityGroup]
    {
        if showSinglePositionConditions {
            return snapshot.groups
        }

        return snapshot.groups.filter {
            $0.positionCount >= 2
        }
    }

    private let metricColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                summaryCard
                protocolCard
                conditionsCard
                limitsCard
            }
            .padding(20)
        }
        .navigationTitle(
            "Head-Position Sensitivity"
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
    }

    private var summaryCard: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Label(
                "Position Coverage",
                systemImage:
                    "person.crop.circle.badge.questionmark"
            )
            .font(.headline)

            LazyVGrid(
                columns: metricColumns,
                spacing: 12
            ) {
                HeadPositionMetricTile(
                    title: "Tagged A/B",
                    value:
                        "\(snapshot.taggedComparisonCount)",
                    detail:
                        snapshot.excludedComparisonCount >
                            0
                        ? "\(snapshot.excludedComparisonCount) excluded"
                        : "all tagged"
                )
                HeadPositionMetricTile(
                    title: "Conditions",
                    value:
                        "\(snapshot.conditionCount)",
                    detail:
                        "matched settings"
                )
                HeadPositionMetricTile(
                    title: "2+ positions",
                    value:
                        "\(snapshot.multiPositionConditionCount)",
                    detail:
                        "sensitivity evidence"
                )
                HeadPositionMetricTile(
                    title: "Direction flips",
                    value:
                        "\(snapshot.directionReversalCount)",
                    detail:
                        "benefit ↔ worsening"
                )
                HeadPositionMetricTile(
                    title: "Max spread",
                    value:
                        spreadText(
                            snapshot.maximumSpreadDB
                        ),
                    detail:
                        "across positions"
                )
            }

            if
                snapshot
                    .taggedComparisonCount ==
                    0
            {
                Text(
                    "No A/B runs have a head-position label yet. Select a position in Cancellation Lab, capture a new baseline for that position, then save treatment comparisons."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .headPositionCard()
    }

    private var protocolCard: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Label(
                "Test Protocol",
                systemImage:
                    "figure.seated.side"
            )
            .font(.headline)

            Text(
                "Use the same route, target frequency, phase, output level, phone placement, and driving condition. Change only the selected head-position label, then capture a fresh baseline before treatment."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            ForEach(
                HeadPositionPreset
                    .allCases
            ) { position in
                HStack(
                    alignment:
                        .firstTextBaseline
                ) {
                    Text(
                        position.title
                    )
                    .font(
                        .caption
                            .weight(.semibold)
                    )

                    Spacer()

                    Text(
                        position.instruction
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                    .multilineTextAlignment(
                        .trailing
                    )
                }
            }

            Text(
                "These are manual labels, not measured distances. Keep each posture shift as repeatable as you can."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .headPositionCard()
    }

    private var conditionsCard: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Label(
                    "Matched Conditions",
                    systemImage:
                        "person.2.wave.2"
                )
                .font(.headline)

                Spacer()

                Toggle(
                    "Show 1-position",
                    isOn:
                        $showSinglePositionConditions
                )
                .labelsHidden()
            }

            if visibleGroups.isEmpty {
                Text(
                    showSinglePositionConditions
                    ? "No tagged head-position comparisons are available yet."
                    : "No matched condition has been measured at two or more head positions yet."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ForEach(
                    visibleGroups
                ) { group in
                    DisclosureGroup {
                        positionDetails(
                            group
                        )
                        .padding(.top, 8)
                    } label: {
                        conditionHeader(
                            group
                        )
                    }

                    if
                        group.id !=
                            visibleGroups
                                .last?
                                .id
                    {
                        Divider()
                    }
                }
            }
        }
        .headPositionCard()
    }

    @ViewBuilder
    private func conditionHeader(
        _ group:
            HeadPositionSensitivityGroup
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            HStack(
                alignment:
                    .firstTextBaseline
            ) {
                Text(
                    conditionTitle(
                        group.condition
                    )
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )

                Spacer()

                Text(
                    group.assessment
                        .rawValue
                )
                .font(
                    .caption
                        .weight(.semibold)
                )
                .multilineTextAlignment(
                    .trailing
                )
            }

            Text(
                group.condition
                    .routeSignature
            )
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(2)

            HStack {
                Text(
                    "\(group.positionCount) positions"
                )
                Text("•")
                Text(
                    "\(group.comparisonCount) comparisons"
                )

                if
                    let spread =
                        group.spreadDB
                {
                    Text("•")
                    Text(
                        "spread " +
                        String(
                            format:
                                "%.2f dB",
                            spread
                        )
                    )
                }
            }
            .font(
                .caption
                    .monospacedDigit()
            )
            .foregroundStyle(.secondary)

            if
                let best =
                    group.bestPosition,
                let worst =
                    group.worstPosition,
                let bestDB =
                    group.bestMeanReductionDB,
                let worstDB =
                    group.worstMeanReductionDB
            {
                Text(
                    "Best \(best.title) \(String(format: "%.2f", bestDB)) dB • Worst \(worst.title) \(String(format: "%.2f", worstDB)) dB"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func positionDetails(
        _ group:
            HeadPositionSensitivityGroup
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            Text(
                "Per-position session-balanced means"
            )
            .font(
                .caption
                    .weight(.semibold)
            )

            ForEach(
                group.positionResults
            ) { result in
                HStack(
                    alignment:
                        .firstTextBaseline
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            result.position
                                .title
                        )
                        .font(
                            .caption
                                .weight(
                                    .semibold
                                )
                        )

                        Text(
                            "\(result.sessionCount) sessions • \(result.comparisonCount) trials"
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    Spacer()

                    VStack(
                        alignment: .trailing,
                        spacing: 2
                    ) {
                        Text(
                            String(
                                format:
                                    "%.2f dB",
                                result
                                    .meanReductionDB
                            )
                        )
                        .font(
                            .caption
                                .monospacedDigit()
                        )

                        Text(
                            String(
                                format:
                                    "%.2f…%.2f dB session means",
                                result
                                    .minimumSessionMeanReductionDB,
                                result
                                    .maximumSessionMeanReductionDB
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }
            }
        }
    }

    private var limitsCard: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            Label(
                "How to read this",
                systemImage:
                    "info.circle"
            )
            .font(.headline)

            Text(
                "A direction reversal is the strongest warning: one head position shows reduction while another shows worsening beyond the ±0.5 dB deadband. Otherwise, ≤1 dB spread is labeled low sensitivity, ≤3 dB moderate, and >3 dB high. This still depends on manually reproduced posture and does not measure the listener's physical coordinates."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .headPositionCard()
    }

    private func conditionTitle(
        _ condition:
            HeadPositionBaseCondition
    ) -> String {
        String(
            format:
                "%.1f Hz • %d° • %d%%",
            condition.targetFrequencyHz,
            condition.phaseDegrees,
            condition.outputPercent
        )
    }

    private func spreadText(
        _ value: Double?
    ) -> String {
        guard let value else {
            return "—"
        }

        return String(
            format: "%.2f dB",
            value
        )
    }
}

private struct HeadPositionMetricTile:
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
    func headPositionCard() -> some View {
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
