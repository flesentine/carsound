import AVFAudio
import Observation

@MainActor
@Observable
final class AudioSessionModel {
    enum State: Equatable {
        case inactive
        case active
        case failed(String)

        var label: String {
            switch self {
            case .inactive: "Inactive"
            case .active: "Active"
            case .failed: "Error"
            }
        }
    }

    struct Port: Identifiable, Equatable {
        let id: String
        let name: String
        let type: String
        let isBluetooth: Bool
    }

    private(set) var state: State = .inactive
    private(set) var inputs: [Port] = []
    private(set) var outputs: [Port] = []
    private(set) var sampleRate: Double = 0
    private(set) var ioBufferDuration: TimeInterval = 0
    private(set) var inputLatency: TimeInterval = 0
    private(set) var outputLatency: TimeInterval = 0
    private(set) var routeRevision: UInt64 = 0
    private(set) var routeSignature = "None"
    private(set) var lastRouteChangeReason = "None"
    private(set) var interruptionRevision: UInt64 = 0
    private(set) var isInterrupted = false
    private(set) var lastInterruptionReason = "None"

    @ObservationIgnored
    private let session = AVAudioSession.sharedInstance()

    @ObservationIgnored
    nonisolated(unsafe) private var routeChangeObserver: NSObjectProtocol?

    @ObservationIgnored
    nonisolated(unsafe) private var mediaResetObserver: NSObjectProtocol?

    @ObservationIgnored
    nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?

    init() {
        installObservers()
        refreshRoute()
    }

    deinit {
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
        if let mediaResetObserver {
            NotificationCenter.default.removeObserver(mediaResetObserver)
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    func configureAndActivate() {
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker]
            )

            // These are requests, not guarantees. The actual values are shown in the UI
            // after activation so later latency work can use measured device behavior.
            try session.setPreferredSampleRate(48_000)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)

            isInterrupted = false
            state = .active
            refreshRoute()
        } catch {
            state = .failed(error.localizedDescription)
            refreshRoute()
        }
    }

    func deactivate() {
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            state = .inactive
        } catch {
            state = .failed(error.localizedDescription)
        }
        refreshRoute()
    }

    func refreshRoute() {
        let refreshedInputs =
            session.currentRoute.inputs.map(Self.makePort)
        let refreshedOutputs =
            session.currentRoute.outputs.map(Self.makePort)

        let signature =
            AudioRouteTestingMath.signature(
                inputs:
                    AudioRouteTestingMath.records(
                        from: refreshedInputs
                    ),
                outputs:
                    AudioRouteTestingMath.records(
                        from: refreshedOutputs
                    )
            )

        if signature != routeSignature {
            routeRevision &+= 1
            routeSignature =
                signature.isEmpty
                    ? "None"
                    : signature
        }

        inputs = refreshedInputs
        outputs = refreshedOutputs
        sampleRate = session.sampleRate
        ioBufferDuration = session.ioBufferDuration
        inputLatency = session.inputLatency
        outputLatency = session.outputLatency
    }

    private func installObservers() {
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let reason = rawReason.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastRouteChangeReason = Self.routeChangeLabel(reason)
                self.refreshRoute()
            }
        }

        mediaResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.state = .inactive
                self.lastRouteChangeReason = "Media services reset"
                self.refreshRoute()
            }
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let typeRaw =
                notification.userInfo?[
                    AVAudioSessionInterruptionTypeKey
                ] as? UInt
            let type =
                typeRaw.flatMap {
                    AVAudioSession.InterruptionType(
                        rawValue: $0
                    )
                }
            let optionsRaw =
                notification.userInfo?[
                    AVAudioSessionInterruptionOptionKey
                ] as? UInt
            let options =
                AVAudioSession.InterruptionOptions(
                    rawValue:
                        optionsRaw ?? 0
                )

            Task { @MainActor [weak self] in
                guard let self else { return }

                switch type {
                case .began:
                    self.isInterrupted = true
                    self.interruptionRevision &+= 1
                    self.lastInterruptionReason =
                        "Audio interruption began"
                    self.state = .inactive
                    self.refreshRoute()

                case .ended:
                    self.isInterrupted = false
                    self.lastInterruptionReason =
                        options.contains(
                            .shouldResume
                        )
                        ? "Interruption ended — reactivate manually"
                        : "Interruption ended"
                    self.refreshRoute()

                case .none:
                    self.lastInterruptionReason =
                        "Unknown audio interruption"

                @unknown default:
                    self.lastInterruptionReason =
                        "Unknown audio interruption"
                }
            }
        }
    }

    private static func makePort(_ port: AVAudioSessionPortDescription) -> Port {
        Port(
            id: port.uid,
            name: port.portName,
            type: readablePortType(port.portType),
            isBluetooth: bluetoothPortTypes.contains(port.portType)
        )
    }

    private static let bluetoothPortTypes: Set<AVAudioSession.Port> = [
        .bluetoothA2DP,
        .bluetoothHFP,
        .bluetoothLE
    ]

    private static func readablePortType(_ type: AVAudioSession.Port) -> String {
        switch type {
        case .builtInMic: "Built-in microphone"
        case .builtInSpeaker: "Built-in speaker"
        case .headphones: "Headphones"
        case .headsetMic: "Headset microphone"
        case .bluetoothA2DP: "Bluetooth A2DP"
        case .bluetoothHFP: "Bluetooth HFP"
        case .bluetoothLE: "Bluetooth LE"
        case .carAudio: "Car audio"
        case .usbAudio: "USB audio"
        case .lineIn: "Line in"
        case .lineOut: "Line out"
        case .airPlay: "AirPlay"
        case .HDMI: "HDMI"
        default: type.rawValue
        }
    }

    private static func routeChangeLabel(_ reason: AVAudioSession.RouteChangeReason?) -> String {
        switch reason {
        case .newDeviceAvailable: "New device available"
        case .oldDeviceUnavailable: "Device disconnected"
        case .categoryChange: "Category changed"
        case .override: "Route override"
        case .wakeFromSleep: "Woke from sleep"
        case .noSuitableRouteForCategory: "No suitable route"
        case .routeConfigurationChange: "Route configuration changed"
        case .unknown, .none: "Unknown"
        @unknown default: "Unknown"
        }
    }
}
