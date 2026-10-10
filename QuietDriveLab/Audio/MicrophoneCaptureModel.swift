import AVFAudio
import Foundation
import Observation

@MainActor
@Observable
final class MicrophoneCaptureModel {
    enum State: Equatable {
        case stopped
        case capturing
        case failed(String)

        var label: String {
            switch self {
            case .stopped: "Stopped"
            case .capturing: "Capturing"
            case .failed: "Error"
            }
        }
    }

    struct Snapshot: Equatable, Sendable {
        let bufferCount: UInt64
        let frameCount: UInt64
        let analysisDroppedBufferCount: UInt64
        let analysisDroppedFrameCount: UInt64
        let lastBufferFrames: AVAudioFrameCount
        let sampleRate: Double
        let channelCount: AVAudioChannelCount
        let formatDescription: String
        let rmsLinear: Float
        let peakLinear: Float
        let peakHoldLinear: Float
        let rmsDBFS: Double
        let peakDBFS: Double
        let peakHoldDBFS: Double
        let lastBufferClippedSampleCount: UInt64
        let totalClippedSampleCount: UInt64
        let isClipping: Bool
        let bufferDurationMilliseconds: Double
        let fftSampleCount: Int
        let fftTransformCount: UInt64
        let fftResolutionHz: Double
        let fftWindowName: String
        let spectrumBins: [SpectrumBin]
        let smoothedSpectrum: SmoothedSpectrumSnapshot
        let noiseFloor: NoiseFloorSnapshot
        let dominantFrequencies: DominantFrequencySnapshot
        let persistentTones: PersistentToneSnapshot
        let processingLatency: ProcessingLatencySnapshot
        let musicInterference: MusicInterferenceSnapshot

        static let empty = Snapshot(
            bufferCount: 0,
            frameCount: 0,
            analysisDroppedBufferCount: 0,
            analysisDroppedFrameCount: 0,
            lastBufferFrames: 0,
            sampleRate: 0,
            channelCount: 0,
            formatDescription: "—",
            rmsLinear: 0,
            peakLinear: 0,
            peakHoldLinear: 0,
            rmsDBFS: AudioLevelAnalyzer.silenceFloorDBFS,
            peakDBFS: AudioLevelAnalyzer.silenceFloorDBFS,
            peakHoldDBFS: AudioLevelAnalyzer.silenceFloorDBFS,
            lastBufferClippedSampleCount: 0,
            totalClippedSampleCount: 0,
            isClipping: false,
            bufferDurationMilliseconds: 0,
            fftSampleCount: 0,
            fftTransformCount: 0,
            fftResolutionHz: 0,
            fftWindowName: FFTAnalyzer.windowName,
            spectrumBins: [],
            smoothedSpectrum: .empty,
            noiseFloor: .empty,
            dominantFrequencies: .empty,
            persistentTones: .empty,
            processingLatency: .empty,
            musicInterference: .empty
        )
    }

    private(set) var state: State = .stopped
    private(set) var snapshot: Snapshot = .empty
    private(set) var analysisMode: AnalysisMode = .ancFocus

    @ObservationIgnored
    private let stats = CaptureStatsStore()

    @ObservationIgnored
    private let engine = AVAudioEngine()

    @ObservationIgnored
    private var pollingTask: Task<Void, Never>?

    @ObservationIgnored
    private var tapInstalled = false

    func beginCapture() -> UInt64 {
        reset()

        lock.lock()
        captureGeneration &+= 1
        captureIsActive = true
        let generation = captureGeneration
        lock.unlock()

        return generation
    }

    func endCapture() {
        lock.lock()
        captureIsActive = false
        lock.unlock()
    }

    func setAnalysisMode(_ mode: AnalysisMode) {
        guard state != .capturing, mode != analysisMode else { return }

        analysisMode = mode
        stats.setAnalysisMode(mode)
        snapshot = stats.snapshot()
    }

    func startCapture() {
        guard state != .capturing else { return }

        stopCapture()
        stats.setAnalysisMode(analysisMode)

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            state = .failed("No usable microphone input format is available.")
            return
        }

