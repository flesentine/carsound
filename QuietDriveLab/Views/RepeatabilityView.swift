import Foundation
import SwiftUI

struct RepeatabilityView: View {
    @Environment(StructuredLogModel.self)
    private var structuredLog

    @State
    private var showSingleSessionConditions =
        false

    private var snapshot:
        RepeatabilitySnapshot
    {
        RepeatabilityAnalytics
            .snapshot(
                events:
                    structuredLog.events
            )
    }

    private var visibleGroups:
        [RepeatabilityGroup]
    {
        if showSingleSessionConditions {
            return snapshot.groups
        }

        return snapshot.groups.filter {
            $0.sessionCount >= 2
        }
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
                summaryCard
                matchingRulesCard
                conditionGroupsCard
                interpretationCard
            }
            .padding(20)
        }
        .navigationTitle("Repeatability")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryCard: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Label(
                "Cross-Session Evidence",
                systemImage:
                    "arrow.triangle.2.circlepath"
            )
            .font(.headline)

            LazyVGrid(
                columns: metricColumns,
                spacing: 12
            ) {
                RepeatabilityMetricTile(
                    title: "A/B records",
                    value:
                        "\(snapshot.analyzableComparisonCount)",
                    detail:
                        snapshot.excludedComparisonCount >
                            0
                        ? "\(snapshot.excludedComparisonCount) excluded"
                        : "all analyzable"
                )
                RepeatabilityMetricTile(
                    title: "Conditions",
                    value:
                        "\(snapshot.matchedConditionCount)",
                    detail:
                        "matched settings"
                )
                RepeatabilityMetricTile(
                    title: "Cross-session",
                    value:
                        "\(snapshot.crossSessionConditionCount)",
                    detail:
                        "2+ sessions"
                )
                RepeatabilityMetricTile(
                    title: "Mature",
                    value:
                        "\(snapshot.matureConditionCount)",
                    detail:
                        "3+ sessions"
                )
                RepeatabilityMetricTile(
                    title: "Consistent reduction",
                    value:
                        "\(snapshot.consistentReductionCount)",
                    detail:
                        "mature conditions"
                )
            }

            if
                snapshot
                    .crossSessionConditionCount ==
                    0
            {
                Text(
                    "No setting has been repeated across separate app sessions yet. Repeat the same route, target frequency, phase, and output level in another session to begin cross-session evidence."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .repeatabilityCard()
    }

    private var matchingRulesCard: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Label(
                "Matching Rules",
                systemImage:
                    "equal.circle"
            )
            .font(.headline)

            Text(
                "A comparison joins the same repeatability condition only when its route signature matches and its target frequency, phase, and output level match after small display-level normalization."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                Text(
                    "• Route signature: exact match"
                )
                Text(
                    "• Target frequency: nearest 0.1 Hz"
                )
                Text(
                    "• Phase: nearest 1°"
                )
                Text(
                    "• Output: nearest 1 percentage point"
                )
                Text(
                    "• Multiple trials inside one session are averaged first"
                )
                Text(
                    "• Mature assessment requires at least 3 separate sessions"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(
                "Consistency uses per-session mean reduction. ±0.5 dB is treated as near-zero; mature groups are considered tight only when session-mean standard deviation is ≤1.0 dB and total range is ≤2.0 dB."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .repeatabilityCard()
    }

    private var conditionGroupsCard: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Label(
                    "Matched Conditions",
                    systemImage:
                        "square.stack.3d.up"
                )
                .font(.headline)

                Spacer()

                Toggle(
                    "Show 1-session",
                    isOn:
                        $showSingleSessionConditions
                )
                .labelsHidden()
            }

            if
                visibleGroups.isEmpty
            {
                Text(
                    showSingleSessionConditions
                    ? "No analyzable A/B conditions are available yet."
                    : "No condition has evidence from at least two sessions yet."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ForEach(
                    visibleGroups
                ) { group in
                    DisclosureGroup {
                        sessionDetails(
                            group
                        )
                        .padding(.top, 8)
                    } label: {
                        groupHeader(
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
        .repeatabilityCard()
    }

    @ViewBuilder
    private func groupHeader(
        _ group: RepeatabilityGroup
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            HStack(
                alignment: .firstTextBaseline
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
                    "\(group.sessionCount) sessions"
                )
                Text("•")
                Text(
                    "\(group.comparisonCount) comparisons"
                )
                Text("•")
                Text(
                    "mean " +
                    reductionText(
                        group.meanReductionDB
                    )
                )
            }
            .font(
                .caption
                    .monospacedDigit()
            )
            .foregroundStyle(.secondary)

            HStack {
                Text(
                    "σ " +
                    String(
                        format: "%.2f dB",
                        group
                            .standardDeviationDB
                    )
                )
                Text("•")
                Text(
                    "range " +
                    String(
                        format: "%.2f dB",
                        group.rangeDB
                    )
                )
                Text("•")
                Text(
                    "+\(group.positiveSessionCount) / 0 \(group.neutralSessionCount) / −\(group.negativeSessionCount)"
                )
            }
            .font(
                .caption2
                    .monospacedDigit()
            )
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func sessionDetails(
        _ group: RepeatabilityGroup
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            Text("Per-session means")
                .font(
                    .caption
                        .weight(.semibold)
                )

            ForEach(
                group.sessionResults
            ) { session in
                HStack(
                    alignment:
                        .firstTextBaseline
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            String(
                                session
                                    .sessionID
                                    .uuidString
                                    .prefix(8)
                            )
                        )
                        .font(
                            .caption
                                .monospaced()
                        )

                        Text(
                            session
                                .latestAt
                                .formatted(
                                    date:
                                        .abbreviated,
                                    time:
                                        .shortened
                                )
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
                            reductionText(
                                session
                                    .meanReductionDB
                            )
                        )
                        .font(
                            .caption
                                .monospacedDigit()
                        )

                        Text(
                            "\(session.comparisonCount) trials • " +
                            String(
                                format:
                                    "%.2f…%.2f dB",
                                session
                                    .minimumReductionDB,
                                session
                                    .maximumReductionDB
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

    private var interpretationCard: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            Label(
                "Limits of this result",
                systemImage:
                    "info.circle"
            )
            .font(.headline)

            Text(
                "Matching here proves only that QuietDrive repeated similar logged settings across app sessions. The current log does not yet encode head position, vehicle speed, road surface, HVAC state, passenger load, or exact phone placement. A consistent reduction is useful evidence, not proof that the result will generalize. #38 adds head-position sensitivity next."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .repeatabilityCard()
    }

    private func conditionTitle(
        _ condition:
            RepeatabilityCondition
    ) -> String {
        String(
            format:
                "%.1f Hz • %d° • %d%%",
            condition.targetFrequencyHz,
            condition.phaseDegrees,
            condition.outputPercent
        )
    }

    private func reductionText(
        _ value: Double
    ) -> String {
        String(
            format: "%.2f dB",
            value
        )
    }
}

private struct RepeatabilityMetricTile:
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
    func repeatabilityCard() -> some View {
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
