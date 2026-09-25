import SwiftUI

@main
struct QuietDriveLabApp: App {
    @State private var microphonePermission = MicrophonePermissionModel()
    @State private var audioSession = AudioSessionModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(microphonePermission)
                .environment(audioSession)
                .task {
                    microphonePermission.refresh()
                    audioSession.refreshRoute()
                }
        }
    }
}
