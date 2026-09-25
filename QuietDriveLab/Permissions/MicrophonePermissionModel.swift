import AVFAudio
import Observation

@MainActor
@Observable
final class MicrophonePermissionModel {
    enum Status: Equatable {
        case undetermined
        case denied
        case granted

        var symbolName: String {
            switch self {
            case .undetermined: "mic.badge.questionmark"
            case .denied: "mic.slash.fill"
            case .granted: "mic.fill"
            }
        }

        var message: String {
            switch self {
            case .undetermined:
                "QuietDrive needs microphone access to measure cabin sound."
            case .denied:
                "Microphone access is currently denied."
            case .granted:
                "Microphone access is granted."
            }
        }
    }

    private(set) var status: Status = .undetermined
    private(set) var requestInFlight = false

    init() {
        refresh()
    }

    func refresh() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            status = .granted
        case .denied:
            status = .denied
        case .undetermined:
            status = .undetermined
        @unknown default:
            status = .undetermined
        }
    }

    func request() async {
        guard !requestInFlight else { return }
        requestInFlight = true
        defer { requestInFlight = false }

        _ = await AVAudioApplication.requestRecordPermission()
        refresh()
    }
}
