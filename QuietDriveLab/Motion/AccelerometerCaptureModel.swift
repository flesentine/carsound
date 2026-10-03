import CoreMotion
import Foundation
import Observation

struct AccelerometerSample: Equatable, Sendable {
    let timestampSeconds: TimeInterval
    let xG: Double
    let yG: Double
    let zG: Double

    var magnitudeG: Double {
        sqrt(
            xG * xG +
            yG * yG +
            zG * zG
        )
    }
}

enum AccelerometerMath {
    static func observedSampleRateHz(
        averageIntervalMilliseconds: Double
    ) -> Double {
        guard averageIntervalMilliseconds > 0 else {
            return 0
        }

        return 1_000.0 /
            averageIntervalMilliseconds
    }
}

struct AccelerometerCaptureSnapshot: Equatable, Sendable {
    let totalSampleCount: UInt64
    let storedSampleCount: Int
    let latestSample: AccelerometerSample?
    let elapsedSeconds: Double

    let averageIntervalMilliseconds: Double
    let intervalJitterMilliseconds: Double
    let minimumIntervalMilliseconds: Double
    let maximumIntervalMilliseconds: Double
    let observedSampleRateHz: Double

    static let empty =
        AccelerometerCaptureSnapshot(
            totalSampleCount: 0,
            storedSampleCount: 0,
            latestSample: nil,
            elapsedSeconds: 0,
            averageIntervalMilliseconds: 0,
            intervalJitterMilliseconds: 0,
            minimumIntervalMilliseconds: 0,
            maximumIntervalMilliseconds: 0,
            observedSampleRateHz: 0
        )
}

struct AccelerometerRingBuffer: Sendable {
    private var storage: [AccelerometerSample?]
    private var nextIndex = 0
    private(set) var count = 0

    let capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage = Array(
            repeating: nil,
            count: max(1, capacity)
        )
    }

    mutating func append(
        _ sample: AccelerometerSample
    ) {
        storage[nextIndex] = sample
        nextIndex =
            (nextIndex + 1) % capacity
        count = min(count + 1, capacity)
    }

    mutating func reset() {
        storage = Array(
            repeating: nil,
            count: capacity
        )
        nextIndex = 0
        count = 0
    }

    func orderedSamples() -> [AccelerometerSample] {
        guard count > 0 else {
            return []
        }

        if count < capacity {
            return storage[0..<count]
                .compactMap { $0 }
        }

        return (
            Array(storage[nextIndex..<capacity]) +
            Array(storage[0..<nextIndex])
        )
        .compactMap { $0 }
    }
}

final class AccelerometerSampleStore:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var samples: AccelerometerRingBuffer

    private var totalSampleCount: UInt64 = 0
    private var latestSample: AccelerometerSample?
    private var firstTimestampSeconds: TimeInterval?
    private var previousTimestampSeconds: TimeInterval?

    private var intervalStatistics =
        LatencyRunningStatistics()

    private var errorMessage: String?

    init(capacity: Int = 4_096) {
        samples =
            AccelerometerRingBuffer(
                capacity: capacity
            )
    }

    func record(
        timestampSeconds: TimeInterval,
        xG: Double,
        yG: Double,
        zG: Double
    ) {
        let sample = AccelerometerSample(
            timestampSeconds: timestampSeconds,
            xG: xG,
            yG: yG,
            zG: zG
        )

        lock.lock()
        defer { lock.unlock() }

        if firstTimestampSeconds == nil {
            firstTimestampSeconds =
                timestampSeconds
        }

        if
            let previousTimestampSeconds,
            timestampSeconds >=
                previousTimestampSeconds
        {
            intervalStatistics.record(
                (
                    timestampSeconds -
                    previousTimestampSeconds
                ) * 1_000
            )
        }

        previousTimestampSeconds =
            timestampSeconds
        totalSampleCount &+= 1
        latestSample = sample
        samples.append(sample)
    }

    func recordError(
        _ message: String
    ) {
        lock.lock()
        errorMessage = message
        lock.unlock()
    }

    func consumeError() -> String? {
        lock.lock()
        defer { lock.unlock() }

        let message = errorMessage
        errorMessage = nil
        return message
    }

    func snapshot() -> AccelerometerCaptureSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let elapsed: Double

        if
            let firstTimestampSeconds,
            let latestSample
        {
            elapsed = max(
                0,
                latestSample.timestampSeconds -
                firstTimestampSeconds
            )
        } else {
            elapsed = 0
        }

        return AccelerometerCaptureSnapshot(
            totalSampleCount:
                totalSampleCount,
            storedSampleCount:
                samples.count,
            latestSample:
                latestSample,
            elapsedSeconds:
                elapsed,
            averageIntervalMilliseconds:
                intervalStatistics
                    .meanMilliseconds,
            intervalJitterMilliseconds:
                intervalStatistics
                    .standardDeviationMilliseconds,
            minimumIntervalMilliseconds:
                intervalStatistics
                    .minimumMilliseconds,
            maximumIntervalMilliseconds:
                intervalStatistics
                    .maximumMilliseconds,
            observedSampleRateHz:
                AccelerometerMath
                    .observedSampleRateHz(
                        averageIntervalMilliseconds:
                            intervalStatistics
                                .meanMilliseconds
                    )
        )
    }

    func recentSamples() -> [AccelerometerSample] {
        lock.lock()
        defer { lock.unlock() }

        return samples.orderedSamples()
    }

    func reset() {
        lock.lock()
        samples.reset()
        totalSampleCount = 0
        latestSample = nil
        firstTimestampSeconds = nil
        previousTimestampSeconds = nil
        intervalStatistics =
            LatencyRunningStatistics()
        errorMessage = nil
        lock.unlock()
    }
}

