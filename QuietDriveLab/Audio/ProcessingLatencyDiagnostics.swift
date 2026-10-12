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

    let latestAnalysisTurnaroundMilliseconds: Double
    let averageAnalysisTurnaroundMilliseconds: Double
    let maximumAnalysisTurnaroundMilliseconds: Double

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
        latestAnalysisTurnaroundMilliseconds: 0,
        averageAnalysisTurnaroundMilliseconds: 0,
        maximumAnalysisTurnaroundMilliseconds: 0,
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

    static func analysisFitsBufferBudget(
        analysisProcessingMilliseconds: Double,
        bufferDurationMilliseconds: Double
    ) -> Bool {
        guard
            analysisProcessingMilliseconds.isFinite,
            bufferDurationMilliseconds.isFinite,
            analysisProcessingMilliseconds >= 0,
            bufferDurationMilliseconds > 0
        else {
            return false
        }

        return
            analysisProcessingMilliseconds <=
                bufferDurationMilliseconds
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
    private var nextExpectedCallbackSequence: UInt64?
    private var pendingCallbackStarts: [UInt64: UInt64] = [:]
    private var latestCallbackIntervalMilliseconds = 0.0
    private var callbackStatistics =
        LatencyRunningStatistics()

    private var latestAnalysisTurnaroundMilliseconds = 0.0
    private var analysisTurnaroundStatistics =
        LatencyRunningStatistics()

    private var latestAnalysisProcessingMilliseconds = 0.0
    private var analysisProcessingStatistics =
        LatencyRunningStatistics()

    private var lastAnalysisCompletedNanoseconds: UInt64?

    mutating func reset() {
        previousCallbackStartNanoseconds = nil
        nextExpectedCallbackSequence = nil
        pendingCallbackStarts.removeAll(keepingCapacity: true)
        latestCallbackIntervalMilliseconds = 0
        callbackStatistics =
            LatencyRunningStatistics()
        latestAnalysisTurnaroundMilliseconds = 0
        analysisTurnaroundStatistics =
            LatencyRunningStatistics()
        latestAnalysisProcessingMilliseconds = 0
        analysisProcessingStatistics =
            LatencyRunningStatistics()
        lastAnalysisCompletedNanoseconds = nil
    }

    mutating func prepareCallbackSequence(
        startingAt sequence: UInt64
    ) {
        nextExpectedCallbackSequence = sequence
        pendingCallbackStarts.removeAll(
            keepingCapacity: true
        )
        previousCallbackStartNanoseconds = nil
        latestCallbackIntervalMilliseconds = 0
        callbackStatistics =
            LatencyRunningStatistics()
    }

    mutating func recordCallbackStart(
        _ callbackStartedNanoseconds: UInt64
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
    }

    mutating func recordCallbackStart(
        sequence: UInt64,
        callbackStartedNanoseconds: UInt64
    ) {
        guard
            let expected =
                nextExpectedCallbackSequence,
            sequence >= expected
        else {
            return
        }

        pendingCallbackStarts[sequence] =
            callbackStartedNanoseconds

        while
            let next =
                nextExpectedCallbackSequence,
            let timestamp =
                pendingCallbackStarts
                    .removeValue(
                        forKey: next
                    )
        {
            recordCallbackStart(timestamp)
            nextExpectedCallbackSequence =
                next &+ 1
        }
    }

    mutating func recordAnalysisTiming(
        callbackStartedNanoseconds: UInt64,
        analysisStartedNanoseconds: UInt64,
        analysisCompletedNanoseconds: UInt64
    ) {
        if
            analysisCompletedNanoseconds >=
                callbackStartedNanoseconds
        {
            let turnaround =
                ProcessingLatencyMath.milliseconds(
                    nanoseconds:
                        analysisCompletedNanoseconds -
                        callbackStartedNanoseconds
                )

            latestAnalysisTurnaroundMilliseconds =
                turnaround
            analysisTurnaroundStatistics.record(
                turnaround
            )
        }

        if
            analysisCompletedNanoseconds >=
                analysisStartedNanoseconds
        {
            let processing =
                ProcessingLatencyMath.milliseconds(
                    nanoseconds:
                        analysisCompletedNanoseconds -
                        analysisStartedNanoseconds
                )

            latestAnalysisProcessingMilliseconds =
                processing
            analysisProcessingStatistics.record(
                processing
            )
        }

        lastAnalysisCompletedNanoseconds =
            analysisCompletedNanoseconds
    }

    mutating func record(
        callbackStartedNanoseconds: UInt64,
        analysisStartedNanoseconds: UInt64,
        analysisCompletedNanoseconds: UInt64
    ) {
        recordCallbackStart(callbackStartedNanoseconds)
        recordAnalysisTiming(
            callbackStartedNanoseconds:
                callbackStartedNanoseconds,
            analysisStartedNanoseconds:
                analysisStartedNanoseconds,
            analysisCompletedNanoseconds:
                analysisCompletedNanoseconds
        )
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
            latestAnalysisTurnaroundMilliseconds:
                latestAnalysisTurnaroundMilliseconds,
            averageAnalysisTurnaroundMilliseconds:
                analysisTurnaroundStatistics
                    .meanMilliseconds,
            maximumAnalysisTurnaroundMilliseconds:
                analysisTurnaroundStatistics
                    .maximumMilliseconds,
            latestAnalysisProcessingMilliseconds:
                latestAnalysisProcessingMilliseconds,
            averageAnalysisProcessingMilliseconds:
                analysisProcessingStatistics
                    .meanMilliseconds,
            maximumAnalysisProcessingMilliseconds:
                analysisProcessingStatistics
                    .maximumMilliseconds,
            fftWindowMilliseconds: fftWindow,
            snapshotAgeMilliseconds: snapshotAge,
            estimatedSpectrumCenterAgeMilliseconds:
                ProcessingLatencyMath
                    .estimatedSpectrumCenterAgeMilliseconds(
                        fftWindowMilliseconds:
                            fftWindow,
                        analysisProcessingMilliseconds:
                            latestAnalysisTurnaroundMilliseconds,
                        snapshotAgeMilliseconds:
                            snapshotAge
                    )
        )
    }
}