        let captureGeneration =
            stats.beginCapture()

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format
        ) { [stats, captureGeneration] buffer, _ in
            stats.record(
                buffer: buffer,
                captureGeneration:
                    captureGeneration
            )
        }
        tapInstalled = true

        engine.prepare()

        do {
            try engine.start()
            state = .capturing
            snapshot = stats.snapshot()
            startPolling()
        } catch {
            stats.endCapture()
            removeTapIfNeeded()
            engine.stop()
            state = .failed(error.localizedDescription)
        }
    }

    func stopCapture() {
        pollingTask?.cancel()
        pollingTask = nil

        stats.endCapture()
        removeTapIfNeeded()

        if engine.isRunning {
            engine.stop()
        }

        if state == .capturing {
            state = .stopped
        }

        stats.flushPendingAnalysis()
        snapshot = stats.snapshot()
    }

    func resetCounters() {
        stats.reset()
        snapshot = .empty
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled, let self else { return }
                self.snapshot = self.stats.snapshot()
            }
        }
    }

    private func removeTapIfNeeded() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }
}

private final class CaptureStatsStore: @unchecked Sendable {
    private let lock = NSLock()
    private let analysisQueue =
        DispatchQueue(
            label: "com.quietdrive.lab.audio-analysis",
            qos: .userInitiated
        )
    private let frameHandoff =
        RealtimeAudioFrameHandoff(
            capacity: 4,
            maxFrameCount: 8_192
        )

    private lazy var analysisSource: DispatchSourceUserDataAdd = {
        let source =
            DispatchSource.makeUserDataAddSource(
                queue: analysisQueue
            )
        source.setEventHandler { [weak self] in
            self?.drainReadyFrames()
        }
        source.resume()
        return source
    }()

    private var analysisMode: AnalysisMode = .ancFocus
    private var captureGeneration: UInt64 = 0
    private var captureIsActive = false
    private var bufferCount: UInt64 = 0
    private var frameCount: UInt64 = 0
    private var analysisDroppedBufferCount: UInt64 = 0
    private var analysisDroppedFrameCount: UInt64 = 0
    private var lastBufferFrames: AVAudioFrameCount = 0
    private var sampleRate: Double = 0
    private var channelCount: AVAudioChannelCount = 0
    private var formatDescription = "—"
    private var rmsLinear: Float = 0
    private var peakLinear: Float = 0
    private var peakHoldLinear: Float = 0
    private var lastBufferClippedSampleCount: UInt64 = 0
    private var totalClippedSampleCount: UInt64 = 0
    private var bufferDurationMilliseconds: Double = 0

    private let fftAnalyzer = FFTAnalyzer()
    private let smoothingBank = SpectrumSmoothingBank()
    private let noiseFloorEstimator = NoiseFloorEstimator()
    private let dominantFrequencyDetector = DominantFrequencyDetector()
    private let persistentToneTracker = PersistentToneTracker()
    private let musicInterferenceDetector = MusicInterferenceDetector()

    private var fftSnapshot: FFTSnapshot = .empty
    private var smoothedSpectrum: SmoothedSpectrumSnapshot = .empty
    private var noiseFloor: NoiseFloorSnapshot = .empty
    private var dominantFrequencies: DominantFrequencySnapshot = .empty
    private var persistentTones: PersistentToneSnapshot = .empty
    private var musicInterference:
        MusicInterferenceSnapshot = .empty
    private var processingLatencyTracker =
        ProcessingLatencyTracker()

    init() {
        // Force creation before the first real-time callback so the callback
        // only signals an already-configured source.
        _ = analysisSource
    }

    func setAnalysisMode(_ mode: AnalysisMode) {
        lock.lock()
        let changed = mode != analysisMode
        analysisMode = mode
        lock.unlock()

        if changed {
            reset()
        }
    }

