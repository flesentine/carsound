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
    @State private var audioRouteTesting = AudioRouteTestingModel()
    @State private var bluetoothJitterDiagnostics = BluetoothJitterDiagnosticsModel()
    @State private var accelerometerCapture = AccelerometerCaptureModel()
    @State private var soundVibrationCorrelation = SoundVibrationCorrelationModel()

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
                .environment(audioRouteTesting)
                .environment(bluetoothJitterDiagnostics)
                .environment(accelerometerCapture)
                .environment(soundVibrationCorrelation)
                .task {
                    microphonePermission.refresh()
                    audioSession.refreshRoute()
                }
        }
    }
}
