import AVFAudio
import Foundation
import Observation

enum ToneGeneratorMath {
    static let minimumFrequencyHz = 20.0
    static let maximumFrequencyHz = 200.0
    static let defaultFrequencyHz = 80.0

    static let minimumPhaseDegrees = 0.0
    static let maximumPhaseDegrees = 360.0
    static let defaultPhaseDegrees = 0.0

    // Hard digital ceiling for the generated PCM samples.
    // This limits digital amplitude, not acoustic SPL at the car speakers.
    static let maximumAmplitude: Float = 0.02
    static let defaultOutputPercent = 50.0

    static let startStopRampDurationSeconds = 0.12
    static let liveLevelRampDurationSeconds = 0.06
    static let phaseChangeRampDurationSeconds = 0.035
    static let phaseChangeDebounceSeconds = 0.05

    static func sanitizedFrequency(_ frequencyHz: Double) -> Double {
        min(
            maximumFrequencyHz,
            max(
                minimumFrequencyHz,
                frequencyHz.rounded()
            )
        )
    }

    static func normalizedPhaseDegrees(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return defaultPhaseDegrees }

        var normalized = degrees.truncatingRemainder(dividingBy: 360)

        if normalized < 0 {
            normalized += 360
        }

        return normalized
    }

    static func invertedPhaseDegrees(_ degrees: Double) -> Double {
        normalizedPhaseDegrees(degrees + 180)
    }

    static func sanitizedOutputPercent(_ percent: Double) -> Double {
        min(100, max(0, percent))
    }

    static func outputGain(forPercent percent: Double) -> Float {
        Float(sanitizedOutputPercent(percent) / 100.0)
    }

    static func effectiveAmplitude(forPercent percent: Double) -> Float {
        maximumAmplitude * outputGain(forPercent: percent)
    }

    static func levelDBFS(forAmplitude amplitude: Float) -> Double {
        guard amplitude > 0 else {
            return AudioLevelAnalyzer.silenceFloorDBFS
        }

        return max(
            AudioLevelAnalyzer.silenceFloorDBFS,
            20.0 * log10(Double(amplitude))
        )
    }

    static var maximumLevelDBFS: Double {
        levelDBFS(forAmplitude: maximumAmplitude)
    }

    static func levelDBFS(forOutputPercent percent: Double) -> Double {
        levelDBFS(
            forAmplitude: effectiveAmplitude(
                forPercent: percent
            )
        )
    }

    static func makeOneSecondLoop(
        frequencyHz: Double,
        sampleRate: Double,
        phaseDegrees: Double = defaultPhaseDegrees
    ) -> [Float] {
        guard sampleRate > 0 else { return [] }

        let frequency = sanitizedFrequency(frequencyHz)
        let phaseRadians =
            normalizedPhaseDegrees(phaseDegrees) *
            Double.pi /
            180.0
        let frameCount = max(1, Int(sampleRate.rounded()))

        return (0..<frameCount).map { frame in
            let phase =
                2.0 *
                Double.pi *
                frequency *
                Double(frame) /
                sampleRate +
                phaseRadians

            return maximumAmplitude * Float(sin(phase))
        }
    }
}

@MainActor
@Observable
final class ToneGeneratorModel {
    enum State: Equatable {
        case stopped
        case playing
        case failed(String)

        var label: String {
            switch self {
            case .stopped:
                "Stopped"
            case .playing:
                "Playing"
            case .failed:
                "Error"
            }
        }
    }

    private(set) var state: State = .stopped
    private(set) var frequencyHz =
        ToneGeneratorMath.defaultFrequencyHz
    private(set) var phaseDegrees =
        ToneGeneratorMath.defaultPhaseDegrees
    private(set) var outputPercent =
        ToneGeneratorMath.defaultOutputPercent
    private(set) var isMuted = false
    private(set) var sampleRate: Double = 0
    private(set) var generatedFrames = 0

