import Foundation
import SwiftUI

struct FrequencyCoverageView: View {
    @Environment(StructuredLogModel.self)
    private var structuredLog

    @State
    private var showSingleTargetSeries =
        false

    private var snapshot:
        FrequencyCoverageSnapshot
    {
        FrequencyCoverageAnalytics
            .snapshot(
                events:
                    structuredLog.events
            )
    }

    private var visibleSeries:
        [FrequencyCoverageSeries]
    {
        if showSingleTargetSeries {
            return snapshot.series
        }

        return snapshot.series.filter {
            $0.frequencyCount >= 2
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
                coverageBandsCard
                seriesCard
                interpretationCard
            }
            .padding(20)
        }
        .navigationTitle(
            "Frequency Coverage"
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
                "Multi-Frequency Evidence",
                systemImage:
                    "waveform.badge.magnifyingglass"
            )
            .font(.headline)

            LazyVGrid(
                columns: metricColumns,
                spacing: 12
            ) {
                FrequencyCoverageMetricTile(
                    title: "A/B records",
                    value:
                        "\(snapshot.analyzableComparisonCount)",
                    detail:
                        snapshot.excludedComparisonCount >
                            0
                        ? "\(snapshot.excludedComparisonCount) excluded"
                        : "all analyzable"
                )
                FrequencyCoverageMetricTile(
                    title: "Targets",
                    value:
                        "\(snapshot.distinctFrequencyCount)",
                    detail:
                        "rounded to 1 Hz"
                )
                FrequencyCoverageMetricTile(
                    title: "Multi-target series",
                    value:
                        "\(snapshot.multiFrequencySeriesCount)",
                    detail:
                        "same route + position"
                )
                FrequencyCoverageMetricTile(
                    title: "Broad series",
                    value:
                        "\(snapshot.broadCoverageSeriesCount)",
                    detail:
                        "low + mid + high"
                )
                FrequencyCoverageMetricTile(
                    title: "Max span",
                    value:
                        spanText(
                            snapshot.maximumFrequencySpanHz
                        ),
                    detail:
                        "within one series"
                )
            }

            if
                snapshot
                    .multiFrequencySeriesCount ==
                    0
            {
                Text(
                    "No route/head-position series has saved A/B evidence at two or more target frequencies yet."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .frequencyCoverageCard()
    }

    private var coverageBandsCard: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Label(
                "Coverage Bands",
                systemImage:
                    "waveform.path"
            )
            .font(.headline)

            ForEach(
                FrequencyCoverageBand
                    .allCases
            ) { band in
                HStack {
                    Text(band.title)
                        .font(
                            .caption
                                .weight(.semibold)
                        )

                    Spacer()

                    Text(
                        band.rangeText
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

            Text(
                "Broad coverage means the same route/head-position series has at least one tested target in all three bands. It does not mean one phase/output setting works at every frequency."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frequencyCoverageCard()
    }

    private var seriesCard: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Label(
                    "Coverage Series",
                    systemImage:
                        "chart.xyaxis.line"
                )
                .font(.headline)

                Spacer()

                Toggle(
                    "Show single target",
                    isOn:
                        $showSingleTargetSeries
                )
                .labelsHidden()
            }

            if visibleSeries.isEmpty {
                Text(
                    showSingleTargetSeries
                    ? "No analyzable frequency evidence is available yet."
                    : "No route/head-position series has more than one tested target yet."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ForEach(
                    visibleSeries
                ) { series in
                    DisclosureGroup {
                        frequencyDetails(
                            series
                        )
                        .padding(.top, 8)
                    } label: {
                        seriesHeader(
                            series
                        )
                    }

                    if
                        series.id !=
                            visibleSeries
                                .last?
                                .id
                    {
                        Divider()
                    }
                }
            }
        }
        .frequencyCoverageCard()
    }

    @ViewBuilder
    private func seriesHeader(
        _ series:
            FrequencyCoverageSeries
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
                    series.context
                        .headPosition?
                        .title ??
                    "Unlabeled position"
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )

                Spacer()

                Text(
                    series.assessment
                        .rawValue
                )
                .font(
                    .caption
                        .weight(.semibold)
                )
            }

            Text(
                series.context
                    .routeSignature
            )
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(2)

            HStack {
                Text(
                    "\(series.frequencyCount) targets"
                )
                Text("•")
                Text(
                    "\(series.bandsCovered.count)/3 bands"
                )
                Text("•")
                Text(
                    String(
                        format:
                            "%.0f–%.0f Hz",
                        series
                            .minimumFrequencyHz,
                        series
                            .maximumFrequencyHz
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
                    "\(series.positiveFrequencyCount) positive-best"
                )
                Text("•")
                Text(
                    "\(series.repeatedPositiveFrequencyCount) repeated-positive"
                )
                Text("•")
                Text(
                    "\(series.crossSessionFrequencyCount) cross-session"
                )
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func frequencyDetails(
        _ series:
            FrequencyCoverageSeries
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(
                series.frequencyResults
            ) { result in
                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    HStack(
                        alignment:
                            .firstTextBaseline
                    ) {
                        Text(
                            String(
                                format:
                                    "%.0f Hz",
                                result
                                    .frequencyHz
                            )
                        )
                        .font(
                            .caption
                                .weight(
                                    .semibold
                                )
                                .monospacedDigit()
                        )

                        Text(
                            result.band
                                .title
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            .secondary
                        )

                        Spacer()

                        Text(
                            String(
                                format:
                                    "%.2f dB best/session",
                                result
                                    .sessionBalancedBestReductionDB
                            )
                        )
                        .font(
                            .caption
                                .monospacedDigit()
                        )
                    }

                    HStack {
                        Text(
                            "\(result.sessionCount) sessions"
                        )
                        Text("•")
                        Text(
                            "\(result.comparisonCount) comparisons"
                        )
                        Text("•")
                        Text(
                            "+\(result.positiveBestSessionCount) / 0 \(result.neutralBestSessionCount) / −\(result.negativeBestSessionCount)"
                        )
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    Text(
                        String(
                            format:
                                "Session-balanced all-trial mean %.2f dB • best observed %.2f dB",
                            result
                                .sessionBalancedAverageReductionDB,
                            result
                                .bestObservedReductionDB
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                if
                    result.id !=
                        series
                            .frequencyResults
                            .last?
                            .id
                {
                    Divider()
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
                "How to read this",
                systemImage:
                    "info.circle"
            )
            .font(.headline)

            Text(
                "Each target frequency is allowed to have its own phase and output optimization. For capability discovery, the primary number is the average of each session's best observed reduction at that frequency; all-trial means are shown beside it so search failures are not hidden. Best-observed evidence can still benefit from trying more settings, so repeatability across sessions remains the stronger confirmation."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Text(
                "Recommended coverage targets are 40, 60, 80, 100, 120, 160, and 200 Hz, but real persistent cabin tones are more important than filling every preset."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frequencyCoverageCard()
    }

    private func spanText(
        _ value: Double?
    ) -> String {
        guard let value else {
            return "—"
        }

        return String(
            format: "%.0f Hz",
            value
        )
    }
}

private struct FrequencyCoverageMetricTile:
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
    func frequencyCoverageCard() -> some View {
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
