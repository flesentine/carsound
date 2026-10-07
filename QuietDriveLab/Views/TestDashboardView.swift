import Foundation
import SwiftUI

struct TestDashboardView: View {
    @Environment(StructuredLogModel.self)
    private var structuredLog

    @State
    private var scope:
        TestDashboardScope =
            .allSaved

    private var snapshot:
        TestDashboardSnapshot
    {
        TestDashboardAnalytics
            .snapshot(
                events:
                    structuredLog.events,
                scope: scope,
                currentSessionID:
                    structuredLog
                        .currentSessionID
            )
    }

    private var repeatability:
        RepeatabilitySnapshot
    {
        RepeatabilityAnalytics
            .snapshot(
                events:
                    structuredLog.events
            )
    }

    private var headPositionSensitivity:
        HeadPositionSensitivitySnapshot
    {
        HeadPositionSensitivityAnalytics
            .snapshot(
                events:
                    structuredLog.events
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
                scopeCard
                overviewCard
                measurementCard
                confidenceCard
                workflowCard
                repeatabilityCard
                headPositionSensitivityCard
                recentSessionsCard
                interpretationCard
            }
            .padding(20)
        }
        .navigationTitle("Test Dashboard")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var scopeCard: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text("Evidence scope")
                .font(.headline)

            Picker(
                "Evidence scope",
                selection: $scope
            ) {
                ForEach(
                    TestDashboardScope
                        .allCases
                ) { item in
                    Text(item.title)
                        .tag(item)
                }
            }
            .pickerStyle(.segmented)

            Text(
                "Summarizes the structured experiment events already saved by QuietDrive. Nothing new is recorded by opening this dashboard."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .dashboardCard()
    }

    private var overviewCard: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Label(
                "Evidence Overview",
                systemImage:
                    "rectangle.3.group"
            )
            .font(.headline)

            LazyVGrid(
                columns: metricColumns,
                spacing: 12
            ) {
                DashboardMetricTile(
                    title: "Sessions",
                    value:
                        "\(snapshot.sessionCount)",
                    detail:
                        snapshot.scope.title
                )
                DashboardMetricTile(
                    title: "Events",
                    value:
                        "\(snapshot.eventCount)",
                    detail:
                        "structured records"
                )
                DashboardMetricTile(
                    title: "Routes",
                    value:
                        "\(snapshot.distinctRouteCount)",
                    detail:
                        "distinct signatures"
                )
                DashboardMetricTile(
                    title: "Frequencies",
                    value:
                        "\(snapshot.distinctFrequencyCount)",
                    detail:
                        "distinct targets"
                )
            }