    let maximumAmplitude = ToneGeneratorMath.maximumAmplitude
    let startStopRampDurationSeconds =
        ToneGeneratorMath.startStopRampDurationSeconds
    let liveLevelRampDurationSeconds =
        ToneGeneratorMath.liveLevelRampDurationSeconds
    let phaseChangeRampDurationSeconds =
        ToneGeneratorMath.phaseChangeRampDurationSeconds

    @ObservationIgnored
    private let engine = AVAudioEngine()

    @ObservationIgnored
    private let player = AVAudioPlayerNode()

    @ObservationIgnored
    private var rampTask: Task<Void, Never>?

    @ObservationIgnored
    private var phaseChangeTask: Task<Void, Never>?

    init() {
        engine.attach(player)
    }

    var outputGain: Float {
        ToneGeneratorMath.outputGain(
            forPercent: outputPercent
        )
    }

    var targetAmplitude: Float {
        ToneGeneratorMath.effectiveAmplitude(
            forPercent: outputPercent
        )
    }

    var targetLevelDBFS: Double {
        ToneGeneratorMath.levelDBFS(
            forOutputPercent: outputPercent
        )
    }

    var maximumLevelDBFS: Double {
        ToneGeneratorMath.maximumLevelDBFS
    }

    func setFrequency(_ frequencyHz: Double) {
        guard state != .playing else { return }

        self.frequencyHz =
            ToneGeneratorMath.sanitizedFrequency(
                frequencyHz
            )
    }

    func setPhaseDegrees(_ degrees: Double) {
        phaseDegrees =
            ToneGeneratorMath.normalizedPhaseDegrees(
                degrees
            )

        guard state == .playing else { return }

        scheduleLivePhaseChange()
    }

    func invertPhase() {
        setPhaseDegrees(
            ToneGeneratorMath.invertedPhaseDegrees(
                phaseDegrees
            )
        )
    }

    func setOutputPercent(_ percent: Double) {
        outputPercent =
            ToneGeneratorMath.sanitizedOutputPercent(
                percent
            )

        guard state == .playing, !isMuted else {
            return
        }

        beginRamp(
            to: outputGain,
            duration:
                ToneGeneratorMath.liveLevelRampDurationSeconds
        )
    }

    func start() {
        guard state != .playing else { return }

        rampTask?.cancel()
        rampTask = nil
        phaseChangeTask?.cancel()
        phaseChangeTask = nil

        player.stop()
        engine.stop()
        engine.disconnectNodeOutput(player)

        let hardwareFormat =
            engine.outputNode.outputFormat(forBus: 0)

        guard
            hardwareFormat.sampleRate > 0,
            hardwareFormat.channelCount > 0
        else {
            state = .failed(
                "No usable audio output route is available."
            )
            return
        }

        let renderSampleRate = hardwareFormat.sampleRate

        guard
            let monoFormat = AVAudioFormat(
                standardFormatWithSampleRate:
                    renderSampleRate,
                channels: 1
            ),
            let buffer = makeToneBuffer(
                format: monoFormat,
                phaseDegrees: phaseDegrees
            )
        else {
            state = .failed(
                "Could not create the tone output buffer."
            )
            return
        }

        engine.connect(
            player,
            to: engine.mainMixerNode,
            format: monoFormat
        )

        player.volume = 0
        player.scheduleBuffer(
            buffer,
            at: nil,
            options: [.loops]
        )

        engine.prepare()

        do {
            try engine.start()
            player.play()

            sampleRate = renderSampleRate
            generatedFrames = Int(buffer.frameLength)
            state = .playing
            isMuted = false

            beginRamp(
                to: outputGain,
                duration:
                    ToneGeneratorMath
                        .startStopRampDurationSeconds
            )
        } catch {
            player.stop()
            engine.stop()
            state = .failed(
                error.localizedDescription
            )
        }
    }

    func muteImmediately() {
        guard state == .playing else { return }

        rampTask?.cancel()
        rampTask = nil
        phaseChangeTask?.cancel()
        phaseChangeTask = nil
        player.volume = 0
        isMuted = true
    }