@MainActor
@Observable
final class AccelerometerCaptureModel {
    enum State: Equatable {
        case stopped
        case capturing
        case unavailable
        case failed(String)

        var label: String {
            switch self {
            case .stopped:
                return "Stopped"
            case .capturing:
                return "Capturing"
            case .unavailable:
                return "Unavailable"
            case .failed:
                return "Failed"
            }
        }
    }

    static let requestedSampleRateHz = 200.0
    static let requestedUpdateInterval =
        1.0 / requestedSampleRateHz
    static let retainedSampleCapacity = 4_096

    private(set) var state: State = .stopped
    private(set) var snapshot:
        AccelerometerCaptureSnapshot = .empty
    private(set) var vibrationSpectrum:
        VibrationSpectrumSnapshot = .empty

    @ObservationIgnored
    private let motionManager =
        CMMotionManager()

    @ObservationIgnored
    private let sampleStore =
        AccelerometerSampleStore(
            capacity: retainedSampleCapacity
        )

    @ObservationIgnored
    private let updateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name =
            "QuietDriveLab.Accelerometer"
        queue.qualityOfService =
            .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    @ObservationIgnored
    private var publishTask:
        Task<Void, Never>?

    var isAvailable: Bool {
        motionManager.isAccelerometerAvailable
    }

    func start() {
        guard state != .capturing else {
            return
        }

        guard motionManager.isAccelerometerAvailable else {
            state = .unavailable
            snapshot = .empty
            return
        }

        sampleStore.reset()
        snapshot = .empty
        vibrationSpectrum = .empty

        motionManager.accelerometerUpdateInterval =
            Self.requestedUpdateInterval

        let store = sampleStore

        motionManager.startAccelerometerUpdates(
            to: updateQueue
        ) { data, error in
            if let error {
                store.recordError(
                    error.localizedDescription
                )
                return
            }

            guard let data else {
                return
            }

            store.record(
                timestampSeconds:
                    data.timestamp,
                xG:
                    data.acceleration.x,
                yG:
                    data.acceleration.y,
                zG:
                    data.acceleration.z
            )
        }

        state = .capturing
        startPublishing()
    }

    func stop() {
        motionManager.stopAccelerometerUpdates()
        publishTask?.cancel()
        publishTask = nil
        snapshot = sampleStore.snapshot()

        if state == .capturing {
            state = .stopped
        }
    }

    func reset() {
        stop()
        sampleStore.reset()
        snapshot = .empty
        vibrationSpectrum = .empty
        state = .stopped
    }

    func recentSamples() -> [AccelerometerSample] {
        sampleStore.recentSamples()
    }

    private func startPublishing() {
        publishTask?.cancel()

        publishTask = Task { @MainActor [weak self] in
            var tick = 0

            while
                let self,
                !Task.isCancelled,
                self.state == .capturing
            {
                self.snapshot =
                    self.sampleStore.snapshot()

                if
                    let message =
                        self.sampleStore
                            .consumeError()
                {
                    self.motionManager
                        .stopAccelerometerUpdates()
                    self.state =
                        .failed(message)
                    return
                }

                if tick.isMultiple(of: 3) {
                    let samples =
                        self.sampleStore
                            .recentSamples()

                    self.vibrationSpectrum =
                        await Task.detached(
                            priority: .userInitiated
                        ) {
                            VibrationSpectrumAnalyzer
                                .analyze(
                                    samples: samples
                                )
                        }
                        .value
                }

                tick &+= 1

                try? await Task.sleep(
                    nanoseconds: 100_000_000
                )
            }
        }
    }
}