            HStack {
                Label(
                    "\(snapshot.failureCount) failures",
                    systemImage:
                        "exclamationmark.triangle"
                )

                Spacer()

                Label(
                    "\(snapshot.safetyMuteCount) safety mutes",
                    systemImage:
                        "speaker.slash"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .dashboardCard()
    }

    private var measurementCard: some View {
        let hitRate =
            snapshot.comparisonCount > 0
            ? Double(
                snapshot
                    .positiveReductionCount
            ) /
            Double(
                snapshot
                    .comparisonCount
            )
            : 0

        return VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Label(
                "A/B Measurement Outcomes",
                systemImage:
                    "waveform.path.ecg"
            )
            .font(.headline)

            LazyVGrid(
                columns: metricColumns,
                spacing: 12
            ) {
                DashboardMetricTile(
                    title: "Comparisons",
                    value:
                        "\(snapshot.comparisonCount)",
                    detail:
                        "saved A/B records"
                )
                DashboardMetricTile(
                    title: "Reduced",
                    value:
                        "\(snapshot.positiveReductionCount)",
                    detail:
                        "target energy lower"
                )
                DashboardMetricTile(
                    title: "Average",
                    value:
                        reductionText(
                            snapshot
                                .averageReductionDB
                        ),
                    detail:
                        "measured reduction"
                )
                DashboardMetricTile(
                    title: "Best",
                    value:
                        reductionText(
                            snapshot
                                .bestReductionDB
                        ),
                    detail:
                        "single comparison"
                )
            }

            if
                snapshot.comparisonCount >
                    0
            {
                ProgressView(
                    value: hitRate
                ) {
                    Text(
                        "Positive-reduction comparisons"
                    )
                    .font(.caption)
                } currentValueLabel: {
                    Text(
                        hitRate.formatted(
                            .percent
                                .precision(
                                    .fractionLength(
                                        0
                                    )
                                )
                        )
                    )
                    .font(.caption.monospacedDigit())
                }
            } else {
                Text(
                    "No saved A/B comparisons in this scope yet."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .dashboardCard()
    }

    private var confidenceCard: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Label(
                "Confidence Evidence",
                systemImage:
                    "gauge.with.dots.needle.67percent"
            )
            .font(.headline)

            LazyVGrid(
                columns: metricColumns,
                spacing: 12
            ) {
                DashboardMetricTile(
                    title: "Latest",
                    value:
                        percentText(
                            snapshot
                                .latestConfidenceScorePercent
                        ),
                    detail:
                        snapshot
                            .latestConfidenceLevel ??
                        "no confidence yet"
                )
                DashboardMetricTile(
                    title: "Coverage",
                    value:
                        percentText(
                            snapshot
                                .latestEvidenceCoveragePercent
                        ),
                    detail:
                        "latest evidence"
                )
                DashboardMetricTile(
                    title: "Snapshots",
                    value:
                        "\(snapshot.confidenceSnapshotCount)",
                    detail:
                        "explicit logs"
                )
                DashboardMetricTile(
                    title: "Snapshot avg",
                    value:
                        percentText(
                            snapshot
                                .averageConfidenceSnapshotScorePercent
                        ),
                    detail:
                        "explicit snapshots"
                )
            }

            if
                let latest =
                    snapshot
                        .latestConfidenceScorePercent
            {
                ProgressView(
                    value:
                        min(
                            max(
                                latest /
                                100,
                                0
                            ),
                            1
                        )
                )
            }
        }
        .dashboardCard()
    }

    private var workflowCard: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Label(
                "Workflow Evidence",
                systemImage:
                    "checklist.checked"
            )
            .font(.headline)

            ForEach(
                snapshot.workflowSummaries
            ) { workflow in
                HStack(
                    alignment:
                        .firstTextBaseline
                ) {
                    Text(workflow.title)

                    Spacer()

                    Text(
                        "\(workflow.completedCount) done"
                    )
                    .font(
                        .caption
                            .monospacedDigit()
                    )
                    .foregroundStyle(
                        .secondary
                    )

                    if
                        workflow.failedCount >
                            0
                    {
                        Text(
                            "\(workflow.failedCount) failed"
                        )
                        .font(
                            .caption
                                .monospacedDigit()
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }

                if
                    workflow.id !=
                        snapshot
                            .workflowSummaries
                            .last?
                            .id
                {
                    Divider()
                }
            }
        }
        .dashboardCard()
    }

    private var repeatabilityCard: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Label(
                    "Repeatability",
                    systemImage:
                        "arrow.triangle.2.circlepath"
                )
                .font(.headline)

                Spacer()

                Text(
                    "\(repeatability.crossSessionConditionCount) cross-session"
                )
                .font(
                    .caption
                        .weight(.semibold)
                )
                .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: metricColumns,
                spacing: 12
            ) {
                DashboardMetricTile(
                    title: "Matched conditions",
                    value:
                        "\(repeatability.matchedConditionCount)",
                    detail:
                        "route + Hz + phase + output"
                )
                DashboardMetricTile(
                    title: "Mature",
                    value:
                        "\(repeatability.matureConditionCount)",
                    detail:
                        "3+ separate sessions"
                )
                DashboardMetricTile(
                    title: "Consistent reduction",
                    value:
                        "\(repeatability.consistentReductionCount)",
                    detail:
                        "tight mature groups"
                )
                DashboardMetricTile(
                    title: "Excluded",
                    value:
                        "\(repeatability.excludedComparisonCount)",
                    detail:
                        "missing match context"
                )
            }

            NavigationLink {
                RepeatabilityView()
            } label: {
                Label(
                    "Open Repeatability",
                    systemImage:
                        "repeat"
                )
                .frame(
                    maxWidth: .infinity
                )
            }
            .buttonStyle(.borderedProminent)

            Text(
                "Repeatability uses per-session means so many search trials inside one session cannot inflate cross-session evidence."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .dashboardCard()
    }

    private var headPositionSensitivityCard: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Label(
                    "Head-Position Sensitivity",
                    systemImage:
                        "figure.seated.side"
                )
                .font(.headline)

                Spacer()

