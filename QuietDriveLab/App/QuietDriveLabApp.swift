import SwiftUI

@main
struct QuietDriveLabApp: App {
    @Environment(\.scenePhase)
    private var scenePhase
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
                                "4.3"
                        ]
                    )
                }
                .onChange(
                    of: scenePhase
                ) { _, phase in
                    guard phase != .active else {
                        return
                    }

                    stopSafetyCriticalActivity(
                        reason:
                            "App left the foreground",
                        deactivateSession: true
                    )

                    Task { @MainActor in
                        await structuredLog
                            .flushPersistence()
                    }
                }
                .onChange(
                    of:
                        audioSession
                            .audioSafetyRevision
                ) { oldValue, newValue in
                    guard newValue != oldValue else {
                        return
                    }

                    stopSafetyCriticalActivity(
                        reason:
                            audioSession
                                .lastAudioSafetyReason,
                        deactivateSession:
                            false
                    )
                }
                .onChange(
                    of:
                        audioSession
                            .routeRevision
                ) { oldValue, newValue in
                    guard
                        oldValue != 0,
                        newValue != oldValue
                    else {
                        return
                    }

                    stopSafetyCriticalActivity(
                        reason:
                            "Audio route changed",
                        deactivateSession:
                            false
                    )
                }
        }
    }

    private func stopSafetyCriticalActivity(
        reason: String,
        deactivateSession: Bool
    ) {
        let hadActiveWork =
            toneGenerator.state == .playing ||
            microphoneCapture.state ==
                .capturing ||
            beforeAfterMeasurement.state
                .isBusy ||
            phaseSweep.state.isRunning ||
            phaseRefinement.state.isRunning ||
            amplitudeSearch.state.isRunning ||
            adaptiveController.state.isRunning ||
            calibration.state.isRunning ||
            bluetoothJitterDiagnostics
                .state.isRunning ||
            soundVibrationCorrelation
                .state.isRunning ||
            accelerometerCapture.state ==
                .capturing
        let safetyContext =
            StructuredLogContext(
                routeSignature:
                    audioSession
                        .routeSignature,
                routeRevision:
                    audioSession
                        .routeRevision,
                calibrationProfileID:
                    nil,
                targetFrequencyHz:
                    toneGenerator
                        .frequencyHz,
                phaseDegrees:
                    toneGenerator
                        .phaseDegrees,
                outputPercent:
                    toneGenerator
                        .outputPercent,
                confidenceScorePercent:
                    nil,
                evidenceCoveragePercent:
                    nil,
                confidenceLevel:
                    nil
            )

        toneGenerator.stopImmediately()
        microphoneCapture.stopCapture()

        if beforeAfterMeasurement.state.isBusy {
            beforeAfterMeasurement
                .cancelCapture()
        }
        if phaseSweep.state.isRunning {
            phaseSweep.cancel()
        }
        if phaseRefinement.state.isRunning {
            phaseRefinement.cancel()
        }
        if amplitudeSearch.state.isRunning {
            amplitudeSearch.cancel()
        }
        if adaptiveController.state.isRunning {
            adaptiveController.cancel()
        }
        if calibration.state.isRunning {
            calibration.cancel()
        }
        if
            bluetoothJitterDiagnostics
                .state.isRunning
        {
            bluetoothJitterDiagnostics.stop()
        }
        if
            soundVibrationCorrelation
                .state.isRunning
        {
            soundVibrationCorrelation.stop()
        }
        if
            accelerometerCapture.state ==
                .capturing
        {
            accelerometerCapture.stop()
        }

        if
            deactivateSession,
            audioSession.state == .active
        {
            audioSession.deactivate()
        }

        guard hadActiveWork else {
            return
        }

        _ = structuredLog.record(
            kind: .safetyMute,
            context:
                safetyContext,
            text: [
                "reason": reason,
                "action":
                    "automatic lifecycle shutdown"
            ]
        )
    }
}
