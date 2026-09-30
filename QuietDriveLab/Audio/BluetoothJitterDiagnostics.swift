import Foundation
import Observation

enum BluetoothTimingStability: String, Equatable, Sendable {
    case insufficientData = "Insufficient data"
    case stable = "Stable observed timing"
    case variable = "Variable observed timing"
    case unstable = "Unstable observed timing"
}

struct BluetoothJitterSample: Equatable, Sendable {
    let capturedAtSeconds: Double
    let fftTransformCount: UInt64
    let profile: BluetoothProfile
    let routeRevision: UInt64
    let sampleRate: Double
    let ioBufferMilliseconds: Double
    let inputLatencyMilliseconds: Double
    let outputLatencyMilliseconds: Double
    let callbackIntervalMilliseconds: Double
    let spectrumCenterAgeMilliseconds: Double
}

struct BluetoothJitterSnapshot: Equatable, Sendable {
    let sampleCount: Int
    let elapsedSeconds: Double
    let profile: BluetoothProfile
    let stability: BluetoothTimingStability

    let callbackMeanMilliseconds: Double
    let callbackJitterMilliseconds: Double
    let callbackRangeMilliseconds: Double

    let spectrumCenterAgeMeanMilliseconds: Double
    let spectrumCenterAgeJitterMilliseconds: Double
    let spectrumCenterAgeRangeMilliseconds: Double

    let outputLatencyMeanMilliseconds: Double
    let outputLatencyJitterMilliseconds: Double
    let outputLatencyRangeMilliseconds: Double

    let ioBufferChangeCount: Int
    let sampleRateChangeCount: Int
    let routeRevisionChangeCount: Int
    let profileChangeCount: Int
}

enum BluetoothJitterMath {
    static let minimumSamplesForAssessment = 8
    static let stableCallbackJitterMilliseconds = 1.0
    static let variableCallbackJitterMilliseconds = 3.0
    static let stableSpectrumAgeJitterMilliseconds = 5.0
    static let variableSpectrumAgeJitterMilliseconds = 15.0

    static func snapshot(
        samples: [BluetoothJitterSample]
    ) -> BluetoothJitterSnapshot? {
        guard !samples.isEmpty else {
            return nil
        }

        let callback = statistics(
            samples.map(
                \.callbackIntervalMilliseconds
            )
        )
        let centerAge = statistics(
            samples.map(
                \.spectrumCenterAgeMilliseconds
            )
        )
        let outputLatency = statistics(
            samples.map(
                \.outputLatencyMilliseconds
            )
        )

        let ioBufferChanges = adjacentChangeCount(
            samples.map(\.ioBufferMilliseconds),
            tolerance: 0.001
        )
        let sampleRateChanges = adjacentChangeCount(
            samples.map(\.sampleRate),
            tolerance: 0.5
        )
        let routeChanges = adjacentChangeCount(
            samples.map(\.routeRevision)
        )
        let profileChanges = adjacentChangeCount(
            samples.map(\.profile)
        )

        let stability = assessStability(
            sampleCount: samples.count,
            callbackJitterMilliseconds:
                callback.standardDeviation,
            spectrumCenterAgeJitterMilliseconds:
                centerAge.standardDeviation,
            routeRevisionChangeCount: routeChanges,
            profileChangeCount: profileChanges,
            ioBufferChangeCount: ioBufferChanges,
            sampleRateChangeCount: sampleRateChanges
        )

        return BluetoothJitterSnapshot(
            sampleCount: samples.count,
            elapsedSeconds:
                max(
                    0,
                    (samples.last?.capturedAtSeconds ?? 0) -
                    (samples.first?.capturedAtSeconds ?? 0)
                ),
            profile: samples.last?.profile ?? .none,
            stability: stability,
            callbackMeanMilliseconds:
                callback.mean,
            callbackJitterMilliseconds:
                callback.standardDeviation,
            callbackRangeMilliseconds:
                callback.range,
            spectrumCenterAgeMeanMilliseconds:
                centerAge.mean,
            spectrumCenterAgeJitterMilliseconds:
                centerAge.standardDeviation,
            spectrumCenterAgeRangeMilliseconds:
                centerAge.range,
            outputLatencyMeanMilliseconds:
                outputLatency.mean,
            outputLatencyJitterMilliseconds:
                outputLatency.standardDeviation,
            outputLatencyRangeMilliseconds:
                outputLatency.range,
            ioBufferChangeCount: ioBufferChanges,
            sampleRateChangeCount: sampleRateChanges,
            routeRevisionChangeCount: routeChanges,
            profileChangeCount: profileChanges
        )
    }

