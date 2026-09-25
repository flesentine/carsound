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
    private(set) var lastRouteChangeReason = "None"

    @ObservationIgnored
    private let session = AVAudioSession.sharedInstance()

    @ObservationIgnored
    private var routeChangeObserver: NSObjectProtocol?

    @ObservationIgnored
    private var mediaResetObserver: NSObjectProtocol?

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
        inputs = session.currentRoute.inputs.map(Self.makePort)
        outputs = session.currentRoute.outputs.map(Self.makePort)
        sampleRate = session.sampleRate
        ioBufferDuration = session.ioBufferDuration
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
        case .hdmi: "HDMI"
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