                Text(
                    "\(headPositionSensitivity.multiPositionConditionCount) tested"
                )
                .font(
                    .caption
                        .weight(.semibold)
                )
                .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: metricColumns,
                spacing: 12
            ) {
                DashboardMetricTile(
                    title: "Tagged A/B",
                    value:
                        "\(headPositionSensitivity.taggedComparisonCount)",
                    detail:
                        "position-labeled"
                )
                DashboardMetricTile(
                    title: "2+ positions",
                    value:
                        "\(headPositionSensitivity.multiPositionConditionCount)",
                    detail:
                        "matched settings"
                )
                DashboardMetricTile(
                    title: "Direction flips",
                    value:
                        "\(headPositionSensitivity.directionReversalCount)",
                    detail:
                        "benefit ↔ worsening"
                )
                DashboardMetricTile(
                    title: "Max spread",
                    value:
                        headPositionSpreadText(
                            headPositionSensitivity
                                .maximumSpreadDB
                        ),
                    detail:
                        "position means"
                )
            }

            NavigationLink {
                HeadPositionSensitivityView()
            } label: {
                Label(
                    "Open Head-Position Sensitivity",
                    systemImage:
                        "person.2.wave.2"
                )
                .frame(
                    maxWidth: .infinity
                )
            }
            .buttonStyle(.borderedProminent)

            Text(
                "Each saved A/B run carries the manually selected Reference/Left/Right/Forward/Back label. A fresh baseline is required after changing position."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .dashboardCard()
    }

    private var recentSessionsCard: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Label(
                "Recent Sessions",
                systemImage:
                    "clock.arrow.circlepath"
            )
            .font(.headline)

            if
                snapshot.recentSessions
                    .isEmpty
            {
                Text(
                    "No structured sessions are available in this scope."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ForEach(
                    snapshot.recentSessions
                ) { session in
                    VStack(
                        alignment: .leading,
                        spacing: 6
                    ) {
                        HStack {
                            Text(
                                sessionTitle(
                                    session
                                )
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )

                            if
                                session
                                    .isCurrentSession
                            {
                                Text("Current")
                                    .font(
                                        .caption2
                                            .weight(
                                                .bold
                                            )
                                    )
                            }

                            Spacer()

                            Text(
                                session
                                    .startedAt
                                    .formatted(
                                        date:
                                            .abbreviated,
                                        time:
                                            .shortened
                                    )
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                        }

                        HStack {
                            Text(
                                "\(session.eventCount) events"
                            )
                            Text("•")
                            Text(
                                "\(session.comparisonCount) A/B"
                            )
                            Text("•")
                            Text(
                                "\(session.distinctRouteCount) routes"
                            )
                            Text("•")
                            Text(
                                "\(session.distinctFrequencyCount) freqs"
                            )
                        }
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )

                        HStack {
                            Text(
                                "Best " +
                                reductionText(
                                    session
                                        .bestReductionDB
                                )
                            )

                            Spacer()

                            Text(
                                "Confidence " +
                                percentText(
                                    session
                                        .latestConfidenceScorePercent
                                )
                            )
                        }
                        .font(
                            .caption
                                .monospacedDigit()
                        )

                        if
                            session.failureCount >
                                0 ||
                            session.safetyMuteCount >
                                0
                        {
                            Text(
                                "\(session.failureCount) failures • \(session.safetyMuteCount) safety mutes"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                        }
                    }

                    if
                        session.id !=
                            snapshot
                                .recentSessions
                                .last?
                                .id
                    {
                        Divider()
                    }
                }
            }
        }
        .dashboardCard()
    }

    private var interpretationCard: some View {
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
                "This dashboard is a descriptive view of saved experiment evidence. Repeatability now keeps labeled head positions separate, and the head-position analysis shows whether the same settings change across Reference/Left/Right/Forward/Back. Vehicle speed, road surface, HVAC state, passenger load, and exact phone placement are still uncontrolled. #39 broadens testing across frequencies next."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .dashboardCard()
    }

    private func sessionTitle(
        _ session:
            TestDashboardSessionSummary
    ) -> String {
        var parts = [
            String(
                session.id
                    .uuidString
                    .prefix(8)
            )
        ]

        if
            let build =
                session.appBuild
        {
            parts.append(
                "build " +
                build
            )
        }

        return parts.joined(
            separator: " • "
        )
    }

    private func reductionText(
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

    private func headPositionSpreadText(
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

private struct DashboardMetricTile:
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
    func dashboardCard() -> some View {
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
