import SwiftUI

struct VibrationSpectrumView: View {
    let snapshot: VibrationSpectrumSnapshot

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard
                    !snapshot.bins.isEmpty,
                    snapshot.maximumAnalyzedFrequencyHz >
                        VibrationSpectrumAnalyzer
                            .minimumAnalyzedFrequencyHz
                else {
                    let text = context.resolve(
                        Text("Collect at least 256 motion samples")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    )
                    context.draw(
                        text,
                        at: CGPoint(
                            x: size.width / 2,
                            y: size.height / 2
                        ),
                        anchor: .center
                    )
                    return
                }

                let maxAmplitude = max(
                    snapshot.bins
                        .map(\.amplitudeMilliG)
                        .max() ?? 1,
                    0.001
                )
                let minFrequency =
                    VibrationSpectrumAnalyzer
                        .minimumAnalyzedFrequencyHz
                let maxFrequency =
                    snapshot.maximumAnalyzedFrequencyHz

                var path = Path()

                for (index, bin) in
                    snapshot.bins.enumerated()
                {
                    let x =
                        (
                            bin.frequencyHz -
                            minFrequency
                        ) /
                        (
                            maxFrequency -
                            minFrequency
                        ) *
                        size.width
                    let y =
                        size.height -
                        (
                            bin.amplitudeMilliG /
                            maxAmplitude
                        ) *
                        size.height

                    let point = CGPoint(
                        x: x,
                        y: y
                    )

                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }

                context.stroke(
                    path,
                    with: .color(.accentColor),
                    style: StrokeStyle(
                        lineWidth: 2,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
        .frame(height: 180)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vibration frequency spectrum")
        .accessibilityValue(
            snapshot.dominantPeaks.isEmpty
                ? "No dominant vibration peaks detected."
                : snapshot.dominantPeaks
                    .prefix(3)
                    .map {
                        String(
                            format:
                                "%.1f hertz %.2f milli-g",
                            $0.frequencyHz,
                            $0.amplitudeMilliG
                        )
                    }
                    .joined(separator: ", ")
        )
    }
}
