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
    @State private var calibration = CalibrationModel()
    @State private var structuredLog = StructuredLogModel()

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
                .environment(calibration)
                .environment(structuredLog)
                .task {
                    microphonePermission.refresh()
                    audioSession.refreshRoute()

                    structuredLog.startSession(
                        context:
                            StructuredLogContext(
                                routeSignature:
                                    audioSession.routeSignature,
                                routeRevision:
                                    audioSession.routeRevision,
                                calibrationProfileID: nil,
                                targetFrequencyHz: nil,
                                phaseDegrees: nil,
                                outputPercent: nil,
                                confidenceScorePercent: nil,
                                evidenceCoveragePercent: nil,
                                confidenceLevel: nil
                            ),
                        text: [
                            "app_build":
                                "3.8"
                        ]
                    )
                }
        }
    }
}
