import Foundation

enum AnalysisMode: String, CaseIterable, Identifiable, Equatable, Sendable {
    case ancFocus = "ANC Focus"
    case wideLab = "Wide Lab"

    var id: String { rawValue }

    var frequencyRange: ClosedRange<Double> {
        switch self {
        case .ancFocus:
            30...200
        case .wideLab:
            20...2_000
        }
    }

    var dominantFrequencyRange: ClosedRange<Double> {
        switch self {
        case .ancFocus:
            30...200
        case .wideLab:
            20...200
        }
    }

    var description: String {
        switch self {
        case .ancFocus:
            "30–200 Hz only. Focuses downstream analysis on the road/engine-drone band used by the cancellation experiments."
        case .wideLab:
            "20–2,000 Hz diagnostics. Keeps broader cabin-spectrum context while tone detection remains focused below 200 Hz."
        }
    }

    func filter(_ bins: [SpectrumBin]) -> [SpectrumBin] {
        bins.filter {
            frequencyRange.contains($0.frequencyHz)
        }
    }
}
