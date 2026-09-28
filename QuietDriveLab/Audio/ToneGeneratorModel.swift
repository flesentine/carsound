import AVFAudio
import Foundation
import Observation

enum ToneGeneratorMath {
    static let minimumFrequencyHz = 20.0
    static let maximumFrequencyHz = 200.0
    static let defaultFrequencyHz = 80.0

    // Fixed conservative amplitude for milestone #12.
    // Manual output level arrives in #13.
    static let fixedAmplitude: Float = 0.01
    static let rampDurationSeconds = 0.12

    static var fixedLevelDBFS: Double {
        20.0 * log10(Double(fixedAmplitude))
    }

    static func sanitizedFrequency(_ frequencyHz: Double) -> Double {
        min(
            maximumFrequencyHz,
            max(
                minimumFrequencyHz,
                frequencyHz.rounded()
            )
        )
    }

    static func makeOneSecondLoop(
        frequencyHz: Double,
        sampleRate: Double
    ) -> [Float] {
        guard sampleRate > 0 else { return [] }

        let frequency = sanitizedFrequency(frequencyHz)
        let frameCount = max(1, Int(sampleRate.rounded()))

        return (0..<frameCount).map { frame in
            let phase =
                2.0 *
                Double.pi *
                frequency *
                Double(frame) /
                sampleRate

            return fixedAmplitude * Float(sin(phase))
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
    private(set) var frequencyHz = ToneGeneratorMath.defaultFrequencyHz
    private(set) var sampleRate: Double = 0
    private(set) var generatedFrames = 0

    let fixedAmplitude = ToneGeneratorMath.fixedAmplitude
    let rampDurationSeconds = ToneGeneratorMath.rampDurationSeconds

    @ObservationIgnored
    private let engine = AVAudioEngine()

    @ObservationIgnored
    private let player = AVAudioPlayerNode()

    @ObservationIgnored
    private var rampTask: Task<Void, Never>?

    init() {
        engine.attach(player)
    }

    var fixedLevelDBFS: Double {
        ToneGeneratorMath.fixedLevelDBFS
    }

    func setFrequency(_ frequencyHz: Double) {
        guard state != .playing else { return }
        self.frequencyHz =
            ToneGeneratorMath.sanitizedFrequency(frequencyHz)
    }

    func start() {
        guard state != .playing else { return }

        rampTask?.cancel()
        rampTask = nil

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
                standardFormatWithSampleRate: renderSampleRate,
                channels: 1
            )
        else {
            state = .failed(
                "Could not create the tone output format."
            )
            return
        }

        let samples = ToneGeneratorMath.makeOneSecondLoop(
            frequencyHz: frequencyHz,
            sampleRate: renderSampleRate
        )

        guard
            !samples.isEmpty,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: monoFormat,
                frameCapacity: AVAudioFrameCount(samples.count)
            ),
            let channel = buffer.floatChannelData?[0]
        else {
            state = .failed(
                "Could not allocate the tone buffer."
            )
            return
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)

        for index in samples.indices {
            channel[index] = samples[index]
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
            generatedFrames = samples.count
            state = .playing

            rampTask = Task { @MainActor [weak self] in
                await self?.rampVolume(
                    to: 1.0,
                    duration: ToneGeneratorMath.rampDurationSeconds
                )
            }
        } catch {
            player.stop()
            engine.stop()
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        guard state == .playing else {
            stopImmediately()
            return
        }

        rampTask?.cancel()
        rampTask = nil

        await rampVolume(
            to: 0,
            duration: ToneGeneratorMath.rampDurationSeconds
        )

        finishStop()
    }

    func stopImmediately() {
        rampTask?.cancel()
        rampTask = nil
        player.volume = 0
        finishStop()
    }

    private func finishStop() {
        player.stop()

        if engine.isRunning {
            engine.stop()
        }

        state = .stopped
    }

    private func rampVolume(
        to target: Float,
        duration: TimeInterval
    ) async {
        let steps = 24
        let startingVolume = player.volume
        let stepDuration = duration / Double(steps)

        for step in 1...steps {
            guard !Task.isCancelled else { return }

            let progress = Float(step) / Float(steps)
            player.volume =
                startingVolume +
                (target - startingVolume) *
                progress

            try? await Task.sleep(
                nanoseconds: UInt64(
                    stepDuration *
                    1_000_000_000
                )
            )
        }

        if !Task.isCancelled {
            player.volume = target
        }
    }
}
