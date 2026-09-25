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

        static let empty = Snapshot(
            bufferCount: 0,
            frameCount: 0,
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
            bufferDurationMilliseconds: 0
        )
    }

    private(set) var state: State = .stopped
    private(set) var snapshot: Snapshot = .empty

    @ObservationIgnored
    private let stats = CaptureStatsStore()

    @ObservationIgnored
    private let engine = AVAudioEngine()

    @ObservationIgnored
    private var pollingTask: Task<Void, Never>?

    @ObservationIgnored
    private var tapInstalled = false

    func startCapture() {
        guard state != .capturing else { return }

        stopCapture()
        stats.reset()

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            state = .failed("No usable microphone input format is available.")
            return
        }

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format
        ) { [stats] buffer, _ in
            stats.record(buffer: buffer)
        }
        tapInstalled = true

        engine.prepare()

        do {
            try engine.start()
            state = .capturing
            snapshot = stats.snapshot()
            startPolling()
        } catch {
            removeTapIfNeeded()
            engine.stop()
            state = .failed(error.localizedDescription)
        }
    }

    func stopCapture() {
        pollingTask?.cancel()
        pollingTask = nil

        removeTapIfNeeded()

        if engine.isRunning {
            engine.stop()
        }

        if state == .capturing {
            state = .stopped
        }

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

    private var bufferCount: UInt64 = 0
    private var frameCount: UInt64 = 0
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

    func record(buffer: AVAudioPCMBuffer) {
        let format = buffer.format
        let description = Self.describe(format: format)
        let measurement = AudioLevelAnalyzer.analyze(buffer: buffer)
        let durationMilliseconds: Double

        if format.sampleRate > 0 {
            durationMilliseconds = Double(buffer.frameLength) / format.sampleRate * 1_000
        } else {
            durationMilliseconds = 0
        }

        lock.lock()
        bufferCount += 1
        frameCount += UInt64(buffer.frameLength)
        lastBufferFrames = buffer.frameLength
        sampleRate = format.sampleRate
        channelCount = format.channelCount
        formatDescription = description
        rmsLinear = measurement.rmsLinear
        peakLinear = measurement.peakLinear
        peakHoldLinear = max(peakHoldLinear, measurement.peakLinear)
        lastBufferClippedSampleCount = measurement.clippedSampleCount
        totalClippedSampleCount += measurement.clippedSampleCount
        bufferDurationMilliseconds = durationMilliseconds
        lock.unlock()
    }

    func snapshot() -> MicrophoneCaptureModel.Snapshot {
        lock.lock()
        defer { lock.unlock() }

        return MicrophoneCaptureModel.Snapshot(
            bufferCount: bufferCount,
            frameCount: frameCount,
            lastBufferFrames: lastBufferFrames,
            sampleRate: sampleRate,
            channelCount: channelCount,
            formatDescription: formatDescription,
            rmsLinear: rmsLinear,
            peakLinear: peakLinear,
            peakHoldLinear: peakHoldLinear,
            rmsDBFS: AudioLevelAnalyzer.decibelsFS(forAmplitude: rmsLinear),
            peakDBFS: AudioLevelAnalyzer.decibelsFS(forAmplitude: peakLinear),
            peakHoldDBFS: AudioLevelAnalyzer.decibelsFS(forAmplitude: peakHoldLinear),
            lastBufferClippedSampleCount: lastBufferClippedSampleCount,
            totalClippedSampleCount: totalClippedSampleCount,
            isClipping: lastBufferClippedSampleCount > 0,
            bufferDurationMilliseconds: bufferDurationMilliseconds
        )
    }

    func reset() {
        lock.lock()
        bufferCount = 0
        frameCount = 0
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
        lock.unlock()
    }

    private static func describe(format: AVAudioFormat) -> String {
        let sampleType: String

        switch format.commonFormat {
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

        return "\(sampleType) • \(format.isInterleaved ? "interleaved" : "non-interleaved")"
    }
}