    static func assessStability(
        sampleCount: Int,
        callbackJitterMilliseconds: Double,
        spectrumCenterAgeJitterMilliseconds: Double,
        routeRevisionChangeCount: Int,
        profileChangeCount: Int,
        ioBufferChangeCount: Int,
        sampleRateChangeCount: Int
    ) -> BluetoothTimingStability {
        guard sampleCount >= minimumSamplesForAssessment else {
            return .insufficientData
        }

        if
            routeRevisionChangeCount > 0 ||
            profileChangeCount > 0 ||
            ioBufferChangeCount > 0 ||
            sampleRateChangeCount > 0 ||
            callbackJitterMilliseconds >
                variableCallbackJitterMilliseconds ||
            spectrumCenterAgeJitterMilliseconds >
                variableSpectrumAgeJitterMilliseconds
        {
            return .unstable
        }

        if
            callbackJitterMilliseconds >
                stableCallbackJitterMilliseconds ||
            spectrumCenterAgeJitterMilliseconds >
                stableSpectrumAgeJitterMilliseconds
        {
            return .variable
        }

        return .stable
    }

    private static func statistics(
        _ values: [Double]
    ) -> (
        mean: Double,
        standardDeviation: Double,
        range: Double
    ) {
        guard !values.isEmpty else {
            return (0, 0, 0)
        }

        let mean =
            values.reduce(0, +) /
            Double(values.count)

        let variance: Double
        if values.count > 1 {
            variance =
                values.reduce(0.0) {
                    partial, value in
                    let delta = value - mean
                    return partial + delta * delta
                } /
                Double(values.count - 1)
        } else {
            variance = 0
        }

        return (
            mean,
            sqrt(max(0, variance)),
            (values.max() ?? 0) -
                (values.min() ?? 0)
        )
    }

    private static func adjacentChangeCount(
        _ values: [Double],
        tolerance: Double
    ) -> Int {
        guard values.count > 1 else {
            return 0
        }

        var count = 0
        for index in 1..<values.count {
            if
                abs(
                    values[index] -
                    values[index - 1]
                ) > tolerance
            {
                count += 1
            }
        }

        return count
    }

    private static func adjacentChangeCount<T: Equatable>(
        _ values: [T]
    ) -> Int {
        guard values.count > 1 else {
            return 0
        }

        var count = 0
        for index in 1..<values.count {
            if values[index] != values[index - 1] {
                count += 1
            }
        }

        return count
    }
}

@MainActor
@Observable
final class BluetoothJitterDiagnosticsModel {
    enum State: Equatable {
        case idle
        case running
        case completed
        case failed(String)

        var isRunning: Bool {
            self == .running
        }
    }

    static let sampleIntervalSeconds = 0.25
    static let maximumSamples = 120
    static let maximumConsecutiveStalePolls = 12

    private(set) var state: State = .idle
    private(set) var samples: [BluetoothJitterSample] = []
    private(set) var snapshot: BluetoothJitterSnapshot?

    private var generation: UInt64 = 0

    func reset() {
        generation += 1
        state = .idle
        samples = []
        snapshot = nil
    }

    func stop() {
        generation += 1
        state = samples.isEmpty
            ? .idle
            : .completed
        snapshot =
            BluetoothJitterMath.snapshot(
                samples: samples
            )
    }

    func run(
        sampleProvider:
            @escaping @MainActor
            () -> BluetoothJitterSample?,
        safetyCheck:
            @escaping @MainActor
            () -> String?
    ) async {
        guard !state.isRunning else {
            return
        }

        generation += 1
        let currentGeneration = generation

        samples = []
        snapshot = nil
        state = .running

        var lastFFTTransformCount: UInt64?
        var consecutiveStalePolls = 0

        while
            currentGeneration == generation,
            !Task.isCancelled,
            samples.count < Self.maximumSamples
        {
            if let reason = safetyCheck() {
                state = .failed(reason)
                generation += 1
                return
            }

            if let sample = sampleProvider() {
                if
                    lastFFTTransformCount == nil ||
                    sample.fftTransformCount >
                        (lastFFTTransformCount ?? 0)
                {
                    lastFFTTransformCount =
                        sample.fftTransformCount
                    consecutiveStalePolls = 0
                    samples.append(sample)
                    snapshot =
                        BluetoothJitterMath.snapshot(
                            samples: samples
                        )
                } else {
                    consecutiveStalePolls += 1

                    if
                        consecutiveStalePolls >=
                            Self.maximumConsecutiveStalePolls
                    {
                        state = .failed(
                            "Fresh FFT measurements stopped arriving."
                        )
                        generation += 1
                        return
                    }
                }
            } else {
                consecutiveStalePolls += 1

                if
                    consecutiveStalePolls >=
                        Self.maximumConsecutiveStalePolls
                {
                    state = .failed(
                        "Bluetooth timing samples became unavailable."
                    )
                    generation += 1
                    return
                }
            }

            try? await Task.sleep(
                nanoseconds: UInt64(
                    Self.sampleIntervalSeconds *
                    1_000_000_000
                )
            )
        }

        guard currentGeneration == generation else {
            return
        }

        state = .completed
        snapshot =
            BluetoothJitterMath.snapshot(
                samples: samples
            )
    }
}