    func record(
        buffer: AVAudioPCMBuffer,
        captureGeneration expectedGeneration: UInt64
    ) {
        lock.lock()
        let acceptsCallback =
            captureIsActive &&
            captureGeneration ==
                expectedGeneration
        lock.unlock()

        guard acceptsCallback else {
            return
        }

        let callbackStartedNanoseconds =
            DispatchTime.now().uptimeNanoseconds
        let durationMilliseconds: Double

        if
            buffer.format.sampleRate.isFinite,
            buffer.format.sampleRate > 0
        {
            durationMilliseconds =
                Double(buffer.frameLength) /
                buffer.format.sampleRate *
                1_000
        } else {
            durationMilliseconds = 0
        }

        lock.lock()
        guard
            captureIsActive,
            captureGeneration ==
                expectedGeneration
        else {
            lock.unlock()
            return
        }

        bufferCount += 1
        frameCount += UInt64(buffer.frameLength)
        lastBufferFrames = buffer.frameLength
        sampleRate = buffer.format.sampleRate
        channelCount = buffer.format.channelCount
        bufferDurationMilliseconds = durationMilliseconds
        processingLatencyTracker.recordCallbackStart(
            callbackStartedNanoseconds
        )
        lock.unlock()

        guard
            frameHandoff.enqueue(
                buffer: buffer,
                callbackStartedNanoseconds:
                    callbackStartedNanoseconds,
                captureGeneration:
                    expectedGeneration
            ) != nil
        else {
            lock.lock()
            if
                captureIsActive,
                captureGeneration ==
                    expectedGeneration
            {
                analysisDroppedBufferCount += 1
                analysisDroppedFrameCount +=
                    UInt64(buffer.frameLength)
            }
            lock.unlock()
            return
        }

        analysisSource.add(data: 1)
    }

    func flushPendingAnalysis() {
        analysisQueue.sync {
            drainReadyFrames()
        }
    }

    func snapshot() -> MicrophoneCaptureModel.Snapshot {
        lock.lock()
        defer { lock.unlock() }

        let latencySnapshot =
            processingLatencyTracker.snapshot(
                nowNanoseconds:
                    DispatchTime.now().uptimeNanoseconds,
                fftSampleCount:
                    fftSnapshot.sampleCount,
                sampleRate: sampleRate
            )

        return MicrophoneCaptureModel.Snapshot(
            bufferCount: bufferCount,
            frameCount: frameCount,
            analysisDroppedBufferCount:
                analysisDroppedBufferCount,
            analysisDroppedFrameCount:
                analysisDroppedFrameCount,
            lastBufferFrames: lastBufferFrames,
            sampleRate: sampleRate,
            channelCount: channelCount,
            formatDescription: formatDescription,
            rmsLinear: rmsLinear,
            peakLinear: peakLinear,
            peakHoldLinear: peakHoldLinear,
            rmsDBFS:
                AudioLevelAnalyzer.decibelsFS(
                    forAmplitude: rmsLinear
                ),
            peakDBFS:
                AudioLevelAnalyzer.decibelsFS(
                    forAmplitude: peakLinear
                ),
            peakHoldDBFS:
                AudioLevelAnalyzer.decibelsFS(
                    forAmplitude:
                        peakHoldLinear
                ),
            lastBufferClippedSampleCount:
                lastBufferClippedSampleCount,
            totalClippedSampleCount:
                totalClippedSampleCount,
            isClipping:
                lastBufferClippedSampleCount > 0,
            bufferDurationMilliseconds:
                bufferDurationMilliseconds,
            fftSampleCount: fftSnapshot.sampleCount,
            fftTransformCount:
                fftSnapshot.transformCount,
            fftResolutionHz:
                fftSnapshot.frequencyResolutionHz,
            fftWindowName: fftSnapshot.windowName,
            spectrumBins: fftSnapshot.bins,
            smoothedSpectrum: smoothedSpectrum,
            noiseFloor: noiseFloor,
            dominantFrequencies:
                dominantFrequencies,
            persistentTones: persistentTones,
            processingLatency: latencySnapshot,
            musicInterference: musicInterference
        )
    }

    func reset() {
        flushPendingAnalysis()

        analysisQueue.sync {
            fftAnalyzer.reset()
            smoothingBank.reset()
            noiseFloorEstimator.reset()
            persistentToneTracker.reset()
            musicInterferenceDetector.reset()
        }

        lock.lock()
        bufferCount = 0
        frameCount = 0
        analysisDroppedBufferCount = 0
        analysisDroppedFrameCount = 0
        lastBufferFrames = 0
        sampleRate = 0
        channelCount = 0
        formatDescription = "—"
        rmsLinear = 0
        peakLinear = 0
        peakHoldLinear = 0
        lastBufferClippedSampleCount = 0
        totalClippedSampleCount = 0
        bufferDurationMilliseconds = 0
        fftSnapshot = .empty
        smoothedSpectrum = .empty
        noiseFloor = .empty
        dominantFrequencies = .empty
        persistentTones = .empty
        musicInterference = .empty
        processingLatencyTracker.reset()
        lock.unlock()
    }

