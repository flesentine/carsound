import SwiftUI

@main
struct QuietDriveLabApp: App {
    @State private var microphonePermission = MicrophonePermissionModel()
    @State private var audioSession = AudioSessionModel()
    @State private var microphoneCapture = MicrophoneCaptureModel()
    @State private var toneGenerator = ToneGeneratorModel()
    @State private var beforeAfterMeasurement = BeforeAfterMeasurementModel()
    @State private var experimentRecorder = ExperimentRecorderModel()
    @State private var phaseSweep = PhaseSweepModel()
    @State private var phaseRefinement = PhaseRefinementModel()
    @State private var amplitudeSearch = AmplitudeSearchModel()
    @State private var adaptiveController = AdaptiveControllerModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(microphonePermission)
                .environment(audioSession)
                .environment(microphoneCapture)
                .environment(toneGenerator)
                .environment(beforeAfterMeasurement)
                .environment(experimentRecorder)
                .environment(phaseSweep)
                .environment(phaseRefinement)
                .environment(amplitudeSearch)
                .environment(adaptiveController)
                .task {
                    microphonePermission.refresh()
                    audioSession.refreshRoute()
                }
        }
    }
}