    func unmute() {
        guard state == .playing, isMuted else {
            return
        }

        isMuted = false

        beginRamp(
            to: outputGain,
            duration:
                ToneGeneratorMath.liveLevelRampDurationSeconds
        )
    }

    func stop() async {
        guard state == .playing else {
            stopImmediately()
            return
        }

        phaseChangeTask?.cancel()
        phaseChangeTask = nil
        rampTask?.cancel()
        rampTask = nil

        await rampVolume(
            to: 0,
            duration:
                ToneGeneratorMath
                    .startStopRampDurationSeconds
        )

        finishStop()
    }

    func stopImmediately() {
        phaseChangeTask?.cancel()
        phaseChangeTask = nil
        rampTask?.cancel()
        rampTask = nil
        player.volume = 0
        finishStop()
    }

    private func scheduleLivePhaseChange() {
        phaseChangeTask?.cancel()

        phaseChangeTask = Task { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(
                nanoseconds: UInt64(
                    ToneGeneratorMath
                        .phaseChangeDebounceSeconds *
                    1_000_000_000
                )
            )

            guard !Task.isCancelled else { return }

            await self.applyLivePhaseChange()
        }
    }

    private func applyLivePhaseChange() async {
        guard
            state == .playing,
            sampleRate > 0,
            let monoFormat = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
            ),
            let buffer = makeToneBuffer(
                format: monoFormat,
                phaseDegrees: phaseDegrees
            )
        else {
            return
        }

        let shouldRestoreAudibleLevel = !isMuted

        rampTask?.cancel()
        rampTask = nil

        if shouldRestoreAudibleLevel {
            await rampVolume(
                to: 0,
                duration:
                    ToneGeneratorMath
                        .phaseChangeRampDurationSeconds
            )
        }

        guard !Task.isCancelled else { return }

        player.stop()
        player.scheduleBuffer(
            buffer,
            at: nil,
            options: [.loops],
            completionHandler: nil
        )
        player.volume = 0
        player.play()

        generatedFrames = Int(buffer.frameLength)

        if shouldRestoreAudibleLevel {
            await rampVolume(
                to: outputGain,
                duration:
                    ToneGeneratorMath
                        .phaseChangeRampDurationSeconds
            )
        }
    }

    private func makeToneBuffer(
        format: AVAudioFormat,
        phaseDegrees: Double
    ) -> AVAudioPCMBuffer? {
        let samples = ToneGeneratorMath.makeOneSecondLoop(
            frequencyHz: frequencyHz,
            sampleRate: format.sampleRate,
            phaseDegrees: phaseDegrees
        )

        guard
            !samples.isEmpty,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity:
                    AVAudioFrameCount(samples.count)
            ),
            let channel =
                buffer.floatChannelData?[0]
        else {
            return nil
        }

        buffer.frameLength =
            AVAudioFrameCount(samples.count)

        for index in samples.indices {
            channel[index] = samples[index]
        }

        return buffer
    }

    private func beginRamp(
        to target: Float,
        duration: TimeInterval
    ) {
        rampTask?.cancel()

        rampTask = Task { @MainActor [weak self] in
            await self?.rampVolume(
                to: target,
                duration: duration
            )
        }
    }

    private func finishStop() {
        player.stop()

        if engine.isRunning {
            engine.stop()
        }

        isMuted = false
        state = .stopped
    }

    private func rampVolume(
        to target: Float,
        duration: TimeInterval
    ) async {
        let safeTarget = min(
            1,
            max(0, target)
        )
        let steps = 24
        let startingVolume = player.volume
        let stepDuration =
            duration / Double(steps)

        for step in 1...steps {
            guard !Task.isCancelled else {
                return
            }

            let progress =
                Float(step) / Float(steps)

            player.volume =
                startingVolume +
                (safeTarget - startingVolume) *
                progress

            try? await Task.sleep(
                nanoseconds: UInt64(
                    stepDuration *
                    1_000_000_000
                )
            )
        }

        if !Task.isCancelled {
            player.volume = safeTarget
        }
    }
}
