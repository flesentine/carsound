import Foundation

struct LatencyRunningStatistics: Equatable, Sendable {
    private(set) var count: UInt64 = 0
    private(set) var meanMilliseconds = 0.0
    private(set) var minimumMilliseconds = 0.0
    private(set) var maximumMilliseconds = 0.0
    private var m2 = 0.0

    var standardDeviationMilliseconds: Double {
        guard count > 1 else { return 0 }
        return sqrt(
            max(
                0,
                m2 / Double(count - 1)
            )
        )
    }

    mutating func record(
        _ milliseconds: Double
    ) {
        guard
            milliseconds.isFinite,
            milliseconds >= 0
        else {
            return
        }

        count += 1

        if count == 1 {
            meanMilliseconds = milliseconds
            minimumMilliseconds = milliseconds
            maximumMilliseconds = milliseconds
            m2 = 0
            return
        }

        minimumMilliseconds = min(
            minimumMilliseconds,
            milliseconds
        )
        maximumMilliseconds = max(
            maximumMilliseconds,
            milliseconds
        )

        let delta =
            milliseconds - meanMilliseconds
        meanMilliseconds +=
            delta / Double(count)
        let delta2 =
            milliseconds - meanMilliseconds
        m2 += delta * delta2
    }
}

struct ProcessingLatencySnapshot: Equatable, Sendable {
    let latestCallbackIntervalMilliseconds: Double
    let averageCallbackIntervalMilliseconds: Double
    let callbackJitterMilliseconds: Double
    let minimumCallbackIntervalMilliseconds: Double
    let maximumCallbackIntervalMilliseconds: Double

    let latestAnalysisProcessingMilliseconds: Double
    let averageAnalysisProcessingMilliseconds: Double
    let maximumAnalysisProcessingMilliseconds: Double

    let fftWindowMilliseconds: Double
    let snapshotAgeMilliseconds: Double
    let estimatedSpectrumCenterAgeMilliseconds: Double

    static let empty = ProcessingLatencySnapshot(
        latestCallbackIntervalMilliseconds: 0,
        averageCallbackIntervalMilliseconds: 0,
        callbackJitterMilliseconds: 0,
        minimumCallbackIntervalMilliseconds: 0,
        maximumCallbackIntervalMilliseconds: 0,
        latestAnalysisProcessingMilliseconds: 0,
        averageAnalysisProcessingMilliseconds: 0,
        maximumAnalysisProcessingMilliseconds: 0,
        fftWindowMilliseconds: 0,
        snapshotAgeMilliseconds: 0,
        estimatedSpectrumCenterAgeMilliseconds: 0
    )
}

enum ProcessingLatencyMath {
    static func milliseconds(
        nanoseconds: UInt64
    ) -> Double {
        Double(nanoseconds) / 1_000_000.0
    }

    static func fftWindowMilliseconds(
        sampleCount: Int,
        sampleRate: Double
    ) -> Double {
        guard
            sampleCount > 0,
            sampleRate > 0
        else {
            return 0
        }

        return
            Double(sampleCount) /
            sampleRate *
            1_000.0
    }

    static func estimatedSpectrumCenterAgeMilliseconds(
        fftWindowMilliseconds: Double,
        analysisProcessingMilliseconds: Double,
        snapshotAgeMilliseconds: Double
    ) -> Double {
        max(0, fftWindowMilliseconds) / 2.0 +
        max(0, analysisProcessingMilliseconds) +
        max(0, snapshotAgeMilliseconds)
    }
}

struct ProcessingLatencyTracker: Sendable {
    private var previousCallbackStartNanoseconds: UInt64?
    private var latestCallbackIntervalMilliseconds = 0.0
    private var callbackStatistics =
        LatencyRunningStatistics()

    private var latestAnalysisProcessingMilliseconds = 0.0
    private var analysisStatistics =
        LatencyRunningStatistics()

    private var lastAnalysisCompletedNanoseconds: UInt64?

    mutating func reset() {
        previousCallbackStartNanoseconds = nil
        latestCallbackIntervalMilliseconds = 0
        callbackStatistics =
            LatencyRunningStatistics()
        latestAnalysisProcessingMilliseconds = 0
        analysisStatistics =
            LatencyRunningStatistics()
        lastAnalysisCompletedNanoseconds = nil
    }

    mutating func record(
        callbackStartedNanoseconds: UInt64,
        analysisCompletedNanoseconds: UInt64
    ) {
        if
            let previous =
                previousCallbackStartNanoseconds,
            callbackStartedNanoseconds >= previous
        {
            let interval =
                ProcessingLatencyMath.milliseconds(
                    nanoseconds:
                        callbackStartedNanoseconds -
                        previous
                )

            latestCallbackIntervalMilliseconds =
                interval
            callbackStatistics.record(interval)
        }

        previousCallbackStartNanoseconds =
            callbackStartedNanoseconds

        if
            analysisCompletedNanoseconds >=
                callbackStartedNanoseconds
        {
            let processing =
                ProcessingLatencyMath.milliseconds(
                    nanoseconds:
                        analysisCompletedNanoseconds -
                        callbackStartedNanoseconds
                )

            latestAnalysisProcessingMilliseconds =
                processing
            analysisStatistics.record(processing)
        }

        lastAnalysisCompletedNanoseconds =
            analysisCompletedNanoseconds
    }

    func snapshot(
        nowNanoseconds: UInt64,
        fftSampleCount: Int,
        sampleRate: Double
    ) -> ProcessingLatencySnapshot {
        let snapshotAge: Double

        if
            let completed =
                lastAnalysisCompletedNanoseconds,
            nowNanoseconds >= completed
        {
            snapshotAge =
                ProcessingLatencyMath.milliseconds(
                    nanoseconds:
                        nowNanoseconds - completed
                )
        } else {
            snapshotAge = 0
        }

        let fftWindow =
            ProcessingLatencyMath
                .fftWindowMilliseconds(
                    sampleCount: fftSampleCount,
                    sampleRate: sampleRate
                )

        return ProcessingLatencySnapshot(
            latestCallbackIntervalMilliseconds:
                latestCallbackIntervalMilliseconds,
            averageCallbackIntervalMilliseconds:
                callbackStatistics
                    .meanMilliseconds,
            callbackJitterMilliseconds:
                callbackStatistics
                    .standardDeviationMilliseconds,
            minimumCallbackIntervalMilliseconds:
                callbackStatistics
                    .minimumMilliseconds,
            maximumCallbackIntervalMilliseconds:
                callbackStatistics
                    .maximumMilliseconds,
            latestAnalysisProcessingMilliseconds:
                latestAnalysisProcessingMilliseconds,
            averageAnalysisProcessingMilliseconds:
                analysisStatistics
                    .meanMilliseconds,
            maximumAnalysisProcessingMilliseconds:
                analysisStatistics
                    .maximumMilliseconds,
            fftWindowMilliseconds: fftWindow,
            snapshotAgeMilliseconds: snapshotAge,
            estimatedSpectrumCenterAgeMilliseconds:
                ProcessingLatencyMath
                    .estimatedSpectrumCenterAgeMilliseconds(
                        fftWindowMilliseconds:
                            fftWindow,
                        analysisProcessingMilliseconds:
                            latestAnalysisProcessingMilliseconds,
                        snapshotAgeMilliseconds:
                            snapshotAge
                    )
        )
    }
}
