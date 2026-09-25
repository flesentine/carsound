import SwiftUI

enum SpectrumRenderMode: String, CaseIterable, Identifiable {
    case raw = "Raw"
    case smoothed = "Smoothed"

    var id: String { rawValue }
}

enum SpectrumDisplayRange: String, CaseIterable, Identifiable {
    case lowFrequency = "20–200 Hz"
    case wide = "20–2,000 Hz"

    var id: String { rawValue }

    var frequencyRange: ClosedRange<Double> {
        switch self {
        case .lowFrequency:
            20...200
        case .wide:
            20...2_000
        }
    }

    var frequencyTicks: [Double] {
        switch self {
        case .lowFrequency:
            [20, 50, 100, 150, 200]
        case .wide:
            [20, 500, 1_000, 1_500, 2_000]
        }
    }
}

enum SpectrumGraphScale {
    static let minimumDBFS = -120.0
    static let maximumDBFS = 0.0

    static func bins(
        from bins: [SpectrumBin],
        in displayRange: SpectrumDisplayRange
    ) -> [SpectrumBin] {
        bins.filter { displayRange.frequencyRange.contains($0.frequencyHz) }
    }

    static func xPosition(
        frequencyHz: Double,
        range: ClosedRange<Double>,
        width: Double
    ) -> Double {
        guard width > 0, range.upperBound > range.lowerBound else { return 0 }

        let normalized = (frequencyHz - range.lowerBound) /
            (range.upperBound - range.lowerBound)

        return min(width, max(0, normalized * width))
    }

    static func yPosition(
        dbFS: Double,
        height: Double
    ) -> Double {
        guard height > 0 else { return 0 }

        let clamped = min(maximumDBFS, max(minimumDBFS, dbFS))
        let normalized = (clamped - minimumDBFS) /
            (maximumDBFS - minimumDBFS)

        return height - normalized * height
    }
}

struct SpectrumGraphView: View {
    let bins: [SpectrumBin]
    let displayRange: SpectrumDisplayRange
    let seriesLabel: String

    init(
        bins: [SpectrumBin],
        displayRange: SpectrumDisplayRange,
        seriesLabel: String
    ) {
        self.bins = bins
        self.displayRange = displayRange
        self.seriesLabel = seriesLabel
    }

    private let dbTicks: [Double] = [0, -20, -40, -60, -80, -100, -120]

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let plotInsets = EdgeInsets(top: 8, leading: 42, bottom: 26, trailing: 8)
                let plotWidth = max(
                    1,
                    geometry.size.width - plotInsets.leading - plotInsets.trailing
                )
                let plotHeight = max(
                    1,
                    geometry.size.height - plotInsets.top - plotInsets.bottom
                )
                let visibleBins = SpectrumGraphScale.bins(
                    from: bins,
                    in: displayRange
                )

                Canvas { context, _ in
                    drawGrid(
                        context: &context,
                        plotInsets: plotInsets,
                        plotWidth: plotWidth,
                        plotHeight: plotHeight
                    )

                    drawSpectrum(
                        context: &context,
                        bins: visibleBins,
                        plotInsets: plotInsets,
                        plotWidth: plotWidth,
                        plotHeight: plotHeight
                    )
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Live frequency spectrum")
                .accessibilityValue(accessibilitySummary(visibleBins))
            }
            .frame(height: 240)

            HStack {
                Text(seriesLabel)
                Spacer()
                Text("0 dBFS top • -120 dBFS bottom")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func drawGrid(
        context: inout GraphicsContext,
        plotInsets: EdgeInsets,
        plotWidth: Double,
        plotHeight: Double
    ) {
        let gridStyle = StrokeStyle(lineWidth: 0.5)
        let axisStyle = StrokeStyle(lineWidth: 1)

        for db in dbTicks {
            let y = plotInsets.top + SpectrumGraphScale.yPosition(
                dbFS: db,
                height: plotHeight
            )

            var line = Path()
            line.move(to: CGPoint(x: plotInsets.leading, y: y))
            line.addLine(
                to: CGPoint(
                    x: plotInsets.leading + plotWidth,
                    y: y
                )
            )

            context.stroke(
                line,
                with: .color(Color.primary.opacity(db == 0 || db == -120 ? 0.35 : 0.14)),
                style: db == 0 || db == -120 ? axisStyle : gridStyle
            )

            let label = context.resolve(
                Text(String(format: "%.0f", db))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            )

            context.draw(
                label,
                at: CGPoint(
                    x: plotInsets.leading - 6,
                    y: y
                ),
                anchor: .trailing
            )
        }

        let range = displayRange.frequencyRange

        for frequency in displayRange.frequencyTicks {
            let x = plotInsets.leading + SpectrumGraphScale.xPosition(
                frequencyHz: frequency,
                range: range,
                width: plotWidth
            )

            var line = Path()
            line.move(to: CGPoint(x: x, y: plotInsets.top))
            line.addLine(
                to: CGPoint(
                    x: x,
                    y: plotInsets.top + plotHeight
                )
            )

            context.stroke(
                line,
                with: .color(Color.primary.opacity(0.12)),
                style: gridStyle
            )

            let label = context.resolve(
                Text(frequencyLabel(frequency))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            )

            context.draw(
                label,
                at: CGPoint(
                    x: x,
                    y: plotInsets.top + plotHeight + 14
                ),
                anchor: .center
            )
        }
    }

    private func drawSpectrum(
        context: inout GraphicsContext,
        bins: [SpectrumBin],
        plotInsets: EdgeInsets,
        plotWidth: Double,
        plotHeight: Double
    ) {
        guard !bins.isEmpty else {
            let message = context.resolve(
                Text("Start capture to populate spectrum")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            )

            context.draw(
                message,
                at: CGPoint(
                    x: plotInsets.leading + plotWidth / 2,
                    y: plotInsets.top + plotHeight / 2
                ),
                anchor: .center
            )
            return
        }

        let range = displayRange.frequencyRange
        var path = Path()

        for (index, bin) in bins.enumerated() {
            let x = plotInsets.leading + SpectrumGraphScale.xPosition(
                frequencyHz: bin.frequencyHz,
                range: range,
                width: plotWidth
            )
            let y = plotInsets.top + SpectrumGraphScale.yPosition(
                dbFS: bin.magnitudeDBFS,
                height: plotHeight
            )
            let point = CGPoint(x: x, y: y)

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        context.stroke(
            path,
            with: .color(Color.accentColor),
            style: StrokeStyle(
                lineWidth: 2,
                lineCap: .round,
                lineJoin: .round
            )
        )
    }

    private func frequencyLabel(_ frequency: Double) -> String {
        if frequency >= 1_000 {
            return String(format: "%.1fk", frequency / 1_000)
        }

        return String(format: "%.0f", frequency)
    }

    private func accessibilitySummary(_ visibleBins: [SpectrumBin]) -> String {
        guard !visibleBins.isEmpty else {
            return "No spectrum data yet."
        }

        return "\(visibleBins.count) spectrum bins from " +
            "\(frequencyLabel(displayRange.frequencyRange.lowerBound)) to " +
            "\(frequencyLabel(displayRange.frequencyRange.upperBound)) hertz."
    }
}