    private func drainReadyFrames() {
        while
            let index =
                frameHandoff.nextReadyIndex()
        {
            frameHandoff.consume(
                slotAt: index
            ) { [weak self] slot in
                self?.process(slot: slot)
            }
        }
    }

    private func process(
        slot: RealtimeAudioFrameHandoff.FrameSlot
    ) {
        lock.lock()
        guard
            captureIsActive,
            slot.captureGeneration ==
                captureGeneration
        else {
            lock.unlock()
            return
        }

        let currentAnalysisMode = analysisMode
        let expectedGeneration =
            captureGeneration
        lock.unlock()

        let latestFFT =
            fftAnalyzer.ingest(
                samples:
                    slot.monoSamples[
                        0..<slot.frameCount
                    ],
                sampleRate: slot.sampleRate
            )
        let latestMusicInterference =
            latestFFT.map {
                musicInterferenceDetector.process(
                    $0.bins
                )
            }
        let latestSmoothedSpectrum =
            latestFFT.map {
                smoothingBank.process(
                    $0.bins,
                    analysisMode:
                        currentAnalysisMode
                )
            }
        let latestNoiseFloor =
            latestSmoothedSpectrum.map {
                noiseFloorEstimator.process(
                    $0.balanced
                )
            }
        let latestDominantFrequencies:
            DominantFrequencySnapshot?

        if
            let latestSmoothedSpectrum,
            let latestNoiseFloor
        {
            latestDominantFrequencies =
                dominantFrequencyDetector.detect(
                    spectrum:
                        latestSmoothedSpectrum
                            .balanced,
                    noiseFloor:
                        latestNoiseFloor.bins,
                    frequencyRange:
                        currentAnalysisMode
                            .dominantFrequencyRange
                )
        } else {
            latestDominantFrequencies = nil
        }

        let timestampSeconds =
            Double(
                slot.callbackStartedNanoseconds
            ) / 1_000_000_000.0
        let latestPersistentTones =
            latestDominantFrequencies.map {
                persistentToneTracker.process(
                    $0.frequencies,
                    timestampSeconds:
                        timestampSeconds
                )
            }
        let analysisCompletedNanoseconds =
            DispatchTime.now().uptimeNanoseconds

        lock.lock()
        guard
            captureIsActive,
            captureGeneration ==
                expectedGeneration
        else {
            lock.unlock()
            return
        }

        formatDescription =
            Self.describe(
                commonFormat:
                    slot.commonFormat,
                isInterleaved:
                    slot.isInterleaved
            )
        rmsLinear =
            slot.levelMeasurement.rmsLinear
        peakLinear =
            slot.levelMeasurement.peakLinear
        peakHoldLinear =
            max(
                peakHoldLinear,
                slot.levelMeasurement
                    .peakLinear
            )
        lastBufferClippedSampleCount =
            slot.levelMeasurement
                .clippedSampleCount
        totalClippedSampleCount +=
            slot.levelMeasurement
                .clippedSampleCount

        if let latestFFT {
            fftSnapshot = latestFFT
        }

        if let latestSmoothedSpectrum {
            smoothedSpectrum =
                latestSmoothedSpectrum
        }

        if let latestNoiseFloor {
            noiseFloor = latestNoiseFloor
        }

        if let latestDominantFrequencies {
            dominantFrequencies =
                latestDominantFrequencies
        }

        if let latestPersistentTones {
            persistentTones =
                latestPersistentTones
        }

        if let latestMusicInterference {
            musicInterference =
                latestMusicInterference
        }

        processingLatencyTracker
            .recordAnalysisTurnaround(
                callbackStartedNanoseconds:
                    slot.callbackStartedNanoseconds,
                analysisCompletedNanoseconds:
                    analysisCompletedNanoseconds
            )
        lock.unlock()
    }

    private static func describe(
        commonFormat: AVAudioCommonFormat,
        isInterleaved: Bool
    ) -> String {
        let sampleType: String

        switch commonFormat {
        case .pcmFormatFloat32:
            sampleType = "Float32"
        case .pcmFormatFloat64:
            sampleType = "Float64"
        case .pcmFormatInt16:
            sampleType = "Int16"
        case .pcmFormatInt32:
            sampleType = "Int32"
        case .otherFormat:
            sampleType = "Other"
        @unknown default:
            sampleType = "Unknown"
        }

        return
            "\(sampleType) • " +
            "\(isInterleaved ? "interleaved" : "non-interleaved")"
    }
}
