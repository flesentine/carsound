import SwiftUI

@main
struct QuietDriveLabApp: App {
    @State private var microphonePermission = MicrophonePermissionModel()
    @State private var audioSession = AudioSessionModel()
    @State private var microphoneCapture = MicrophoneCaptureModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(microphonePermission)
                .environment(audioSession)
                .environment(microphoneCapture)
                .task {
                    microphonePermission.refresh()
                    audioSession.refreshRoute()
                }
        }
    }
}
