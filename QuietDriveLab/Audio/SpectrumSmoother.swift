import Foundation

enum SpectrumSmoothingPreset: String, CaseIterable, Identifiable, Hashable, Sendable {
    case responsive = "Responsive"
    case balanced = "Balanced"
    case stable = "Stable"

    var id: String { rawValue }

    var alpha: Double {
        switch self {
        case .responsive:
            0.35
        case .balanced:
            0.15
        case .stable:
            0.06
        }
    }

    var description: String {
        switch self {
        case .responsive:
            "Tracks changes quickly with light temporal smoothing."
        case .balanced:
            "Reduces FFT flicker while still following changing road noise."
        case .stable:
            "Heavier smoothing for steady low-frequency drone."
        }
    }
}

struct SmoothedSpectrumSnapshot: Equatable, Sendable {
    let responsive: [SpectrumBin]
    let balanced: [SpectrumBin]
    let stable: [SpectrumBin]

    static let empty = SmoothedSpectrumSnapshot(
        responsive: [],
        balanced: [],
        stable: []
    )

    func bins(for preset: SpectrumSmoothingPreset) -> [SpectrumBin] {
        switch preset {
        case .responsive:
            responsive
        case .balanced:
            balanced
        case .stable:
            stable
        }
    }
}

final class SpectrumSmoothingBank {
    private var smoothers: [SpectrumSmoothingPreset: SpectrumSmoother] = {
        Dictionary(
            uniqueKeysWithValues: SpectrumSmoothingPreset.allCases.map {
                ($0, SpectrumSmoother(alpha: $0.alpha))
            }
        )
    }()

    func reset() {
        for smoother in smoothers.values {
            smoother.reset()
        }
    }

    func process(_ bins: [SpectrumBin]) -> SmoothedSpectrumSnapshot {
        SmoothedSpectrumSnapshot(
            responsive: smoothers[.responsive]?.process(bins) ?? bins,
            balanced: smoothers[.balanced]?.process(bins) ?? bins,
            stable: smoothers[.stable]?.process(bins) ?? bins
        )
    }
}

final class SpectrumSmoother {
    private let alpha: Double
    private var powerState: [Double] = []
    private var frequencies: [Double] = []

    init(alpha: Double) {
        precondition(alpha > 0 && alpha <= 1, "Smoothing alpha must be in (0, 1]")
        self.alpha = alpha
    }

    func reset() {
        powerState.removeAll(keepingCapacity: true)
        frequencies.removeAll(keepingCapacity: true)
    }

    func process(_ bins: [SpectrumBin]) -> [SpectrumBin] {
        guard !bins.isEmpty else {
            reset()
            return []
        }

        if shouldReset(for: bins) {
            frequencies = bins.map(\.frequencyHz)
            powerState = bins.map { Self.power(fromDBFS: $0.magnitudeDBFS) }
            return bins
        }

        var result = [SpectrumBin]()
        result.reserveCapacity(bins.count)

        for index in bins.indices {
            let currentPower = Self.power(fromDBFS: bins[index].magnitudeDBFS)
            let smoothedPower =
                alpha * currentPower +
                (1.0 - alpha) * powerState[index]

            powerState[index] = smoothedPower

            result.append(
                SpectrumBin(
                    frequencyHz: bins[index].frequencyHz,
                    magnitudeDBFS: Self.dbFS(fromPower: smoothedPower)
                )
            )
        }

        return result
    }

    private func shouldReset(for bins: [SpectrumBin]) -> Bool {
        guard bins.count == powerState.count, bins.count == frequencies.count else {
            return true
        }

        guard let first = bins.first, let last = bins.last else {
            return true
        }

        return abs(first.frequencyHz - frequencies[0]) > 0.0001 ||
            abs(last.frequencyHz - frequencies[frequencies.count - 1]) > 0.0001
    }

    private static func power(fromDBFS dbFS: Double) -> Double {
        pow(10.0, dbFS / 10.0)
    }

    private static func dbFS(fromPower power: Double) -> Double {
        guard power > 0 else { return FFTAnalyzer.magnitudeFloorDBFS }
        return max(
            FFTAnalyzer.magnitudeFloorDBFS,
            10.0 * log10(power)
        )
    }
}
