import SwiftUI

struct CancellationLabView: View {
    @Environment(AudioSessionModel.self) private var audioSession
    @Environment(MicrophoneCaptureModel.self) private var microphoneCapture
    @Environment(ToneGeneratorModel.self) private var toneGenerator
    @Environment(BeforeAfterMeasurementModel.self) private var beforeAfterMeasurement
    @Environment(ExperimentRecorderModel.self) private var experimentRecorder
    @Environment(PhaseSweepModel.self) private var phaseSweep
    @Environment(PhaseRefinementModel.self) private var phaseRefinement
    @Environment(AmplitudeSearchModel.self) private var amplitudeSearch
    @Environment(AdaptiveControllerModel.self) private var adaptiveController
    @Environment(AudioRouteTestingModel.self) private var audioRouteTesting
    @Environment(BluetoothJitterDiagnosticsModel.self) private var bluetoothJitterDiagnostics
    @Environment(AccelerometerCaptureModel.self) private var accelerometerCapture
    @Environment(SoundVibrationCorrelationModel.self) private var soundVibrationCorrelation
    @Environment(CalibrationModel.self) private var calibration
    @Environment(StructuredLogModel.self) private var structuredLog

    @State private var lastSavedComparisonKey: String?
    @State private var phaseRefinementProgressText: String?
    @State private var amplitudeSearchProgressText: String?
    @State private var externalSPLReferenceText = ""
    @State private var structuredLogExportScope: StructuredLogExportScope = .allEvents
    @State private var structuredLogExportFormat: StructuredLogExportFormat = .json
    @State private var structuredLogExportDocument: StructuredLogExportDocument?
    @State private var structuredLogExportFilename = "quietdrive-structured-events.json"
    @State private var structuredLogExportEventCount = 0
    @State private var isStructuredLogExporterPresented = false
    @State private var structuredLogExportFeedback: String?
    @State private var selectedHeadPosition:
        HeadPositionPreset = .reference
    @State private var baselineHeadPosition:
        HeadPositionPreset?
    @State private var baselineRouteSignature:
        String?
    @State private var baselineRouteRevision:
        UInt64?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                readinessCard
                calibrationCard
                structuredLogCard
                testDashboardCard
                processingLatencyCard
                audioRouteTestingCard
                bluetoothBehaviorCard
                bluetoothJitterCard
                accelerometerCard
                vibrationSpectrumCard
                soundVibrationCorrelationCard
                musicInterferenceCard
                overallConfidenceCard
                targetCard
                targetEnergyCard
                headPositionCard
                beforeAfterCard
                phaseSweepCard
                phaseRefinementCard
                amplitudeSearchCard
                adaptiveControllerCard
                experimentHistoryCard
                controlsCard
                liveStateCard
                safetyCard
            }
            .padding(20)
        }
        .navigationTitle("Cancellation Lab")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented:
                $isStructuredLogExporterPresented,
            document:
                structuredLogExportDocument,
            contentType:
                structuredLogExportFormat
                    .contentType,
            defaultFilename:
                structuredLogExportFilename
        ) { result in
            handleStructuredLogExportCompletion(
                result
            )
        }
        .onDisappear {
            stopExperimentWorkForNavigation()
        }
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Experiment Readiness", systemImage: "checklist")
                .font(.headline)

            readinessRow(
                title: "Audio session",
                isReady: audioSession.state == .active,
                detail: audioSession.state.label
            )

            readinessRow(
                title: "ANC analysis mode",
                isReady: microphoneCapture.analysisMode == .ancFocus,
                detail: microphoneCapture.analysisMode.rawValue
            )

            readinessRow(
                title: "Output route",
                isReady: !audioSession.outputs.isEmpty,
                detail: outputRouteSummary
            )

            readinessRow(
                title: "Input route",
                isReady: !audioSession.inputs.isEmpty,
                detail: inputRouteSummary
            )

            if !isExperimentReady {
                Text("Activate the audio session and use ANC Focus before running the cancellation experiment.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .cancellationCard()
    }

    private var calibrationCard: some View {
        let matching =
            calibration.latestMatchingProfile(
                routeSignature:
                    audioSession.routeSignature,
                sampleRate:
                    audioSession.sampleRate,
                ioBufferDuration:
                    audioSession.ioBufferDuration
            )
        let approximateLiveSPL =
            matching.flatMap {
                CalibrationMath.approximateSPLDB(
                    rmsDBFS:
                        microphoneCapture.snapshot
                            .rmsDBFS,
                    profile: $0,
                    currentRouteSignature:
                        audioSession.routeSignature
                )
            }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    "Calibration",
                    systemImage: "scope"
                )
                .font(.headline)

                Spacer()

                if matching != nil {
                    Text("Route matched")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                } else {
                    Text("No matching profile")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            Text("Capture a 5-second quiet reference with generated output off. QuietDrive stores a route-specific microphone, timing, and vibration baseline. Native measurements remain dBFS/g; optional external SPL creates only an approximate route-specific offset.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField(
                "Optional external SPL reference (dB)",
                text: $externalSPLReferenceText
            )
            .textFieldStyle(.roundedBorder)
            .keyboardType(.decimalPad)
            .disabled(calibration.state.isRunning)

            Text("If you use an external sound meter, enter its simultaneous reading before calibration. QuietDrive does not apply A/C weighting or certify the phone as an SPL meter.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Start 5s Calibration") {
                    startCalibration()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartCalibration)

                if calibration.state.isRunning {
                    Button("Cancel") {
                        calibration.cancel()
                    }
                    .buttonStyle(.bordered)
                }
            }

            switch calibration.state {
            case .idle:
                if !canStartCalibration {
                    Text("Requires active audio session, microphone + accelerometer capture, generated tone off/muted, fresh FFT/motion data, no clipping, and no likely program-audio interference.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case let .capturing(collected, required):
                ProgressView(
                    value: Double(collected),
                    total: Double(required)
                )
                Text(
                    "\(collected) / \(required) fresh paired calibration samples"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            case .completed:
                Text("Calibration profile saved.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)

            case let .failed(message):
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }

            if let profile = matching {
                Divider()

                Text("Current matching reference")
                    .font(.subheadline.weight(.semibold))

                LabeledContent(
                    "Captured",
                    value: profile.capturedAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )

                LabeledContent(
                    "Route",
                    value: profile.routeFamily.rawValue
                )

                LabeledContent(
                    "Reference mic RMS",
                    value: String(
                        format: "%.1f dBFS",
                        profile.microphoneRMSDBFS
                    )
                )

                LabeledContent(
                    "Mic variation σ",
                    value: String(
                        format: "%.2f dB",
                        profile
                            .microphoneRMSStandardDeviationDB
                    )
                )

                LabeledContent(
                    "LF / wide floor",
                    value: String(
                        format: "%.1f / %.1f dBFS",
                        profile.lowFrequencyFloorDBFS,
                        profile.widebandFloorDBFS
                    )
                )

                if
                    let target =
                        profile.targetFrequencyHz,
                    let energy =
                        profile.targetBandEnergyDBFS
                {
                    LabeledContent(
                        "Target reference",
                        value: String(
                            format:
                                "%.0f Hz • %.1f dBFS",
                            target,
                            energy
                        )
                    )
                }

                LabeledContent(
                    "Vibration RMS",
                    value: String(
                        format: "%.3f mg",
                        profile.dynamicVibrationRMSG *
                            1_000
                    )
                )

                LabeledContent(
                    "Accelerometer rate",
                    value: String(
                        format: "%.1f Hz",
                        profile
                            .accelerometerObservedRateHz
                    )
                )

                LabeledContent(
                    "Callback jitter σ",
                    value: String(
                        format: "%.3f ms",
                        profile
                            .callbackJitterMilliseconds
                    )
                )

                LabeledContent(
                    "Spectrum-center age",
                    value: String(
                        format: "%.2f ms",
                        profile
                            .spectrumCenterAgeMilliseconds
                    )
                )

                if
                    let reference =
                        profile.externalReferenceSPLDB,
                    let offset =
                        profile.approximateSPLOffsetDB
                {
                    LabeledContent(
                        "External reference",
                        value: String(
                            format: "%.1f dB",
                            reference
                        )
                    )

                    LabeledContent(
                        "Approx. SPL offset",
                        value: String(
                            format: "%+.1f dB",
                            offset
                        )
                    )

                    if let approximateLiveSPL {
                        LabeledContent(
                            "Approx. live SPL",
                            value: String(
                                format: "%.1f dB",
                                approximateLiveSPL
                            )
                        )
                    }
                } else {
                    Text("No external SPL reference is attached to this profile; absolute SPL is intentionally unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Text("Saved calibration profiles")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("\(calibration.profiles.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = calibration.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            ForEach(
                Array(
                    calibration.profiles
                        .prefix(6)
                )
            ) { profile in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(profile.routeFamily.rawValue)
                            .font(.caption.weight(.semibold))

                        Spacer()

                        Text(
                            profile.capturedAt.formatted(
                                date: .numeric,
                                time: .shortened
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    Text(profile.outputRoute)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(
                        String(
                            format:
                                "%.0f Hz • mic %.1f dBFS • vibration %.3f mg",
                            profile.sampleRate,
                            profile.microphoneRMSDBFS,
                            profile.dynamicVibrationRMSG *
                                1_000
                        )
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                    Button("Delete Calibration") {
                        calibration.delete(
                            id: profile.id
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(calibration.state.isRunning)
                }
            }

            if !calibration.profiles.isEmpty {
                Button(
                    "Clear All Calibrations",
                    role: .destructive
                ) {
                    calibration.clearAll()
                }
                .buttonStyle(.bordered)
                .disabled(calibration.state.isRunning)
            }

            Text("A calibration profile is valid only for the same route signature and sample rate. Changing the microphone/output route intentionally removes the live match instead of reusing the wrong reference.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cancellationCard()
    }

    private var structuredLogCard: some View {
        let recent =
            Array(
                structuredLog.events
                    .suffix(12)
                    .reversed()
            )
        let exportEventCount =
            StructuredLogExporter
                .selectedEvents(
                    from:
                        structuredLog.events,
                    scope:
                        structuredLogExportScope,
                    currentSessionID:
                        structuredLog
                            .currentSessionID
                )
                .count

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    "Structured Logs",
                    systemImage: "list.bullet.rectangle"
                )
                .font(.headline)

                Spacer()

                Text("\(structuredLog.events.count) events")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("Versioned, machine-readable experiment events saved locally for export, dashboards, and repeatability analysis. Raw microphone audio and raw accelerometer streams are never written to this log.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            LabeledContent(
                "Current session",
                value: String(
                    structuredLog
                        .currentSessionID
                        .uuidString
                        .prefix(8)
                )
            )

            LabeledContent(
                "Current session events",
                value:
                    "\(structuredLog.currentSessionEvents.count)"
            )

            LabeledContent(
                "Saved sessions",
                value:
                    "\(structuredLog.distinctSessionCount)"
            )

            Divider()

            Text("Export")
                .font(.subheadline.weight(.semibold))

            Picker(
                "Export scope",
                selection:
                    $structuredLogExportScope
            ) {
                ForEach(
                    StructuredLogExportScope
                        .allCases
                ) { scope in
                    Text(scope.title)
                        .tag(scope)
                }
            }
            .pickerStyle(.segmented)

            LabeledContent(
                "Selected events",
                value:
                    "\(exportEventCount)"
            )

            HStack {
                Button {
                    prepareStructuredLogExport(
                        .json
                    )
                } label: {
                    Label(
                        "Export JSON",
                        systemImage:
                            "doc.text"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    exportEventCount == 0
                )

                Button {
                    prepareStructuredLogExport(
                        .csv
                    )
                } label: {
                    Label(
                        "Export CSV",
                        systemImage:
                            "tablecells"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(
                    exportEventCount == 0
                )
            }

            Text("JSON preserves the typed event schema. CSV flattens context plus every metric, text field, flag, and reference ID into analysis-friendly columns.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let feedback =
                structuredLogExportFeedback
            {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Log Confidence Snapshot") {
                    logConfidenceSnapshot()
                }
                .buttonStyle(.borderedProminent)

                if !structuredLog.events.isEmpty {
                    Button(
                        "Clear Logs",
                        role: .destructive
                    ) {
                        structuredLog.clearAll()
                        structuredLog.startSession(
                            context:
                                structuredLogContext,
                            text: [
                                "app_build":
                                    "4.3"
                            ]
                        )

                        Task { @MainActor in
                            await structuredLog
                                .flushPersistence()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let error = structuredLog.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if recent.isEmpty {
                Text("No structured events saved yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Divider()

                Text("Recent events")
                    .font(.subheadline.weight(.semibold))

                ForEach(recent) { event in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.kind.rawValue)
                                .font(.caption.monospaced())

                            Text(
                                event.recordedAt.formatted(
                                    date: .omitted,
                                    time: .standard
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("#\(event.sequence)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("The event store is capped at \(StructuredLogModel.maximumEventCount) records. Oldest events are pruned first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cancellationCard()
    }

    private var testDashboardCard: some View {
        let dashboard =
            TestDashboardAnalytics
                .snapshot(
                    events:
                        structuredLog.events,
                    scope: .allSaved,
                    currentSessionID:
                        structuredLog
                            .currentSessionID
                )
        let decision =
            LabGoNoGoAnalytics
                .snapshot(
                    events:
                        structuredLog.events,
                    currentSessionID:
                        structuredLog
                            .currentSessionID
                )

        return VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Label(
                    "Test Dashboard",
                    systemImage:
                        "rectangle.3.group"
                )
                .font(.headline)

                Spacer()

                Text(
                    "\(dashboard.sessionCount) sessions"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Text(
                "Review saved test coverage, A/B outcomes, confidence evidence, workflow completions and failures, safety mutes, and recent sessions in one place."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            HStack {
                LabeledContent(
                    "A/B",
                    value:
                        "\(dashboard.comparisonCount)"
                )

                LabeledContent(
                    "Routes",
                    value:
                        "\(dashboard.distinctRouteCount)"
                )

                LabeledContent(
                    "Failures",
                    value:
                        "\(dashboard.failureCount)"
                )
            }
            .font(.caption)

            NavigationLink {
                TestDashboardView()
            } label: {
                Label(
                    "Open Test Dashboard",
                    systemImage:
                        "chart.bar.xaxis"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            HStack {
                Text("Final Lab verdict")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(
                    decision.verdict
                        .rawValue
                )
                .font(
                    .caption
                        .weight(.bold)
                )
            }

            Text(
                "The final report combines evidence volume, overall confidence, cross-session repeatability, head-position robustness, and frequency breadth. GO means continue prototyping — not production-ready ANC."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .cancellationCard()
    }

    private var processingLatencyCard: some View {
        let latency =
            microphoneCapture.snapshot.processingLatency

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Processing Latency", systemImage: "timer")
                    .font(.headline)

                Spacer()

                if microphoneCapture.state == .capturing {
                    Text("Live")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                }
            }

            Text("Separates measured app/DSP timing from iOS-reported audio I/O latency. These numbers do not yet include measured Bluetooth or acoustic round-trip delay.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if microphoneCapture.state == .capturing {
                LabeledContent(
                    "Mic buffer duration",
                    value: String(
                        format: "%.2f ms",
                        microphoneCapture.snapshot
                            .bufferDurationMilliseconds
                    )
                )

                LabeledContent(
                    "Callback interval",
                    value: String(
                        format: "%.2f ms",
                        latency
                            .latestCallbackIntervalMilliseconds
                    )
                )

                LabeledContent(
                    "Callback average",
                    value: String(
                        format: "%.2f ms",
                        latency
                            .averageCallbackIntervalMilliseconds
                    )
                )

                LabeledContent(
                    "Callback jitter σ",
                    value: String(
                        format: "%.3f ms",
                        latency.callbackJitterMilliseconds
                    )
                )

                LabeledContent(
                    "Callback min / max",
                    value: String(
                        format: "%.2f / %.2f ms",
                        latency
                            .minimumCallbackIntervalMilliseconds,
                        latency
                            .maximumCallbackIntervalMilliseconds
                    )
                )

                Divider()

                LabeledContent(
                    "DSP processing latest",
                    value: String(
                        format: "%.2f ms",
                        latency
                            .latestAnalysisProcessingMilliseconds
                    )
                )

                LabeledContent(
                    "DSP processing average",
                    value: String(
                        format: "%.2f ms",
                        latency
                            .averageAnalysisProcessingMilliseconds
                    )
                )

                LabeledContent(
                    "DSP processing max",
                    value: String(
                        format: "%.2f ms",
                        latency
                            .maximumAnalysisProcessingMilliseconds
                    )
                )

                LabeledContent(
                    "FFT analysis window",
                    value: String(
                        format: "%.2f ms",
                        latency.fftWindowMilliseconds
                    )
                )

                LabeledContent(
                    "Published snapshot age",
                    value: String(
                        format: "%.2f ms",
                        latency.snapshotAgeMilliseconds
                    )
                )

                LabeledContent(
                    "Estimated spectrum-center age",
                    value: String(
                        format: "%.2f ms",
                        latency
                            .estimatedSpectrumCenterAgeMilliseconds
                    )
                )
            } else {
                Text("Start microphone capture to measure callback cadence and DSP timing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("iOS-reported route timing")
                .font(.subheadline.weight(.semibold))

            LabeledContent(
                "I/O buffer",
                value: String(
                    format: "%.2f ms",
                    audioSession.ioBufferDuration * 1_000
                )
            )

            LabeledContent(
                "Input latency",
                value: String(
                    format: "%.2f ms",
                    audioSession.inputLatency * 1_000
                )
            )

            LabeledContent(
                "Output latency",
                value: String(
                    format: "%.2f ms",
                    audioSession.outputLatency * 1_000
                )
            )

            Text("Estimated spectrum-center age describes how old the middle of the FFT time window is when the published snapshot is created. It is not end-to-end cancellation latency.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cancellationCard()
    }

    private var audioRouteTestingCard: some View {
        let inputRecords =
            AudioRouteTestingMath.records(
                from: audioSession.inputs
            )
        let outputRecords =
            AudioRouteTestingMath.records(
                from: audioSession.outputs
            )
        let family =
            AudioRouteTestingMath.classify(
                inputs: inputRecords,
                outputs: outputRecords
            )
        let signature =
            AudioRouteTestingMath.signature(
                inputs: inputRecords,
                outputs: outputRecords
            )

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Audio Route Testing", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)

                Spacer()

                Text(family.rawValue)
                    .font(.caption.weight(.bold))
            }

            Text("Capture comparable route snapshots after switching connection types. Each record stores route identity plus the current sample rate, buffer, iOS I/O latency, and measured processing timing.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            LabeledContent(
                "Route revision",
                value: "\(audioSession.routeRevision)"
            )

            LabeledContent(
                "Input",
                value: inputRouteSummary
            )

            LabeledContent(
                "Output",
                value: outputRouteSummary
            )

            LabeledContent(
                "Sample rate",
                value: String(
                    format: "%.0f Hz",
                    audioSession.sampleRate
                )
            )

            LabeledContent(
                "I/O buffer",
                value: String(
                    format: "%.2f ms",
                    audioSession.ioBufferDuration * 1_000
                )
            )

            LabeledContent(
                "Input latency",
                value: String(
                    format: "%.2f ms",
                    audioSession.inputLatency * 1_000
                )
            )

            LabeledContent(
                "Output latency",
                value: String(
                    format: "%.2f ms",
                    audioSession.outputLatency * 1_000
                )
            )

            Text(
                signature.isEmpty
                    ? "No active route signature"
                    : signature
            )
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

            HStack {
                Button("Refresh Route") {
                    audioSession.refreshRoute()
                }
                .buttonStyle(.bordered)

                Button("Capture Route Test") {
                    let record = audioRouteTesting.capture(
                        inputs: audioSession.inputs,
                        outputs: audioSession.outputs,
                        routeRevision:
                            audioSession.routeRevision,
                        sampleRate:
                            audioSession.sampleRate,
                        ioBufferDuration:
                            audioSession.ioBufferDuration,
                        inputLatency:
                            audioSession.inputLatency,
                        outputLatency:
                            audioSession.outputLatency,
                        microphoneSnapshot:
                            microphoneCapture.snapshot
                    )
                    logRouteTest(record)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCaptureRouteTest)
            }

            if !canCaptureRouteTest {
                Text("Activate the audio session and run microphone capture until at least one FFT transform is available before saving a route test.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text("Saved route tests")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(
                    "\(audioRouteTesting.records.count) tests • \(audioRouteTesting.distinctRouteCount) routes"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let error = audioRouteTesting.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if audioRouteTesting.records.isEmpty {
                Text("No route tests saved yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(
                    Array(
                        audioRouteTesting.records
                            .prefix(10)
                            .enumerated()
                    ),
                    id: \.element.id
                ) { index, record in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(record.family.rawValue)
                                .font(.subheadline.weight(.semibold))

                            Spacer()

                            Text(
                                record.capturedAt.formatted(
                                    date: .abbreviated,
                                    time: .standard
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        Text(
                            String(
                                format:
                                    "%.0f Hz • buffer %.2f ms • in %.2f ms • out %.2f ms",
                                record.sampleRate,
                                record.ioBufferMilliseconds,
                                record.inputLatencyMilliseconds,
                                record.outputLatencyMilliseconds
                            )
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                        Text(
                            String(
                                format:
                                    "callback %.2f ± %.3f ms • DSP %.2f ms • spectrum center %.2f ms",
                                record.callbackAverageMilliseconds,
                                record.callbackJitterMilliseconds,
                                record.analysisAverageMilliseconds,
                                record.estimatedSpectrumCenterAgeMilliseconds
                            )
                        )
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                        Text(
                            "IN: " +
                            routePortSummary(record.inputs)
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                        Text(
                            "OUT: " +
                            routePortSummary(record.outputs)
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                        Button("Delete Route Test") {
                            audioRouteTesting.delete(
                                id: record.id
                            )
                        }
                        .buttonStyle(.bordered)

                        if index <
                            min(
                                audioRouteTesting.records.count,
                                10
                            ) - 1
                        {
                            Divider()
                        }
                    }
                }

                if audioRouteTesting.records.count > 10 {
                    Text("Showing the 10 most recent route tests.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Clear All Route Tests", role: .destructive) {
                    audioRouteTesting.clearAll()
                }
                .buttonStyle(.bordered)
            }

            Text("Route snapshots are diagnostic metadata only; they do not measure acoustic round-trip latency. Bluetooth-specific behavior is #26 and jitter characterization is #27.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cancellationCard()
    }

    private var bluetoothBehaviorCard: some View {
        let inputs =
            AudioRouteTestingMath.records(
                from: audioSession.inputs
            )
        let outputs =
            AudioRouteTestingMath.records(
                from: audioSession.outputs
            )
        let behavior =
            BluetoothBehaviorMath.behavior(
                inputs: inputs,
                outputs: outputs,
                routeRevision:
                    audioSession.routeRevision,
                sampleRate:
                    audioSession.sampleRate,
                ioBufferDuration:
                    audioSession.ioBufferDuration,
                inputLatency:
                    audioSession.inputLatency,
                outputLatency:
                    audioSession.outputLatency,
                records:
                    audioRouteTesting.records
            )

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Bluetooth Behavior", systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)

                Spacer()

                Text(behavior.profile.rawValue)
                    .font(.caption.weight(.bold))
            }

            Text("Characterizes the Bluetooth path from the active route plus saved route tests. This is observational route behavior, not a prediction that Bluetooth will be suitable for cancellation.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            LabeledContent(
                "Topology",
                value: behavior.topology.rawValue
            )

            LabeledContent(
                "Bluetooth input",
                value: behavior.hasBluetoothInput
                    ? "Yes"
                    : "No"
            )

            LabeledContent(
                "Bluetooth output",
                value: behavior.hasBluetoothOutput
                    ? "Yes"
                    : "No"
            )

            LabeledContent(
                "Route revision",
                value: "\(behavior.routeRevision)"
            )

            LabeledContent(
                "Sample rate",
                value: String(
                    format: "%.0f Hz",
                    behavior.sampleRate
                )
            )

            LabeledContent(
                "I/O buffer",
                value: String(
                    format: "%.2f ms",
                    behavior.ioBufferMilliseconds
                )
            )

            LabeledContent(
                "Input latency",
                value: String(
                    format: "%.2f ms",
                    behavior.inputLatencyMilliseconds
                )
            )

            LabeledContent(
                "Output latency",
                value: String(
                    format: "%.2f ms",
                    behavior.outputLatencyMilliseconds
                )
            )

            if
                let nonBluetooth =
                    behavior
                        .nonBluetoothOutputLatencyAverageMilliseconds,
                let delta =
                    behavior
                        .outputLatencyDeltaVersusNonBluetoothMilliseconds
            {
                LabeledContent(
                    "Saved non-Bluetooth output avg",
                    value: String(
                        format: "%.2f ms",
                        nonBluetooth
                    )
                )

                LabeledContent(
                    "Current output delta",
                    value: String(
                        format: "%+.2f ms",
                        delta
                    )
                )
            }

            Divider()

            LabeledContent(
                "Saved Bluetooth tests",
                value: "\(behavior.savedBluetoothTestCount)"
            )

            LabeledContent(
                "Distinct Bluetooth routes",
                value: "\(behavior.distinctBluetoothRouteCount)"
            )

            LabeledContent(
                "Observed profile switches",
                value: "\(behavior.observedProfileSwitchCount)"
            )

            LabeledContent(
                "Observed profiles",
                value:
                    behavior.observedProfiles.isEmpty
                    ? "None yet"
                    : behavior.observedProfiles
                        .map(\.rawValue)
                        .joined(separator: ", ")
            )

            if let stats = behavior.currentProfileStatistics {
                Divider()

                Text("\(stats.profile.rawValue) saved-test averages")
                    .font(.subheadline.weight(.semibold))

                LabeledContent(
                    "Tests",
                    value: "\(stats.recordCount)"
                )

                LabeledContent(
                    "Sample rate",
                    value: String(
                        format: "%.0f Hz",
                        stats.averageSampleRate
                    )
                )

                LabeledContent(
                    "I/O buffer",
                    value: String(
                        format: "%.2f ms",
                        stats.averageIOBufferMilliseconds
                    )
                )

                LabeledContent(
                    "Input / output latency",
                    value: String(
                        format: "%.2f / %.2f ms",
                        stats.averageInputLatencyMilliseconds,
                        stats.averageOutputLatencyMilliseconds
                    )
                )

                LabeledContent(
                    "Callback jitter σ",
                    value: String(
                        format: "%.3f ms",
                        stats.averageCallbackJitterMilliseconds
                    )
                )

                LabeledContent(
                    "Spectrum-center age",
                    value: String(
                        format: "%.2f ms",
                        stats.averageSpectrumCenterAgeMilliseconds
                    )
                )
            }

            if behavior.profile == .none {
                Text("Connect a Bluetooth route, run microphone capture, and save route tests to build a Bluetooth behavior record.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Save several route tests for this profile under the same physical setup. #27 will analyze timing variation/jitter across the Bluetooth path rather than relying only on one snapshot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cancellationCard()
    }

    private var bluetoothJitterCard: some View {
        let inputRecords =
            AudioRouteTestingMath.records(
                from: audioSession.inputs
            )
        let outputRecords =
            AudioRouteTestingMath.records(
                from: audioSession.outputs
            )
        let profile =
            BluetoothBehaviorMath.profile(
                inputs: inputRecords,
                outputs: outputRecords
            )

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Bluetooth Jitter", systemImage: "waveform.path.ecg")
                    .font(.headline)

                Spacer()

                if bluetoothJitterDiagnostics.state.isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else if
                    let snapshot =
                        bluetoothJitterDiagnostics.snapshot
                {
                    Text(snapshot.stability.rawValue)
                        .font(.caption.weight(.bold))
                }
            }

            Text("Runs a live ~30 second timing window at 4 samples/second. It measures observable app/route timing variation; it does not claim direct codec or acoustic round-trip jitter.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            LabeledContent(
                "Active profile",
                value: profile.rawValue
            )

            HStack {
                Button("Start 30s Jitter Run") {
                    startBluetoothJitterRun()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartBluetoothJitterRun)

                if bluetoothJitterDiagnostics.state.isRunning {
                    Button("Stop Jitter Run") {
                        bluetoothJitterDiagnostics.stop()
                    }
                    .buttonStyle(.bordered)
                } else if
                    bluetoothJitterDiagnostics.snapshot != nil
                {
                    Button("Reset") {
                        bluetoothJitterDiagnostics.reset()
                    }
                    .buttonStyle(.bordered)
                }
            }

            switch bluetoothJitterDiagnostics.state {
            case .idle:
                if !canStartBluetoothJitterRun {
                    Text("Use an active Bluetooth route with microphone capture running and at least one FFT transform available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .running:
                Text(
                    "\(bluetoothJitterDiagnostics.samples.count) / \(BluetoothJitterDiagnosticsModel.maximumSamples) fresh samples"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            case .completed:
                Text("Timing window complete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case let .failed(message):
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }

            if let snapshot = bluetoothJitterDiagnostics.snapshot {
                Divider()

                LabeledContent(
                    "Observed timing",
                    value: snapshot.stability.rawValue
                )

                LabeledContent(
                    "Fresh samples",
                    value: "\(snapshot.sampleCount)"
                )

                LabeledContent(
                    "Elapsed",
                    value: String(
                        format: "%.1f sec",
                        snapshot.elapsedSeconds
                    )
                )

                LabeledContent(
                    "Callback mean / jitter σ",
                    value: String(
                        format: "%.2f / %.3f ms",
                        snapshot.callbackMeanMilliseconds,
                        snapshot.callbackJitterMilliseconds
                    )
                )

                LabeledContent(
                    "Callback range",
                    value: String(
                        format: "%.2f ms",
                        snapshot.callbackRangeMilliseconds
                    )
                )

                LabeledContent(
                    "Spectrum-center mean / jitter σ",
                    value: String(
                        format: "%.2f / %.2f ms",
                        snapshot.spectrumCenterAgeMeanMilliseconds,
                        snapshot.spectrumCenterAgeJitterMilliseconds
                    )
                )

                LabeledContent(
                    "Spectrum-center range",
                    value: String(
                        format: "%.2f ms",
                        snapshot.spectrumCenterAgeRangeMilliseconds
                    )
                )

                LabeledContent(
                    "Reported output latency mean / jitter σ",
                    value: String(
                        format: "%.2f / %.3f ms",
                        snapshot.outputLatencyMeanMilliseconds,
                        snapshot.outputLatencyJitterMilliseconds
                    )
                )

                LabeledContent(
                    "Reported output latency range",
                    value: String(
                        format: "%.2f ms",
                        snapshot.outputLatencyRangeMilliseconds
                    )
                )

                Divider()

                LabeledContent(
                    "Route revision changes",
                    value: "\(snapshot.routeRevisionChangeCount)"
                )

                LabeledContent(
                    "Profile changes",
                    value: "\(snapshot.profileChangeCount)"
                )

                LabeledContent(
                    "I/O buffer changes",
                    value: "\(snapshot.ioBufferChangeCount)"
                )

                LabeledContent(
                    "Sample-rate changes",
                    value: "\(snapshot.sampleRateChangeCount)"
                )
            }

            Text("The stability label is based only on observable timing. A route can look stable here and still have unmeasured Bluetooth transport/acoustic delay. Physical loopback is still required before treating phase as route-stable.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cancellationCard()
    }

    private var accelerometerCard: some View {
        let snapshot = accelerometerCapture.snapshot

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Accelerometer", systemImage: "iphone.gen3.motion")
                    .font(.headline)

                Spacer()

                Text(accelerometerCapture.state.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(
                        accelerometerCapture.state == .capturing
                            ? Color.green
                            : Color.secondary
                    )
            }

            Text("Captures raw device acceleration locally at a requested 200 Hz. Core Motion may cap delivery lower on some hardware, so the observed rate is measured and used for all vibration frequency math.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                if accelerometerCapture.state == .capturing {
                    Button("Stop Accelerometer") {
                        accelerometerCapture.stop()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Start Accelerometer") {
                        accelerometerCapture.start()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!accelerometerCapture.isAvailable)
                }

                Button("Reset Motion Data") {
                    accelerometerCapture.reset()
                }
                .buttonStyle(.bordered)
                .disabled(accelerometerCapture.state == .capturing)
            }

            if !accelerometerCapture.isAvailable {
                Text("Accelerometer data is unavailable on this device/runtime. A physical iPhone is required for meaningful vehicle vibration capture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case let .failed(message) = accelerometerCapture.state {
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }

            if let latest = snapshot.latestSample {
                Divider()

                Text("Latest acceleration")
                    .font(.subheadline.weight(.semibold))

                LabeledContent(
                    "X",
                    value: String(
                        format: "%+.4f g",
                        latest.xG
                    )
                )

                LabeledContent(
                    "Y",
                    value: String(
                        format: "%+.4f g",
                        latest.yG
                    )
                )

                LabeledContent(
                    "Z",
                    value: String(
                        format: "%+.4f g",
                        latest.zG
                    )
                )

                LabeledContent(
                    "Magnitude",
                    value: String(
                        format: "%.4f g",
                        latest.magnitudeG
                    )
                )
            }

            Divider()

            LabeledContent(
                "Requested rate",
                value: String(
                    format: "%.0f Hz",
                    AccelerometerCaptureModel.requestedSampleRateHz
                )
            )

            LabeledContent(
                "Observed rate",
                value: snapshot.observedSampleRateHz > 0
                    ? String(
                        format: "%.1f Hz",
                        snapshot.observedSampleRateHz
                    )
                    : "—"
            )

            LabeledContent(
                "Average interval",
                value: snapshot.averageIntervalMilliseconds > 0
                    ? String(
                        format: "%.3f ms",
                        snapshot.averageIntervalMilliseconds
                    )
                    : "—"
            )

            LabeledContent(
                "Interval jitter σ",
                value: snapshot.intervalJitterMilliseconds > 0
                    ? String(
                        format: "%.3f ms",
                        snapshot.intervalJitterMilliseconds
                    )
                    : "—"
            )

            LabeledContent(
                "Interval min / max",
                value: snapshot.averageIntervalMilliseconds > 0
                    ? String(
                        format: "%.3f / %.3f ms",
                        snapshot.minimumIntervalMilliseconds,
                        snapshot.maximumIntervalMilliseconds
                    )
                    : "—"
            )

            LabeledContent(
                "Samples captured",
                value: "\(snapshot.totalSampleCount)"
            )

            LabeledContent(
                "Samples retained",
                value: "\(snapshot.storedSampleCount) / \(AccelerometerCaptureModel.retainedSampleCapacity)"
            )

            LabeledContent(
                "Elapsed",
                value: String(
                    format: "%.1f sec",
                    snapshot.elapsedSeconds
                )
            )

            Text("Raw acceleration includes gravity and phone-orientation effects. The vibration spectrum removes the slow/static component before frequency analysis.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Raw motion samples remain in memory only and are not uploaded or written to the experiment history.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cancellationCard()
    }

    private var vibrationSpectrumCard: some View {
        let spectrum =
            accelerometerCapture.vibrationSpectrum

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Vibration Spectrum", systemImage: "waveform")
                    .font(.headline)

                Spacer()

                if spectrum.sampleCount > 0 {
                    Text(
                        String(
                            format: "%.1f Hz max",
                            spectrum.maximumAnalyzedFrequencyHz
                        )
                    )
                    .font(.caption.weight(.bold))
                }
            }

            Text("High-pass filters each accelerometer axis to remove gravity/slow tilt, resamples the latest motion window uniformly, FFTs X/Y/Z separately, then combines their amplitudes so dominant vibration frequencies are less dependent on phone orientation.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VibrationSpectrumView(
                snapshot: spectrum
            )

            if spectrum.sampleCount > 0 {
                LabeledContent(
                    "FFT samples",
                    value: "\(spectrum.sampleCount)"
                )

                LabeledContent(
                    "Observed motion rate",
                    value: String(
                        format: "%.1f Hz",
                        spectrum.observedSampleRateHz
                    )
                )

                LabeledContent(
                    "Nyquist",
                    value: String(
                        format: "%.1f Hz",
                        spectrum.nyquistFrequencyHz
                    )
                )

                LabeledContent(
                    "Analyzed band",
                    value: String(
                        format: "%.1f–%.1f Hz",
                        VibrationSpectrumAnalyzer.minimumAnalyzedFrequencyHz,
                        spectrum.maximumAnalyzedFrequencyHz
                    )
                )

                LabeledContent(
                    "Resolution",
                    value: String(
                        format: "%.3f Hz",
                        spectrum.frequencyResolutionHz
                    )
                )

                LabeledContent(
                    "High-pass cutoff",
                    value: String(
                        format: "%.1f Hz",
                        spectrum.highPassCutoffHz
                    )
                )

                LabeledContent(
                    "Dynamic RMS",
                    value: String(
                        format: "%.3f mg",
                        spectrum.dynamicRMSG * 1_000
                    )
                )

                Divider()

                Text("Dominant vibration peaks")
                    .font(.subheadline.weight(.semibold))

                if spectrum.dominantPeaks.isEmpty {
                    Text("No dominant vibration peaks above the current detection floor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(
                        Array(
                            spectrum.dominantPeaks
                                .enumerated()
                        ),
                        id: \.element.id
                    ) { index, peak in
                        LabeledContent(
                            "#\(index + 1)",
                            value: String(
                                format: "%.2f Hz • %.3f mg",
                                peak.frequencyHz,
                                peak.amplitudeMilliG
                            )
                        )
                    }
                }

                if spectrum.canResolveSeventyTwoHz {
                    Text("This observed sample rate can directly resolve a 72 Hz vibration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(
                        String(
                            format:
                                "This device/run cannot directly resolve 72 Hz: the safe analyzed limit is %.1f Hz. Higher-frequency peaks are intentionally not inferred.",
                            spectrum.maximumAnalyzedFrequencyHz
                        )
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("Collect at least 256 fresh accelerometer samples to populate the vibration spectrum.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Spectrum amplitudes are relative device acceleration in milli-g, not calibrated vehicle-body displacement or force.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cancellationCard()
    }

    private var soundVibrationCorrelationCard: some View {
        let summary =
            soundVibrationCorrelation.summary
        let sound =
            microphoneCapture.snapshot
        let vibration =
            accelerometerCapture
                .vibrationSpectrum
        let tolerance =
            SoundVibrationCorrelationMath
                .matchingToleranceHz(
                    audioResolutionHz:
                        sound.fftResolutionHz,
                    vibrationResolutionHz:
                        vibration
                            .frequencyResolutionHz
                )

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    "Sound ↔ Vibration Correlation",
                    systemImage:
                        "waveform.path.ecg.rectangle"
                )
                .font(.headline)

                Spacer()

                if soundVibrationCorrelation
                    .state.isRunning
                {
                    ProgressView()
                        .controlSize(.small)
                } else if
                    summary.opportunityCount > 0
                {
                    Text(summary.level.rawValue)
                        .font(.caption.weight(.bold))
                }
            }

            Text("Runs a 30-second paired analysis. Fresh microphone and accelerometer spectra are sampled together every 0.5 seconds, then shared-frequency matches are tracked over time. Frequency agreement and amplitude co-movement are reported separately.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if vibration.sampleCount > 0 {
                LabeledContent(
                    "Current overlap ceiling",
                    value: String(
                        format: "%.1f Hz",
                        vibration
                            .maximumAnalyzedFrequencyHz
                    )
                )

                LabeledContent(
                    "Current match tolerance",
                    value: String(
                        format: "±%.2f Hz",
                        tolerance
                    )
                )
            }

            HStack {
                Button("Start 30s Correlation") {
                    startSoundVibrationCorrelation()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !canStartSoundVibrationCorrelation
                )

                if soundVibrationCorrelation
                    .state.isRunning
                {
                    Button("Stop Correlation") {
                        soundVibrationCorrelation
                            .stop()
                    }
                    .buttonStyle(.bordered)
                } else if
                    summary.opportunityCount > 0
                {
                    Button("Reset") {
                        soundVibrationCorrelation
                            .reset()
                    }
                    .buttonStyle(.bordered)
                }
            }

            switch soundVibrationCorrelation.state {
            case .idle:
                if !canStartSoundVibrationCorrelation {
                    Text("Run microphone capture and accelerometer capture until both sound and vibration spectra are populated.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .running:
                Text(
                    "\(summary.opportunityCount) / \(SoundVibrationCorrelationModel.maximumObservations) fresh paired observations"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            case .completed:
                Text("Correlation window complete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case let .failed(message):
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }

            if summary.opportunityCount > 0 {
                Divider()

                LabeledContent(
                    "Assessment",
                    value: summary.level.rawValue
                )

                if let frequency =
                    summary.primarySharedFrequencyHz
                {
                    LabeledContent(
                        "Primary shared frequency",
                        value: String(
                            format: "%.2f Hz",
                            frequency
                        )
                    )
                }

                LabeledContent(
                    "Primary track observations",
                    value:
                        "\(summary.primaryTrackObservationCount) / \(summary.opportunityCount)"
                )

                LabeledContent(
                    "Match presence",
                    value: String(
                        format: "%.0f%%",
                        summary.matchPresenceRatio *
                            100
                    )
                )

                if let delta =
                    summary.averageFrequencyDeltaHz
                {
                    LabeledContent(
                        "Average frequency delta",
                        value: String(
                            format: "%.2f Hz",
                            delta
                        )
                    )
                }

                if let agreement =
                    summary.averageFrequencyAgreement
                {
                    LabeledContent(
                        "Average frequency agreement",
                        value: String(
                            format: "%.0f%%",
                            agreement * 100
                        )
                    )
                }

                if let correlation =
                    summary.amplitudeCorrelation
                {
                    LabeledContent(
                        "Amplitude co-movement r",
                        value: String(
                            format: "%+.3f",
                            correlation
                        )
                    )
                } else {
                    LabeledContent(
                        "Amplitude co-movement r",
                        value: "Not enough variation"
                    )
                }

                LabeledContent(
                    "Persistent sound matches",
                    value: String(
                        format: "%.0f%%",
                        summary
                            .persistentSoundRatio *
                            100
                    )
                )

                LabeledContent(
                    "Avg sound persistence confidence",
                    value: String(
                        format: "%.0f%%",
                        summary
                            .averageSoundPersistenceConfidence *
                            100
                    )
                )
            }

            if !soundVibrationCorrelation
                .latestMatches.isEmpty
            {
                Divider()

                Text("Latest shared-frequency matches")
                    .font(.subheadline.weight(.semibold))

                ForEach(
                    Array(
                        soundVibrationCorrelation
                            .latestMatches
                            .prefix(3)
                    )
                ) { match in
                    LabeledContent(
                        String(
                            format:
                                "%.2f Hz sound",
                            match.soundFrequencyHz
                        ),
                        value: String(
                            format:
                                "%.2f Hz vibration • Δ %.2f Hz",
                            match.vibrationFrequencyHz,
                            match.frequencyDeltaHz
                        )
                    )
                }
            }

            Text("A shared frequency is evidence that cabin sound and device vibration occupy the same band. A positive amplitude correlation means their measured strengths tend to rise and fall together. Neither result by itself proves that structural vibration caused the sound.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Only frequencies inside the vibration analyzer's Nyquist-safe band can be correlated. Higher microphone tones are left unresolved rather than aliased into a false vibration match.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cancellationCard()
    }

    private var musicInterferenceCard: some View {
        let interference =
            microphoneCapture.snapshot
                .musicInterference

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    "Music / Program Interference",
                    systemImage: "music.note.list"
                )
                .font(.headline)

                Spacer()

                Text(interference.level.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(
                        musicInterferenceColor(
                            interference.level
                        )
                    )
            }

            Text("Automatically scores whether the microphone spectrum looks like broad, changing program audio rather than a narrow cabin/engine tone. The detector uses the full 200–4000 Hz spectrum even while ANC Focus is selected.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if interference.updateCount == 0 {
                Text("Start microphone capture and wait for the FFT to populate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent(
                    "Interference score",
                    value: String(
                        format: "%.0f%%",
                        interference.smoothedScore *
                            100
                    )
                )

                LabeledContent(
                    "Instantaneous score",
                    value: String(
                        format: "%.0f%%",
                        interference.instantaneousScore *
                            100
                    )
                )

                Divider()

                LabeledContent(
                    "Program band (200–4000 Hz)",
                    value: String(
                        format: "%.1f dBFS",
                        interference.programBandLevelDBFS
                    )
                )

                LabeledContent(
                    "Low band (30–200 Hz)",
                    value: String(
                        format: "%.1f dBFS",
                        interference.lowBandLevelDBFS
                    )
                )

                LabeledContent(
                    "Program vs low",
                    value: String(
                        format: "%+.1f dB",
                        interference.programToLowRatioDB
                    )
                )

                LabeledContent(
                    "Broadband occupancy",
                    value: String(
                        format: "%.0f%%",
                        interference.occupiedBinRatio *
                            100
                    )
                )

                LabeledContent(
                    "Spectral flatness",
                    value: String(
                        format: "%.3f",
                        interference.spectralFlatness
                    )
                )

                LabeledContent(
                    "Spectral change",
                    value: String(
                        format: "%.0f%%",
                        interference.spectralFlux *
                            100
                    )
                )

                LabeledContent(
                    "FFT updates",
                    value: "\(interference.updateCount)"
                )
            }

            switch interference.level {
            case .clear:
                Text("No strong program-audio-like contamination is currently detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .possible:
                Text("Broadband or program-like energy is present, but the evidence is not strong enough to call it likely music. Treat acoustic measurements with some caution.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .likely:
                Text("Likely program-audio interference is contaminating the microphone spectrum. #32 will discount confidence while this condition is active.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("A single QuietDrive sine tone is intentionally not enough to trigger the detector: narrow spectra are capped as Clear, and broad-but-static spectra cannot reach Likely without temporal change.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("This is a spectral interference detector, not a content recognizer. It cannot identify a song or prove that the source is music; speech and other changing broadband audio may also register as interference.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cancellationCard()
    }

    private func musicInterferenceColor(
        _ level: MusicInterferenceLevel
    ) -> Color {
        switch level {
        case .clear:
            return .green
        case .possible:
            return .orange
        case .likely:
            return .red
        }
    }

    private var overallConfidenceCard: some View {
        let confidence =
            overallConfidenceSnapshot

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    "Overall Confidence",
                    systemImage:
                        "gauge.with.dots.needle.67percent"
                )
                .font(.headline)

                Spacer()

                Text(confidence.level.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(
                        overallConfidenceColor(
                            confidence.level
                        )
                    )
            }

            HStack(alignment: .firstTextBaseline) {
                Text(
                    String(
                        format: "%.0f",
                        confidence.scorePercent
                    )
                )
                .font(
                    .system(
                        size: 42,
                        weight: .bold,
                        design: .rounded
                    )
                )

                Text("/ 100")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Evidence coverage")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(
                        String(
                            format: "%.0f%%",
                            confidence
                                .evidenceCoveragePercent
                        )
                    )
                    .font(.title3.weight(.semibold))
                }
            }

            ProgressView(
                value:
                    confidence.scorePercent,
                total: 100
            )

            Text("Confidence measures how trustworthy the current experimental evidence is. It is not the measured dB reduction and is not a probability that full-car ANC will work.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            Text("Evidence breakdown")
                .font(.subheadline.weight(.semibold))

            ForEach(confidence.components) { component in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(component.id.rawValue)
                            .font(.subheadline)

                        Spacer()

                        if let score = component.score {
                            Text(
                                String(
                                    format:
                                        "%.0f%% • %.0f pts",
                                    score * 100,
                                    component.weight *
                                        score
                                )
                            )
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        } else {
                            Text("Missing")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(
                        String(
                            format:
                                "Weight %.0f • %@",
                            component.weight,
                            component.detail
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if !confidence.limitingFactors.isEmpty {
                Divider()

                Text("Limiting factors")
                    .font(.subheadline.weight(.semibold))

                ForEach(
                    Array(
                        confidence
                            .limitingFactors
                            .enumerated()
                    ),
                    id: \.offset
                ) { _, factor in
                    Text("• \(factor)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Hard caps prevent a strong result in one metric from hiding unsafe or contaminated evidence: clipping and ≥3 dB target amplification cap confidence at 20, adaptive fail-safe at 35, unstable Bluetooth timing at 55, and likely program-audio interference at 60.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("High confidence still means only that the current evidence is internally strong and consistent. Physical repeatability across vehicles, routes, speeds, positions, and days remains a separate proof step.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cancellationCard()
    }

    private var overallConfidenceSnapshot:
        OverallConfidenceSnapshot
    {
        let sound =
            microphoneCapture.snapshot
        let inputRecords =
            AudioRouteTestingMath.records(
                from: audioSession.inputs
            )
        let outputRecords =
            AudioRouteTestingMath.records(
                from: audioSession.outputs
            )
        let bluetoothProfile =
            BluetoothBehaviorMath.profile(
                inputs: inputRecords,
                outputs: outputRecords
            )
        let bluetoothActive =
            bluetoothProfile != .none
        let matchingBluetoothJitter:
            BluetoothJitterSnapshot?

        if
            let snapshot =
                bluetoothJitterDiagnostics.snapshot,
            snapshot.profile ==
                bluetoothProfile
        {
            matchingBluetoothJitter =
                snapshot
        } else {
            matchingBluetoothJitter =
                nil
        }

        let adaptiveFailed: Bool

        if case .failed =
            adaptiveController.state
        {
            adaptiveFailed = true
        } else {
            adaptiveFailed = false
        }

        let comparison:
            BeforeAfterComparison?

        if
            let current =
                beforeAfterMeasurement.comparison,
            abs(
                current
                    .baseline
                    .condition
                    .targetFrequencyHz -
                toneGenerator.frequencyHz
            ) <= 0.5,
            baselineMatchesCurrentHeadPosition,
            baselineMatchesCurrentRoute
        {
            comparison = current
        } else {
            comparison = nil
        }

        let processingJitter: Double?

        if sound.fftTransformCount > 0 {
            processingJitter =
                sound
                    .processingLatency
                    .callbackJitterMilliseconds
        } else {
            processingJitter = nil
        }

        return OverallConfidenceMath.score(
            input: OverallConfidenceInput(
                persistentToneUpdateCount:
                    sound
                        .persistentTones
                        .updateCount,
                persistentTones:
                    sound
                        .persistentTones
                        .tones,
                comparison: comparison,
                adaptiveEvidencePresent:
                    adaptiveFailed ||
                    adaptiveController
                        .iterationCount > 0 ||
                    adaptiveController
                        .lastObservation != nil,
                adaptiveFailed:
                    adaptiveFailed,
                adaptiveIterations:
                    adaptiveController
                        .iterationCount,
                adaptiveRollbacks:
                    adaptiveController
                        .rollbackCount,
                adaptiveStabilityHoldCount:
                    adaptiveController
                        .stabilityHoldCount,
                adaptivePhaseReversalStreak:
                    adaptiveController
                        .phaseDirectionReversalStreak,
                adaptiveAmplitudeReversalStreak:
                    adaptiveController
                        .amplitudeDirectionReversalStreak,
                adaptiveTreatmentStandardDeviationDB:
                    adaptiveController
                        .lastObservation?
                        .treatment
                        .standardDeviationDB,
                processingCallbackJitterMilliseconds:
                    processingJitter,
                processingAnalysisMilliseconds:
                    sound.fftTransformCount > 0
                    ? sound
                        .processingLatency
                        .latestAnalysisProcessingMilliseconds
                    : nil,
                processingBufferDurationMilliseconds:
                    sound.fftTransformCount > 0
                    ? sound
                        .bufferDurationMilliseconds
                    : nil,
                bluetoothActive:
                    bluetoothActive,
                bluetoothJitter:
                    matchingBluetoothJitter,
                soundVibration:
                    soundVibrationCorrelation
                        .summary,
                musicInterference:
                    sound
                        .musicInterference,
                microphoneIsClipping:
                    sound.isClipping
            )
        )
    }

    private func overallConfidenceColor(
        _ level: OverallConfidenceLevel
    ) -> Color {
        switch level {
        case .insufficientEvidence:
            return .secondary
        case .low:
            return .red
        case .moderate:
            return .orange
        case .high:
            return .green
        }
    }

    private var targetCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Target Tone", systemImage: "scope")
                    .font(.headline)

                Spacer()

                Text(
                    String(
                        format: "%.0f Hz",
                        toneGenerator.frequencyHz
                    )
                )
                .font(.title3.monospacedDigit().weight(.semibold))
            }

            if let detectedTone = bestPersistentTone {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Detected persistent tone")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(
                            String(
                                format: "%.1f Hz • %@ %.0f%%",
                                detectedTone.frequencyHz,
                                detectedTone.confidenceLevel.rawValue,
                                detectedTone.confidence * 100
                            )
                        )
                        .font(.subheadline.monospacedDigit())
                    }

                    Spacer()

                    Button("Use Tone") {
                        toneGenerator.setFrequency(
                            detectedTone.frequencyHz
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(toneGenerator.state == .playing)
                }
            } else {
                Text("No persistent tone is available yet. You can set the target manually or run microphone capture until one is detected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { toneGenerator.frequencyHz },
                    set: { toneGenerator.setFrequency($0) }
                ),
                in: 30...200,
                step: 1
            )
            .disabled(toneGenerator.state == .playing)

            HStack {
                Text("30 Hz")
                Spacer()
                Text("200 Hz")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Menu {
                ForEach(
                    FrequencyCoverageAnalytics
                        .recommendedTargetsHz,
                    id: \.self
                ) { frequency in
                    Button(
                        String(
                            format:
                                "%.0f Hz",
                            frequency
                        )
                    ) {
                        toneGenerator
                            .setFrequency(
                                frequency
                            )
                    }
                }
            } label: {
                Label(
                    "Coverage Preset",
                    systemImage:
                        "waveform.badge.plus"
                )
            }
            .buttonStyle(.bordered)
            .disabled(
                toneGenerator.state ==
                    .playing
            )

            Text(
                "Coverage presets span the ANC band at 40, 60, 80, 100, 120, 160, and 200 Hz. Real detected cabin tones are more important than filling every preset."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            HStack {
                Text("Output")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(
                    String(
                        format: "%.0f%% • %.1f dBFS",
                        toneGenerator.outputPercent,
                        toneGenerator.targetLevelDBFS
                    )
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { toneGenerator.outputPercent },
                    set: { toneGenerator.setOutputPercent($0) }
                ),
                in: 0...100,
                step: 1
            )

            HStack {
                Text("0%")
                Spacer()
                Text("Hard-capped")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Divider()

            HStack {
                Text("Phase")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(
                    String(
                        format: "%.0f°",
                        toneGenerator.phaseDegrees
                    )
                )
                .font(.subheadline.monospacedDigit())
            }

            Slider(
                value: Binding(
                    get: { toneGenerator.phaseDegrees },
                    set: { toneGenerator.setPhaseDegrees($0) }
                ),
                in: 0...360,
                step: 1
            )

            HStack(spacing: 8) {
                phaseButton("0°", degrees: 0)
                phaseButton("90°", degrees: 90)
                phaseButton("180°", degrees: 180)
                phaseButton("270°", degrees: 270)
            }

            Button("Invert +180°") {
                toneGenerator.invertPhase()
            }
            .buttonStyle(.bordered)
        }
        .cancellationCard()
        .disabled(
            beforeAfterMeasurement.state.isBusy ||
            phaseSweep.state.isRunning ||
            phaseRefinement.state.isRunning ||
            amplitudeSearch.state.isRunning ||
            adaptiveController.state.isRunning
        )
    }

    private var targetEnergyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Target Energy", systemImage: "waveform.path")
                    .font(.headline)

                Spacer()

                if targetEnergyMeasurement != nil {
                    Text("Live")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                }
            }

            Text("Measured from the Balanced spectrum in a narrow multi-bin band around the selected target. Lower is quieter at that target.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let measurement = targetEnergyMeasurement {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Narrow-band energy")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(
                            String(
                                format: "%.1f dBFS",
                                measurement.bandEnergyDBFS
                            )
                        )
                        .font(.title2.monospacedDigit().weight(.semibold))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Center level")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(
                            String(
                                format: "%.1f dBFS",
                                measurement.centerLevelDBFS
                            )
                        )
                        .font(.headline.monospacedDigit())
                    }
                }

                Divider()

                if
                    let floor = measurement.floorBandEnergyDBFS,
                    let excess = measurement.excessDB
                {
                    LabeledContent(
                        "Tracked floor energy",
                        value: String(
                            format: "%.1f dBFS",
                            floor
                        )
                    )

                    LabeledContent(
                        "Above floor",
                        value: String(
                            format: "+%.1f dB",
                            excess
                        )
                    )
                } else {
                    LabeledContent(
                        "Tracked floor energy",
                        value: "Warming up"
                    )
                }

                LabeledContent(
                    "Measured target",
                    value: String(
                        format: "%.1f Hz",
                        measurement.targetFrequencyHz
                    )
                )

                LabeledContent(
                    "Nearest FFT bin",
                    value: String(
                        format: "%.1f Hz",
                        measurement.nearestBinFrequencyHz
                    )
                )

                LabeledContent(
                    "Measurement band",
                    value: String(
                        format: "%.1f–%.1f Hz • %d bins",
                        measurement.lowerFrequencyHz,
                        measurement.upperFrequencyHz,
                        measurement.binCount
                    )
                )

                LabeledContent(
                    "FFT resolution",
                    value: String(
                        format: "%.2f Hz/bin",
                        measurement.frequencyResolutionHz
                    )
                )
            } else {
                Text(
                    microphoneCapture.state == .capturing
                        ? "Waiting for enough FFT data to measure the selected target."
                        : "Start microphone capture to measure target-frequency energy."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Text("Relative digital measurement only. Keep phone position, route, stereo volume, and driving condition as consistent as possible when comparing settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cancellationCard()
    }

    private var headPositionCard: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Label(
                    "Head Position",
                    systemImage:
                        "figure.seated.side"
                )
                .font(.headline)

                Spacer()

                if
                    beforeAfterMeasurement
                        .baseline != nil
                {
                    Text(
                        baselineHeadPosition?
                            .title ??
                        "Unlabeled baseline"
                    )
                    .font(
                        .caption
                            .weight(.semibold)
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Text(
                "Label the listener posture before capturing a baseline. QuietDrive stores this label with every saved A/B result so the same settings can be compared across positions."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Picker(
                "Head position",
                selection:
                    $selectedHeadPosition
            ) {
                ForEach(
                    HeadPositionPreset
                        .allCases
                ) { position in
                    Text(
                        position.shortTitle
                    )
                    .tag(position)
                }
            }
            .pickerStyle(.segmented)
            .disabled(
                headPositionSelectionLocked
            )

            Text(
                selectedHeadPosition
                    .instruction
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if
                beforeAfterMeasurement
                    .baseline != nil,
                !baselineMatchesCurrentHeadPosition
            {
                Text(
                    "Head position changed after the baseline. Capture a fresh baseline at \(selectedHeadPosition.title) before collecting treatment or running automatic searches."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(
                "These are manual posture labels, not measured coordinates. Keep the phone, seat, route, speed, HVAC, and stereo volume as consistent as possible."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .cancellationCard()
    }

    private var headPositionSelectionLocked: Bool {
        beforeAfterMeasurement
            .state.isBusy ||
        phaseSweep.state.isRunning ||
        phaseRefinement.state.isRunning ||
        amplitudeSearch.state.isRunning ||
        adaptiveController.state.isRunning
    }

    private var beforeAfterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Before / After", systemImage: "arrow.left.arrow.right")
                    .font(.headline)

                Spacer()

                if beforeAfterMeasurement.state.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Each window averages 20 target-energy readings in linear power. Baseline is captured with generated output muted/off; treatment is captured with the tone actively audible.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let progress = comparisonProgressText {
                Text(progress)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Capture Baseline") {
                    captureBaseline()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    microphoneCapture.state != .capturing ||
                    !measurementWindowIsUsable ||
                    targetEnergyMeasurement == nil ||
                    beforeAfterMeasurement.state.isBusy ||
                    phaseSweep.state.isRunning ||
                    phaseRefinement.state.isRunning ||
                    amplitudeSearch.state.isRunning ||
                    adaptiveController.state.isRunning
                )

                Button("Capture Treatment") {
                    captureTreatment()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    beforeAfterMeasurement.baseline == nil ||
                    microphoneCapture.state != .capturing ||
                    toneGenerator.state != .playing ||
                    toneGenerator.isMuted ||
                    !measurementWindowIsUsable ||
                    targetEnergyMeasurement == nil ||
                    !baselineMatchesCurrentTarget ||
                    !baselineMatchesCurrentHeadPosition ||
                    !baselineMatchesCurrentRoute ||
                    beforeAfterMeasurement.state.isBusy ||
                    phaseSweep.state.isRunning ||
                    phaseRefinement.state.isRunning ||
                    amplitudeSearch.state.isRunning ||
                    adaptiveController.state.isRunning
                )
            }

            if
                beforeAfterMeasurement.baseline != nil,
                !baselineMatchesCurrentTarget
            {
                Text("The target frequency changed after the baseline. Capture a new baseline before comparing treatment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if
                beforeAfterMeasurement.baseline != nil,
                !baselineMatchesCurrentRoute
            {
                Text("The audio route changed after the baseline. Capture a fresh baseline on the current route before comparing treatment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if
                beforeAfterMeasurement.baseline != nil,
                !baselineMatchesCurrentHeadPosition
            {
                Text("The selected head position no longer matches the baseline. Capture a new baseline at the selected position.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if
                beforeAfterMeasurement.baseline != nil,
                toneGenerator.state == .playing,
                toneGenerator.isMuted
            {
                Text("Baseline captured. Set the phase/level you want to test, then Resume Tone before capturing treatment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case let .failed(message) = beforeAfterMeasurement.state {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let baseline = beforeAfterMeasurement.baseline {
                Divider()

                comparisonWindowRow(
                    title: "Baseline",
                    summary: baseline
                )
            }

            if let treatment = beforeAfterMeasurement.treatment {
                Divider()

                comparisonWindowRow(
                    title: "Treatment",
                    summary: treatment
                )
            }

            if let comparison = beforeAfterMeasurement.comparison {
                Divider()

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Measured change")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(comparisonResultText(comparison))
                            .font(.title3.monospacedDigit().weight(.semibold))
                    }

                    Spacer()

                    Text(
                        String(
                            format: "%+.2f dB treatment − baseline",
                            comparison.treatmentMinusBaselineDB
                        )
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                }

                Text("A positive measured reduction means the treatment window had less target-band energy than baseline. This is a relative A/B result, not calibrated SPL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(
                    comparisonKey(comparison) == lastSavedComparisonKey
                        ? "Run Saved"
                        : "Save Run"
                ) {
                    let record = experimentRecorder.record(
                        comparison: comparison,
                        inputRoute: inputRouteSummary,
                        outputRoute: outputRouteSummary
                    )
                    lastSavedComparisonKey = comparisonKey(comparison)

                    logExperimentRecord(
                        record,
                        kind: .comparisonSaved
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    comparisonKey(comparison) == lastSavedComparisonKey ||
                    !baselineMatchesCurrentRoute ||
                    phaseSweep.state.isRunning ||
                    phaseRefinement.state.isRunning ||
                    amplitudeSearch.state.isRunning ||
                    adaptiveController.state.isRunning
                )
            }

            if
                beforeAfterMeasurement.baseline != nil ||
                beforeAfterMeasurement.treatment != nil
            {
                Button("Reset Comparison") {
                    beforeAfterMeasurement.reset()
                    lastSavedComparisonKey = nil
                    baselineHeadPosition = nil
                    baselineRouteSignature = nil
                    baselineRouteRevision = nil
                }
                .buttonStyle(.bordered)
                .disabled(
                    beforeAfterMeasurement.state.isBusy ||
                    phaseSweep.state.isRunning ||
                    phaseRefinement.state.isRunning ||
                    amplitudeSearch.state.isRunning ||
                    adaptiveController.state.isRunning
                )
            }
        }
        .cancellationCard()
    }

    private var phaseSweepCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Automatic Phase Sweep", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)

                Spacer()

                if phaseSweep.state.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Coarse search: one baseline is reused while QuietDrive measures treatment at 0°, 45°, 90° … 315°. Each phase gets the same 20-sample treatment window.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let progress = phaseSweepProgressText {
                Text(progress)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Start 8-Phase Sweep") {
                    startPhaseSweep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartPhaseSweep)

                if phaseSweep.state.isRunning {
                    Button("Cancel Sweep") {
                        phaseSweep.cancel()
                        toneGenerator.muteImmediately()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if beforeAfterMeasurement.baseline == nil {
                Text("Capture a baseline first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !baselineMatchesCurrentTarget {
                Text("The baseline target no longer matches the selected target. Capture a new baseline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if toneGenerator.state == .playing && toneGenerator.isMuted {
                Text("Resume the tone before starting the sweep. The sweep will mute the tone automatically when it finishes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case let .failed(message) = phaseSweep.state {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if !phaseSweep.results.isEmpty {
                Divider()

                ForEach(phaseSweep.results) { result in
                    HStack {
                        Text(
                            String(
                                format: "%.0f°",
                                result.phaseDegrees
                            )
                        )
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .frame(width: 48, alignment: .leading)

                        Text(
                            String(
                                format: "%.2f dBFS",
                                result.treatment.averageBandEnergyDBFS
                            )
                        )
                        .font(.subheadline.monospacedDigit())

                        Spacer()

                        Text(
                            result.comparison.measuredReductionDB >= 0
                                ? String(
                                    format: "−%.2f dB",
                                    result.comparison.measuredReductionDB
                                )
                                : String(
                                    format: "+%.2f dB",
                                    abs(result.comparison.measuredReductionDB)
                                )
                        )
                        .font(.subheadline.monospacedDigit())
                    }
                }
            }

            if let best = phaseSweep.bestResult {
                Divider()

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Best coarse phase")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(
                            String(
                                format: "%.0f° • %.2f dBFS",
                                best.phaseDegrees,
                                best.treatment.averageBandEnergyDBFS
                            )
                        )
                        .font(.title3.monospacedDigit().weight(.semibold))
                    }

                    Spacer()

                    Text(
                        String(
                            format: "%.2f dB reduction",
                            best.comparison.measuredReductionDB
                        )
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                Button("Apply Best Coarse Phase") {
                    toneGenerator.setPhaseDegrees(
                        best.phaseDegrees
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(toneGenerator.state != .playing)

                Text("This is only the best point in the coarse 45° grid. #20 will refine the search around this region.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !phaseSweep.results.isEmpty &&
                !phaseSweep.state.isRunning
            {
                Button("Reset Sweep") {
                    phaseSweep.reset()
                    phaseRefinement.reset()
                    phaseRefinementProgressText = nil
                    amplitudeSearch.reset()
                    amplitudeSearchProgressText = nil
                }
                .buttonStyle(.bordered)
            }
        }
        .cancellationCard()
        .disabled(
            amplitudeSearch.state.isRunning ||
            adaptiveController.state.isRunning
        )
    }

    private var phaseRefinementCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Fine Phase Refinement", systemImage: "scope")
                    .font(.headline)

                Spacer()

                if phaseRefinement.state.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Two-stage search around the best coarse phase: first ±30° at 15° spacing, then ±10° around the Stage-1 winner at 5° spacing.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let progress = phaseRefinementProgressText {
                Text(progress)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Start Fine Search") {
                    startPhaseRefinement()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartPhaseRefinement)

                if phaseRefinement.state.isRunning {
                    Button("Cancel Fine Search") {
                        phaseRefinement.cancel()
                        phaseRefinementProgressText = nil
                        toneGenerator.muteImmediately()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if phaseSweep.bestResult == nil {
                Text("Run the coarse 8-phase sweep first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if toneGenerator.state == .playing && toneGenerator.isMuted {
                Text("Resume the tone before starting fine refinement. QuietDrive will mute it again when refinement finishes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case let .failed(message) = phaseRefinement.state {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            ForEach(phaseRefinement.stages, id: \.stage) { stage in
                Divider()

                HStack {
                    Text(
                        stage.stage == 1
                            ? "Stage 1 • 15° grid"
                            : "Stage 2 • 5° grid"
                    )
                    .font(.subheadline.weight(.semibold))

                    Spacer()

                    if let best = stage.bestResult {
                        Text(
                            String(
                                format: "best %.0f°",
                                best.phaseDegrees
                            )
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }

                ForEach(stage.results) { result in
                    HStack {
                        Text(
                            String(
                                format: "%.0f°",
                                result.phaseDegrees
                            )
                        )
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .frame(width: 48, alignment: .leading)

                        Text(
                            String(
                                format: "%.2f dBFS",
                                result.treatment.averageBandEnergyDBFS
                            )
                        )
                        .font(.subheadline.monospacedDigit())

                        Spacer()

                        Text(
                            result.comparison.measuredReductionDB >= 0
                                ? String(
                                    format: "−%.2f dB",
                                    result.comparison.measuredReductionDB
                                )
                                : String(
                                    format: "+%.2f dB",
                                    abs(result.comparison.measuredReductionDB)
                                )
                        )
                        .font(.subheadline.monospacedDigit())
                    }
                }
            }

            if let best = phaseRefinement.bestResult {
                Divider()

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Best refined phase")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(
                            String(
                                format: "%.0f° • %.2f dBFS",
                                best.phaseDegrees,
                                best.treatment.averageBandEnergyDBFS
                            )
                        )
                        .font(.title3.monospacedDigit().weight(.semibold))
                    }

                    Spacer()

                    Text(
                        String(
                            format: "%.2f dB reduction",
                            best.comparison.measuredReductionDB
                        )
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                Button("Apply Best Refined Phase") {
                    toneGenerator.setPhaseDegrees(
                        best.phaseDegrees
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(toneGenerator.state != .playing)

                Text("This is the best measured point on the 5° refinement grid. #21 will hold this phase while searching output amplitude.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !phaseRefinement.stages.isEmpty &&
                !phaseRefinement.state.isRunning
            {
                Button("Reset Fine Search") {
                    phaseRefinement.reset()
                    phaseRefinementProgressText = nil
                    amplitudeSearch.reset()
                    amplitudeSearchProgressText = nil
                }
                .buttonStyle(.bordered)
            }
        }
        .cancellationCard()
        .disabled(
            amplitudeSearch.state.isRunning ||
            adaptiveController.state.isRunning
        )
    }

    private var amplitudeSearchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Automatic Amplitude Search", systemImage: "speaker.wave.2")
                    .font(.headline)

                Spacer()

                if amplitudeSearch.state.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Holds the best refined phase fixed. Stage 1 searches in 10% output steps up to your current selected level; Stage 2 refines around the best result in 2% steps. The current selected output is the search ceiling.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let bestPhase = phaseRefinement.bestResult {
                LabeledContent(
                    "Fixed refined phase",
                    value: String(
                        format: "%.0f°",
                        bestPhase.phaseDegrees
                    )
                )
            }

            LabeledContent(
                "Current search ceiling",
                value: String(
                    format: "%.0f%%",
                    toneGenerator.outputPercent
                )
            )

            if let progress = amplitudeSearchProgressText {
                Text(progress)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Start Amplitude Search") {
                    startAmplitudeSearch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartAmplitudeSearch)

                if amplitudeSearch.state.isRunning {
                    Button("Cancel Amplitude Search") {
                        amplitudeSearch.cancel()
                        amplitudeSearchProgressText = nil
                        toneGenerator.muteImmediately()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if phaseRefinement.bestResult == nil {
                Text("Complete fine phase refinement first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if toneGenerator.outputPercent <
                AmplitudeSearchMath.minimumSearchPercent
            {
                Text("Set the output ceiling to at least 2%.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if toneGenerator.state == .playing &&
                toneGenerator.isMuted
            {
                Text("Resume the tone before starting amplitude search. QuietDrive will mute it again when the search finishes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case let .failed(message) = amplitudeSearch.state {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            ForEach(amplitudeSearch.stages, id: \.stage) { stage in
                Divider()

                HStack {
                    Text(
                        stage.stage == 1
                            ? "Stage 1 • coarse output"
                            : "Stage 2 • fine output"
                    )
                    .font(.subheadline.weight(.semibold))

                    Spacer()

                    if let best = stage.bestResult {
                        Text(
                            String(
                                format: "best %.0f%%",
                                best.outputPercent
                            )
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }

                ForEach(stage.results) { result in
                    HStack {
                        Text(
                            String(
                                format: "%.0f%%",
                                result.outputPercent
                            )
                        )
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .frame(width: 52, alignment: .leading)

                        Text(
                            String(
                                format: "%.2f dBFS",
                                result.treatment.averageBandEnergyDBFS
                            )
                        )
                        .font(.subheadline.monospacedDigit())

                        Spacer()

                        Text(
                            result.comparison.measuredReductionDB >= 0
                                ? String(
                                    format: "−%.2f dB",
                                    result.comparison.measuredReductionDB
                                )
                                : String(
                                    format: "+%.2f dB",
                                    abs(result.comparison.measuredReductionDB)
                                )
                        )
                        .font(.subheadline.monospacedDigit())
                    }
                }
            }

            if let best = amplitudeSearch.bestResult {
                Divider()

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Best output level")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(
                            String(
                                format: "%.0f%% • %.2f dBFS",
                                best.outputPercent,
                                best.treatment.averageBandEnergyDBFS
                            )
                        )
                        .font(.title3.monospacedDigit().weight(.semibold))
                    }

                    Spacer()

                    Text(
                        String(
                            format: "%.2f dB reduction",
                            best.comparison.measuredReductionDB
                        )
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                Button("Apply Best Output Level") {
                    toneGenerator.setOutputPercent(
                        best.outputPercent
                    )
                    toneGenerator.setPhaseDegrees(
                        best.phaseDegrees
                    )
                }
                .buttonStyle(.borderedProminent)

                Text(
                    String(
                        format: "Search ceiling was %.0f%%. The search never exceeded that user-selected level or the app's hard digital ceiling.",
                        amplitudeSearch.searchCeilingPercent
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !amplitudeSearch.stages.isEmpty &&
                !amplitudeSearch.state.isRunning
            {
                Button("Reset Amplitude Search") {
                    amplitudeSearch.reset()
                    amplitudeSearchProgressText = nil
                }
                .buttonStyle(.bordered)
            }
        }
        .cancellationCard()
        .disabled(adaptiveController.state.isRunning)
    }

    private var adaptiveControllerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Adaptive Controller", systemImage: "waveform.path.badge.plus")
                    .font(.headline)

                Spacer()

                if adaptiveController.state.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Starts from the best phase/output found by the search pipeline, then alternates tiny local probes: ±5° phase and ±2% output. A change must improve target-band energy by at least 0.35 dB or it is rolled back.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let seed = amplitudeSearch.bestResult {
                LabeledContent(
                    "Optimized starting point",
                    value: String(
                        format: "%.0f° • %.0f%%",
                        seed.phaseDegrees,
                        seed.outputPercent
                    )
                )

                LabeledContent(
                    "Adaptive output ceiling",
                    value: String(
                        format: "%.0f%%",
                        amplitudeSearch.searchCeilingPercent
                    )
                )
            }

            if let status = adaptiveControllerStatusText {
                Text(status)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Start Adaptive Controller") {
                    startAdaptiveController()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartAdaptiveController)

                if adaptiveController.state.isRunning {
                    Button("Stop + Mute") {
                        adaptiveController.cancel()
                        toneGenerator.muteImmediately()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if amplitudeSearch.bestResult == nil {
                Text("Complete automatic amplitude search first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if toneGenerator.state == .playing &&
                toneGenerator.isMuted
            {
                Text("Resume the tone before starting adaptive control.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case let .failed(message) = adaptiveController.state {
                Text("FAIL-SAFE: \(message)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
            }

            if let settings = adaptiveController.acceptedSettings {
                Divider()

                LabeledContent(
                    "Accepted phase",
                    value: String(
                        format: "%.0f°",
                        settings.phaseDegrees
                    )
                )

                LabeledContent(
                    "Accepted output",
                    value: String(
                        format: "%.0f%%",
                        settings.outputPercent
                    )
                )
            }

            if let observation = adaptiveController.lastObservation {
                LabeledContent(
                    "Last target energy",
                    value: String(
                        format: "%.2f dBFS",
                        observation.treatment.averageBandEnergyDBFS
                    )
                )

                LabeledContent(
                    "Last reduction",
                    value: String(
                        format: "%.2f dB",
                        observation.comparison.measuredReductionDB
                    )
                )

                LabeledContent(
                    "Measurement variability",
                    value: String(
                        format: "σ %.2f dB",
                        observation.treatment.standardDeviationDB
                    )
                )
            }

            LabeledContent(
                "Iterations",
                value: "\(adaptiveController.iterationCount)"
            )

            LabeledContent(
                "Accepted adjustments",
                value: "\(adaptiveController.acceptedAdjustmentCount)"
            )

            LabeledContent(
                "Rollbacks",
                value: "\(adaptiveController.rollbackCount)"
            )

            LabeledContent(
                "Last action",
                value: adaptiveController.lastAction
            )

            Divider()

            Text("Stability Protection")
                .font(.subheadline.weight(.semibold))

            LabeledContent(
                "Phase drift from seed",
                value: String(
                    format: "%.0f° / %.0f° max",
                    adaptiveController.phaseExcursionDegrees,
                    AdaptiveStabilityGuard.maximumPhaseExcursionDegrees
                )
            )

            LabeledContent(
                "Output drift from seed",
                value: String(
                    format: "%.0f%% / %.0f%% max",
                    adaptiveController.outputExcursionPercent,
                    AdaptiveStabilityGuard.maximumOutputExcursionPercent
                )
            )

            LabeledContent(
                "Stability holds",
                value: "\(adaptiveController.stabilityHoldCount)"
            )

            LabeledContent(
                "Hold remaining",
                value: "\(adaptiveController.stabilityHoldIterationsRemaining) iterations"
            )

            LabeledContent(
                "Phase reversal streak",
                value: "\(adaptiveController.phaseDirectionReversalStreak)"
            )

            LabeledContent(
                "Amplitude reversal streak",
                value: "\(adaptiveController.amplitudeDirectionReversalStreak)"
            )

            Text("Adaptive settings stay inside a trusted envelope around the optimized seed. Repeated rollbacks trigger temporary probe holds; repeated accepted direction reversals trigger fail-safe shutdown.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Fail-safe mute triggers on route/session loss, clipping, stale or missing target measurement, repeated unstable windows, oscillation, or measured target amplification of 3 dB or more above baseline.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Experimental lab control only. Do not operate these controls while driving; use a passenger or a controlled stationary/test setting.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .cancellationCard()
    }

    private var experimentHistoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Experiment History", systemImage: "clock.arrow.circlepath")
                    .font(.headline)

                Spacer()

                Text("\(experimentRecorder.records.count) saved")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("Saved locally as measurement summaries only. Raw microphone audio is never written to the experiment history.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let error = experimentRecorder.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if experimentRecorder.records.isEmpty {
                Text("No saved runs yet. Complete a baseline/treatment comparison and tap Save Run.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(experimentRecorder.records.prefix(20).enumerated()), id: \.element.id) { index, record in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    String(
                                        format: "%.0f Hz • %.0f° • %.0f%%",
                                        record.targetFrequencyHz,
                                        record.phaseDegrees,
                                        record.outputPercent
                                    )
                                )
                                .font(.subheadline.monospacedDigit().weight(.semibold))

                                Text(
                                    record.recordedAt.formatted(
                                        date: .abbreviated,
                                        time: .standard
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(
                                record.measuredReductionDB >= 0
                                    ? String(
                                        format: "−%.2f dB",
                                        record.measuredReductionDB
                                    )
                                    : String(
                                        format: "+%.2f dB",
                                        abs(record.measuredReductionDB)
                                    )
                            )
                            .font(.headline.monospacedDigit())
                        }

                        HStack {
                            Text(
                                String(
                                    format: "Baseline %.2f",
                                    record.baselineBandEnergyDBFS
                                )
                            )

                            Spacer()

                            Text(
                                String(
                                    format: "Treatment %.2f dBFS",
                                    record.treatmentBandEnergyDBFS
                                )
                            )
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                        Text(
                            String(
                                format: "σ %.2f → %.2f dB • %d/%d samples",
                                record.baselineStandardDeviationDB,
                                record.treatmentStandardDeviationDB,
                                record.baselineSampleCount,
                                record.treatmentSampleCount
                            )
                        )
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                        Text("Input: \(record.inputRoute)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("Output: \(record.outputRoute)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Button("Delete Run") {
                            experimentRecorder.delete(id: record.id)
                        }
                        .buttonStyle(.bordered)

                        if index <
                            min(
                                experimentRecorder.records.count,
                                20
                            ) - 1
                        {
                            Divider()
                        }
                    }
                }

                if experimentRecorder.records.count > 20 {
                    Text("Showing the 20 most recent runs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Clear All Saved Runs", role: .destructive) {
                    experimentRecorder.clearAll()
                    lastSavedComparisonKey = nil
                }
                .buttonStyle(.bordered)
            }
        }
        .cancellationCard()
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Experiment Controls", systemImage: "slider.horizontal.3")
                .font(.headline)

            HStack {
                Button(
                    microphoneCapture.state == .capturing
                        ? "Stop Capture"
                        : "Start Capture"
                ) {
                    if microphoneCapture.state == .capturing {
                        microphoneCapture.stopCapture()
                        _ = structuredLog.record(
                            kind: .captureStopped,
                            context: structuredLogContext
                        )
                    } else {
                        microphoneCapture.startCapture()
                        _ = structuredLog.record(
                            kind: .captureStarted,
                            context: structuredLogContext
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    audioSession.state != .active ||
                    beforeAfterMeasurement.state.isBusy ||
                    phaseSweep.state.isRunning ||
                    phaseRefinement.state.isRunning ||
                    amplitudeSearch.state.isRunning ||
                    adaptiveController.state.isRunning
                )

                Button(
                    toneGenerator.state == .playing
                        ? "Stop Tone"
                        : "Start Tone"
                ) {
                    if toneGenerator.state == .playing {
                        Task { @MainActor in
                            await toneGenerator.stop()
                            _ = structuredLog.record(
                                kind: .toneStopped,
                                context:
                                    structuredLogContext
                            )
                        }
                    } else {
                        toneGenerator.start()
                        _ = structuredLog.record(
                            kind: .toneStarted,
                            context: structuredLogContext
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    audioSession.state != .active ||
                    beforeAfterMeasurement.state.isBusy ||
                    phaseSweep.state.isRunning ||
                    phaseRefinement.state.isRunning ||
                    amplitudeSearch.state.isRunning ||
                    adaptiveController.state.isRunning
                )
            }

            Button("Start Capture + Tone") {
                if microphoneCapture.state != .capturing {
                    microphoneCapture.startCapture()
                    _ = structuredLog.record(
                        kind: .captureStarted,
                        context: structuredLogContext
                    )
                }

                if toneGenerator.state != .playing {
                    toneGenerator.start()
                    _ = structuredLog.record(
                        kind: .toneStarted,
                        context: structuredLogContext
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                !isExperimentReady ||
                bothRunning ||
                beforeAfterMeasurement.state.isBusy ||
                phaseSweep.state.isRunning ||
                phaseRefinement.state.isRunning ||
                amplitudeSearch.state.isRunning ||
                adaptiveController.state.isRunning
            )

            Button("Stop All") {
                beforeAfterMeasurement.cancelCapture()
                phaseSweep.cancel()
                phaseRefinement.cancel()
                phaseRefinementProgressText = nil
                amplitudeSearch.cancel()
                amplitudeSearchProgressText = nil
                adaptiveController.cancel()
                toneGenerator.stopImmediately()
                microphoneCapture.stopCapture()

                _ = structuredLog.record(
                    kind: .toneStopped,
                    context: structuredLogContext,
                    text: [
                        "reason": "stop_all"
                    ]
                )
                _ = structuredLog.record(
                    kind: .captureStopped,
                    context: structuredLogContext,
                    text: [
                        "reason": "stop_all"
                    ]
                )
            }
            .buttonStyle(.bordered)

            Text("The full manual-search pipeline now feeds the adaptive controller. Stop All remains the hard stop for every measurement/search/control loop.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .cancellationCard()
    }

    private var liveStateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Live State", systemImage: "waveform.path.ecg")
                .font(.headline)

            LabeledContent(
                "Microphone",
                value: microphoneCapture.state.label
            )

            LabeledContent(
                "Tone output",
                value: toneGenerator.isMuted &&
                    toneGenerator.state == .playing
                    ? "Muted"
                    : toneGenerator.state.label
            )

            LabeledContent(
                "Target",
                value: String(
                    format: "%.0f Hz",
                    toneGenerator.frequencyHz
                )
            )

            LabeledContent(
                "Phase",
                value: String(
                    format: "%.0f°",
                    toneGenerator.phaseDegrees
                )
            )

            LabeledContent(
                "Output",
                value: String(
                    format: "%.0f%%",
                    toneGenerator.outputPercent
                )
            )

            LabeledContent(
                "Persistent tones detected",
                value: "\(microphoneCapture.snapshot.persistentTones.persistentCount)"
            )

            if let detectedTone = bestPersistentTone {
                LabeledContent(
                    "Best persistent tone",
                    value: String(
                        format: "%.1f Hz",
                        detectedTone.frequencyHz
                    )
                )
            }
        }
        .cancellationCard()
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Safety", systemImage: "exclamationmark.shield")
                .font(.headline)

            Button(
                toneGenerator.isMuted
                    ? "Resume Tone"
                    : "MUTE NOW"
            ) {
                if toneGenerator.isMuted {
                    toneGenerator.unmute()
                    _ = structuredLog.record(
                        kind: .toneStarted,
                        context: structuredLogContext,
                        text: [
                            "action": "resume_from_mute"
                        ]
                    )
                } else {
                    phaseSweep.cancel()
                    phaseRefinement.cancel()
                    phaseRefinementProgressText = nil
                    amplitudeSearch.cancel()
                    amplitudeSearchProgressText = nil
                    adaptiveController.cancel()
                    toneGenerator.muteImmediately()
                    _ = structuredLog.record(
                        kind: .safetyMute,
                        context: structuredLogContext,
                        text: [
                            "action": "mute_now"
                        ]
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(toneGenerator.state != .playing)

            Text("The digital output ceiling does not control your car amplifier or speaker volume. Begin physical tests with the vehicle volume low and use MUTE NOW immediately if the tone is uncomfortable or behaves unexpectedly.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            LabeledContent(
                "Hard digital ceiling",
                value: String(
                    format: "%.1f dBFS",
                    toneGenerator.maximumLevelDBFS
                )
            )
        }
        .cancellationCard()
    }

    private func stopExperimentWorkForNavigation() {
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
            toneGenerator.state ==
                .playing
        {
            toneGenerator.muteImmediately()
        }
    }

    private var structuredLogContext:
        StructuredLogContext
    {
        let confidence =
            overallConfidenceSnapshot
        let matchingCalibration =
            calibration.latestMatchingProfile(
                routeSignature:
                    audioSession.routeSignature,
                sampleRate:
                    audioSession.sampleRate,
                ioBufferDuration:
                    audioSession.ioBufferDuration
            )

        return StructuredLogContext(
            routeSignature:
                audioSession.routeSignature,
            routeRevision:
                audioSession.routeRevision,
            calibrationProfileID:
                matchingCalibration?.id,
            targetFrequencyHz:
                toneGenerator.frequencyHz,
            phaseDegrees:
                toneGenerator.phaseDegrees,
            outputPercent:
                toneGenerator.outputPercent,
            confidenceScorePercent:
                confidence.scorePercent,
            evidenceCoveragePercent:
                confidence
                    .evidenceCoveragePercent,
            confidenceLevel:
                confidence.level.rawValue
        )
    }

    private func prepareStructuredLogExport(
        _ format: StructuredLogExportFormat
    ) {
        let selectedEvents =
            StructuredLogExporter
                .selectedEvents(
                    from:
                        structuredLog.events,
                    scope:
                        structuredLogExportScope,
                    currentSessionID:
                        structuredLog
                            .currentSessionID
                )

        guard !selectedEvents.isEmpty else {
            structuredLogExportFeedback =
                "No structured events are available for the selected scope."
            return
        }

        do {
            let data = try
                StructuredLogExporter
                    .data(
                        for: format,
                        events:
                            selectedEvents
                    )

            structuredLogExportFormat =
                format
            structuredLogExportDocument =
                StructuredLogExportDocument(
                    data: data
                )
            structuredLogExportFilename =
                StructuredLogExporter
                    .suggestedFilename(
                        format: format,
                        scope:
                            structuredLogExportScope
                    )
            structuredLogExportEventCount =
                selectedEvents.count
            structuredLogExportFeedback = nil
            isStructuredLogExporterPresented =
                true
        } catch {
            structuredLogExportFeedback =
                "Could not prepare " +
                format.title +
                " export: " +
                error.localizedDescription
        }
    }

    private func handleStructuredLogExportCompletion(
        _ result: Result<URL, Error>
    ) {
        switch result {
        case .success:
            structuredLogExportFeedback =
                "Exported " +
                String(
                    structuredLogExportEventCount
                ) +
                " events as " +
                structuredLogExportFormat
                    .title +
                "."

        case .failure(let error):
            structuredLogExportFeedback =
                "Export failed: " +
                error.localizedDescription
        }
    }

    private func logConfidenceSnapshot() {
        let confidence =
            overallConfidenceSnapshot

        _ = structuredLog.record(
            kind: .confidenceSnapshot,
            context:
                structuredLogContext,
            metrics: [
                "score_percent":
                    confidence.scorePercent,
                "evidence_coverage_percent":
                    confidence
                        .evidenceCoveragePercent
            ],
            text: [
                "level":
                    confidence.level.rawValue,
                "limiting_factors":
                    confidence
                        .limitingFactors
                        .joined(
                            separator: " | "
                        ),
                "head_position":
                    selectedHeadPosition
                        .rawValue,
                "head_position_title":
                    selectedHeadPosition
                        .title,
                ExperimentEvidenceQuality
                    .audioConfigurationTextKey:
                    audioConfigurationSignature
            ],
            flags: [
                "microphone_clipping":
                    microphoneCapture
                        .snapshot
                        .isClipping,
                "likely_program_interference":
                    microphoneCapture
                        .snapshot
                        .musicInterference
                        .level == .likely
            ]
        )
    }

    private func logExperimentRecord(
        _ record: ExperimentRecord,
        kind: StructuredLogEventKind
    ) {
        _ = structuredLog.record(
            kind: kind,
            context:
                structuredLogContext,
            metrics: [
                "baseline_band_energy_dbfs":
                    record
                        .baselineBandEnergyDBFS,
                "treatment_band_energy_dbfs":
                    record
                        .treatmentBandEnergyDBFS,
                "treatment_minus_baseline_db":
                    record
                        .treatmentMinusBaselineDB,
                "measured_reduction_db":
                    record.measuredReductionDB,
                "baseline_stddev_db":
                    record
                        .baselineStandardDeviationDB,
                "treatment_stddev_db":
                    record
                        .treatmentStandardDeviationDB,
                "baseline_sample_count":
                    Double(
                        record
                            .baselineSampleCount
                    ),
                "treatment_sample_count":
                    Double(
                        record
                            .treatmentSampleCount
                    )
            ],
            text: [
                "input_route":
                    record.inputRoute,
                "output_route":
                    record.outputRoute,
                "head_position":
                    (
                        baselineHeadPosition ??
                        selectedHeadPosition
                    ).rawValue,
                "head_position_title":
                    (
                        baselineHeadPosition ??
                        selectedHeadPosition
                    ).title,
                ExperimentEvidenceQuality
                    .audioConfigurationTextKey:
                    audioConfigurationSignature
            ],
            flags: [
                "quality_filtered_samples_only":
                    true,
                "microphone_clipping_at_log":
                    microphoneCapture
                        .snapshot
                        .isClipping,
                "likely_program_interference_at_log":
                    microphoneCapture
                        .snapshot
                        .musicInterference
                        .level == .likely
            ],
            references: [
                "experiment_record_id":
                    record.id.uuidString
            ]
        )
    }

    private func logWorkflowFailure(
        workflow: String,
        message: String
    ) {
        _ = structuredLog.record(
            kind: .workflowFailed,
            context: structuredLogContext,
            text: [
                "workflow": workflow,
                "message": message
            ],
            flags: [
                "success": false
            ]
        )
    }

    private func logRouteTest(
        _ record: AudioRouteTestRecord
    ) {
        _ = structuredLog.record(
            kind: .routeTestCaptured,
            context: structuredLogContext,
            metrics: [
                "sample_rate_hz":
                    record.sampleRate,
                "io_buffer_ms":
                    record.ioBufferMilliseconds,
                "input_latency_ms":
                    record.inputLatencyMilliseconds,
                "output_latency_ms":
                    record.outputLatencyMilliseconds,
                "callback_jitter_ms":
                    record.callbackJitterMilliseconds,
                "spectrum_center_age_ms":
                    record
                        .estimatedSpectrumCenterAgeMilliseconds
            ],
            text: [
                "route_family":
                    record.family.rawValue,
                "input_route":
                    routePortSummary(
                        record.inputs
                    ),
                "output_route":
                    routePortSummary(
                        record.outputs
                    )
            ],
            references: [
                "route_test_id":
                    record.id.uuidString
            ]
        )
    }

    private func logCalibrationOutcome() {
        switch calibration.state {
        case .completed:
            guard
                let profile =
                    calibration.lastCapturedProfile
            else {
                return
            }

            var metrics: [String: Double] = [
                "microphone_rms_dbfs":
                    profile.microphoneRMSDBFS,
                "microphone_rms_stddev_db":
                    profile
                        .microphoneRMSStandardDeviationDB,
                "low_frequency_floor_dbfs":
                    profile.lowFrequencyFloorDBFS,
                "wideband_floor_dbfs":
                    profile.widebandFloorDBFS,
                "dynamic_vibration_rms_g":
                    profile.dynamicVibrationRMSG,
                "accelerometer_rate_hz":
                    profile.accelerometerObservedRateHz,
                "callback_jitter_ms":
                    profile.callbackJitterMilliseconds,
                "spectrum_center_age_ms":
                    profile.spectrumCenterAgeMilliseconds
            ]

            if
                let target =
                    profile.targetBandEnergyDBFS
            {
                metrics[
                    "target_band_energy_dbfs"
                ] = target
            }

            if
                let reference =
                    profile.externalReferenceSPLDB
            {
                metrics[
                    "external_reference_spl_db"
                ] = reference
            }

            if
                let offset =
                    profile.approximateSPLOffsetDB
            {
                metrics[
                    "approximate_spl_offset_db"
                ] = offset
            }

            _ = structuredLog.record(
                kind: .calibrationCompleted,
                context: structuredLogContext,
                metrics: metrics,
                text: [
                    "route_family":
                        profile.routeFamily.rawValue
                ],
                flags: [
                    "has_external_spl_reference":
                        profile
                            .hasExternalSPLReference
                ],
                references: [
                    "calibration_profile_id":
                        profile.id.uuidString
                ]
            )

        case let .failed(message):
            _ = structuredLog.record(
                kind: .calibrationFailed,
                context: structuredLogContext,
                text: [
                    "message": message
                ],
                flags: [
                    "success": false
                ]
            )

        case .idle, .capturing:
            break
        }
    }

    private func logPhaseSweepOutcome() {
        if
            phaseSweep.state == .completed,
            let best = phaseSweep.bestResult
        {
            _ = structuredLog.record(
                kind: .phaseSweepCompleted,
                context: structuredLogContext,
                metrics: [
                    "result_count":
                        Double(
                            phaseSweep.results.count
                        ),
                    "best_phase_degrees":
                        best.phaseDegrees,
                    "best_treatment_dbfs":
                        best
                            .treatment
                            .averageBandEnergyDBFS,
                    "best_reduction_db":
                        best
                            .comparison
                            .measuredReductionDB
                ],
                flags: [
                    "success": true
                ]
            )
        } else if
            case let .failed(message) =
                phaseSweep.state
        {
            logWorkflowFailure(
                workflow: "phase_sweep",
                message: message
            )
        }
    }

    private func logPhaseRefinementOutcome() {
        if
            phaseRefinement.state == .completed,
            let best =
                phaseRefinement.bestResult
        {
            _ = structuredLog.record(
                kind: .phaseRefinementCompleted,
                context: structuredLogContext,
                metrics: [
                    "stage_count":
                        Double(
                            phaseRefinement.stages.count
                        ),
                    "best_phase_degrees":
                        best.phaseDegrees,
                    "best_treatment_dbfs":
                        best
                            .treatment
                            .averageBandEnergyDBFS,
                    "best_reduction_db":
                        best
                            .comparison
                            .measuredReductionDB
                ],
                flags: [
                    "success": true
                ]
            )
        } else if
            case let .failed(message) =
                phaseRefinement.state
        {
            logWorkflowFailure(
                workflow:
                    "phase_refinement",
                message: message
            )
        }
    }

    private func logAmplitudeSearchOutcome() {
        if
            amplitudeSearch.state == .completed,
            let best =
                amplitudeSearch.bestResult
        {
            _ = structuredLog.record(
                kind: .amplitudeSearchCompleted,
                context: structuredLogContext,
                metrics: [
                    "stage_count":
                        Double(
                            amplitudeSearch.stages.count
                        ),
                    "search_ceiling_percent":
                        amplitudeSearch
                            .searchCeilingPercent,
                    "best_output_percent":
                        best.outputPercent,
                    "best_phase_degrees":
                        best.phaseDegrees,
                    "best_treatment_dbfs":
                        best
                            .treatment
                            .averageBandEnergyDBFS,
                    "best_reduction_db":
                        best
                            .comparison
                            .measuredReductionDB
                ],
                flags: [
                    "success": true
                ]
            )
        } else if
            case let .failed(message) =
                amplitudeSearch.state
        {
            logWorkflowFailure(
                workflow:
                    "amplitude_search",
                message: message
            )
        }
    }

    private func logBluetoothJitterOutcome() {
        switch bluetoothJitterDiagnostics.state {
        case .completed:
            guard
                let snapshot =
                    bluetoothJitterDiagnostics.snapshot
            else {
                return
            }

            _ = structuredLog.record(
                kind: .bluetoothJitterCompleted,
                context: structuredLogContext,
                metrics: [
                    "sample_count":
                        Double(
                            snapshot.sampleCount
                        ),
                    "elapsed_seconds":
                        snapshot.elapsedSeconds,
                    "callback_jitter_ms":
                        snapshot
                            .callbackJitterMilliseconds,
                    "spectrum_center_age_jitter_ms":
                        snapshot
                            .spectrumCenterAgeJitterMilliseconds,
                    "output_latency_jitter_ms":
                        snapshot
                            .outputLatencyJitterMilliseconds,
                    "route_revision_changes":
                        Double(
                            snapshot
                                .routeRevisionChangeCount
                        ),
                    "profile_changes":
                        Double(
                            snapshot
                                .profileChangeCount
                        )
                ],
                text: [
                    "profile":
                        snapshot.profile.rawValue,
                    "stability":
                        snapshot.stability.rawValue
                ],
                flags: [
                    "success": true
                ]
            )

        case let .failed(message):
            logWorkflowFailure(
                workflow:
                    "bluetooth_jitter",
                message: message
            )

        case .idle, .running:
            break
        }
    }

    private func logCorrelationOutcome() {
        switch soundVibrationCorrelation.state {
        case .completed:
            let summary =
                soundVibrationCorrelation.summary

            var metrics: [String: Double] = [
                "opportunity_count":
                    Double(
                        summary.opportunityCount
                    ),
                "primary_track_count":
                    Double(
                        summary
                            .primaryTrackObservationCount
                    ),
                "match_presence_ratio":
                    summary.matchPresenceRatio,
                "persistent_sound_ratio":
                    summary.persistentSoundRatio
            ]

            if
                let frequency =
                    summary.primarySharedFrequencyHz
            {
                metrics[
                    "primary_shared_frequency_hz"
                ] = frequency
            }

            if
                let delta =
                    summary.averageFrequencyDeltaHz
            {
                metrics[
                    "average_frequency_delta_hz"
                ] = delta
            }

            if
                let correlation =
                    summary.amplitudeCorrelation
            {
                metrics[
                    "amplitude_correlation_r"
                ] = correlation
            }

            _ = structuredLog.record(
                kind:
                    .soundVibrationCorrelationCompleted,
                context: structuredLogContext,
                metrics: metrics,
                text: [
                    "level":
                        summary.level.rawValue
                ],
                flags: [
                    "success": true
                ]
            )

        case let .failed(message):
            logWorkflowFailure(
                workflow:
                    "sound_vibration_correlation",
                message: message
            )

        case .idle, .running:
            break
        }
    }

    private func logAdaptiveFailure(
        _ message: String
    ) {
        _ = structuredLog.record(
            kind: .adaptiveFailed,
            context: structuredLogContext,
            metrics: [
                "iterations":
                    Double(
                        adaptiveController
                            .iterationCount
                    ),
                "accepted_adjustments":
                    Double(
                        adaptiveController
                            .acceptedAdjustmentCount
                    ),
                "rollbacks":
                    Double(
                        adaptiveController
                            .rollbackCount
                    ),
                "stability_holds":
                    Double(
                        adaptiveController
                            .stabilityHoldCount
                    )
            ],
            text: [
                "message": message,
                "last_action":
                    adaptiveController.lastAction
            ],
            flags: [
                "success": false
            ]
        )
    }

    private func logAdaptiveStopped() {
        if case .failed =
            adaptiveController.state
        {
            return
        }

        _ = structuredLog.record(
            kind: .adaptiveStopped,
            context: structuredLogContext,
            metrics: [
                "iterations":
                    Double(
                        adaptiveController
                            .iterationCount
                    ),
                "accepted_adjustments":
                    Double(
                        adaptiveController
                            .acceptedAdjustmentCount
                    ),
                "rollbacks":
                    Double(
                        adaptiveController
                            .rollbackCount
                    ),
                "stability_holds":
                    Double(
                        adaptiveController
                            .stabilityHoldCount
                    )
            ],
            text: [
                "last_action":
                    adaptiveController.lastAction
            ]
        )
    }

    private var canStartSoundVibrationCorrelation: Bool {
        microphoneCapture.state ==
            .capturing &&
        accelerometerCapture.state ==
            .capturing &&
        audioSession.state == .active &&
        microphoneCapture.snapshot
            .fftTransformCount > 0 &&
        accelerometerCapture.snapshot
            .totalSampleCount > 0 &&
        accelerometerCapture
            .vibrationSpectrum
            .sampleCount > 0 &&
        !soundVibrationCorrelation
            .state.isRunning
    }

    private func startSoundVibrationCorrelation() {
        let routeRevision =
            audioSession.routeRevision

        Task { @MainActor in
            await soundVibrationCorrelation.run(
                sampleProvider: {
                    let sound =
                        microphoneCapture.snapshot
                    let vibration =
                        accelerometerCapture
                            .vibrationSpectrum
                    let motion =
                        accelerometerCapture
                            .snapshot

                    guard
                        sound.fftTransformCount > 0,
                        motion.totalSampleCount > 0,
                        vibration.sampleCount > 0
                    else {
                        return nil
                    }

                    return SoundVibrationCorrelationInput(
                        audioFFTTransformCount:
                            sound
                                .fftTransformCount,
                        motionSampleCount:
                            motion
                                .totalSampleCount,
                        audioResolutionHz:
                            sound
                                .fftResolutionHz,
                        vibrationResolutionHz:
                            vibration
                                .frequencyResolutionHz,
                        vibrationMaximumFrequencyHz:
                            vibration
                                .maximumAnalyzedFrequencyHz,
                        dominantSoundFrequencies:
                            sound
                                .dominantFrequencies
                                .frequencies,
                        persistentTones:
                            sound
                                .persistentTones
                                .tones,
                        vibrationPeaks:
                            vibration
                                .dominantPeaks
                    )
                },
                safetyCheck: {
                    if audioSession.state != .active {
                        return "Audio session became inactive."
                    }

                    if microphoneCapture.state != .capturing {
                        return "Microphone capture stopped."
                    }

                    if accelerometerCapture.state != .capturing {
                        return "Accelerometer capture stopped."
                    }

                    if audioSession.routeRevision != routeRevision {
                        return "Audio route changed during correlation."
                    }

                    return nil
                }
            )

            logCorrelationOutcome()
        }
    }

    private var canStartCalibration: Bool {
        let sound =
            microphoneCapture.snapshot
        let motion =
            accelerometerCapture.snapshot
        let toneIsQuiet =
            toneGenerator.state != .playing ||
            toneGenerator.isMuted

        return
            audioSession.state == .active &&
            microphoneCapture.state == .capturing &&
            accelerometerCapture.state == .capturing &&
            sound.fftTransformCount > 0 &&
            motion.totalSampleCount > 0 &&
            accelerometerCapture
                .vibrationSpectrum
                .sampleCount > 0 &&
            toneIsQuiet &&
            !sound.isClipping &&
            sound.musicInterference.level != .likely &&
            ProcessingLatencyMath
                .analysisFitsBufferBudget(
                    analysisProcessingMilliseconds:
                        sound
                            .processingLatency
                            .latestAnalysisProcessingMilliseconds,
                    bufferDurationMilliseconds:
                        sound
                            .bufferDurationMilliseconds
                ) &&
            !audioSession.inputs.isEmpty &&
            !audioSession.outputs.isEmpty &&
            !calibration.state.isRunning
    }

    private func parsedExternalSPLReference() -> Double? {
        let trimmed =
            externalSPLReferenceText
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        guard !trimmed.isEmpty else {
            return nil
        }

        return Double(trimmed)
    }

    private func startCalibration() {
        let routeSignature =
            audioSession.routeSignature
        let routeRevision =
            audioSession.routeRevision
        let inputRoute =
            inputRouteSummary
        let outputRoute =
            outputRouteSummary
        let inputRecords =
            AudioRouteTestingMath.records(
                from: audioSession.inputs
            )
        let outputRecords =
            AudioRouteTestingMath.records(
                from: audioSession.outputs
            )
        let routeFamily =
            AudioRouteTestingMath.classify(
                inputs: inputRecords,
                outputs: outputRecords
            )
        let target =
            toneGenerator.frequencyHz
        let externalReference =
            parsedExternalSPLReference()

        Task { @MainActor in
            await calibration.run(
                routeSignature:
                    routeSignature,
                routeFamily:
                    routeFamily,
                routeRevision:
                    routeRevision,
                inputRoute:
                    inputRoute,
                outputRoute:
                    outputRoute,
                sampleRate:
                    audioSession.sampleRate,
                ioBufferDuration:
                    audioSession.ioBufferDuration,
                inputLatency:
                    audioSession.inputLatency,
                outputLatency:
                    audioSession.outputLatency,
                targetFrequencyHz:
                    target,
                externalReferenceSPLDB:
                    externalReference,
                sampleProvider: {
                    let sound =
                        microphoneCapture.snapshot
                    let motion =
                        accelerometerCapture.snapshot
                    let vibration =
                        accelerometerCapture
                            .vibrationSpectrum
                    let targetMeasurement =
                        measurementForTarget(
                            target
                        )

                    return CalibrationSample(
                        fftTransformCount:
                            sound.fftTransformCount,
                        motionSampleCount:
                            motion.totalSampleCount,
                        microphoneRMSDBFS:
                            sound.rmsDBFS,
                        lowFrequencyFloorDBFS:
                            sound
                                .noiseFloor
                                .lowFrequencyFloorDBFS,
                        widebandFloorDBFS:
                            sound
                                .noiseFloor
                                .widebandFloorDBFS,
                        targetBandEnergyDBFS:
                            targetMeasurement?
                                .bandEnergyDBFS,
                        callbackJitterMilliseconds:
                            sound
                                .processingLatency
                                .callbackJitterMilliseconds,
                        spectrumCenterAgeMilliseconds:
                            sound
                                .processingLatency
                                .estimatedSpectrumCenterAgeMilliseconds,
                        accelerationXG:
                            motion.latestSample?
                                .xG,
                        accelerationYG:
                            motion.latestSample?
                                .yG,
                        accelerationZG:
                            motion.latestSample?
                                .zG,
                        dynamicVibrationRMSG:
                            vibration.dynamicRMSG,
                        accelerometerObservedRateHz:
                            motion
                                .observedSampleRateHz,
                        accelerometerIntervalJitterMilliseconds:
                            motion
                                .intervalJitterMilliseconds,
                        musicInterferenceScore:
                            sound
                                .musicInterference
                                .smoothedScore
                    )
                },
                safetyCheck: {
                    if audioSession.state != .active {
                        return "Audio session became inactive."
                    }

                    if
                        audioSession.routeSignature !=
                            routeSignature ||
                        audioSession.routeRevision !=
                            routeRevision
                    {
                        return "Audio route changed during calibration."
                    }

                    if microphoneCapture.state != .capturing {
                        return "Microphone capture stopped."
                    }

                    if accelerometerCapture.state != .capturing {
                        return "Accelerometer capture stopped."
                    }

                    if microphoneCapture.snapshot.isClipping {
                        return "Microphone clipping invalidated calibration."
                    }

                    if
                        !ProcessingLatencyMath
                            .analysisFitsBufferBudget(
                                analysisProcessingMilliseconds:
                                    microphoneCapture
                                        .snapshot
                                        .processingLatency
                                        .latestAnalysisProcessingMilliseconds,
                                bufferDurationMilliseconds:
                                    microphoneCapture
                                        .snapshot
                                        .bufferDurationMilliseconds
                            )
                    {
                        return "Audio analysis exceeded the microphone buffer budget."
                    }

                    if
                        microphoneCapture
                            .snapshot
                            .musicInterference
                            .level == .likely
                    {
                        return "Likely program-audio interference invalidated calibration."
                    }

                    if
                        toneGenerator.state == .playing &&
                        !toneGenerator.isMuted
                    {
                        return "Generated tone became audible during calibration."
                    }

                    return nil
                }
            )

            logCalibrationOutcome()
        }
    }

    private var canStartBluetoothJitterRun: Bool {
        let inputs =
            AudioRouteTestingMath.records(
                from: audioSession.inputs
            )
        let outputs =
            AudioRouteTestingMath.records(
                from: audioSession.outputs
            )

        return
            audioSession.state == .active &&
            BluetoothBehaviorMath.profile(
                inputs: inputs,
                outputs: outputs
            ) != .none &&
            microphoneCapture.state == .capturing &&
            microphoneCapture.snapshot.fftTransformCount > 0 &&
            !bluetoothJitterDiagnostics.state.isRunning
    }

    private func startBluetoothJitterRun() {
        let startedAt =
            ProcessInfo.processInfo.systemUptime

        Task { @MainActor in
            await bluetoothJitterDiagnostics.run(
                sampleProvider: {
                    let inputRecords =
                        AudioRouteTestingMath.records(
                            from: audioSession.inputs
                        )
                    let outputRecords =
                        AudioRouteTestingMath.records(
                            from: audioSession.outputs
                        )
                    let snapshot =
                        microphoneCapture.snapshot
                    let latency =
                        snapshot.processingLatency

                    return BluetoothJitterSample(
                        capturedAtSeconds:
                            ProcessInfo.processInfo.systemUptime -
                            startedAt,
                        fftTransformCount:
                            snapshot.fftTransformCount,
                        profile:
                            BluetoothBehaviorMath.profile(
                                inputs: inputRecords,
                                outputs: outputRecords
                            ),
                        routeRevision:
                            audioSession.routeRevision,
                        sampleRate:
                            audioSession.sampleRate,
                        ioBufferMilliseconds:
                            audioSession.ioBufferDuration * 1_000,
                        inputLatencyMilliseconds:
                            audioSession.inputLatency * 1_000,
                        outputLatencyMilliseconds:
                            audioSession.outputLatency * 1_000,
                        callbackIntervalMilliseconds:
                            latency
                                .latestCallbackIntervalMilliseconds,
                        spectrumCenterAgeMilliseconds:
                            latency
                                .estimatedSpectrumCenterAgeMilliseconds
                    )
                },
                safetyCheck: {
                    if audioSession.state != .active {
                        return "Audio session became inactive."
                    }

                    if microphoneCapture.state != .capturing {
                        return "Microphone capture stopped."
                    }

                    if audioSession.outputs.isEmpty {
                        return "Audio output route disappeared."
                    }

                    return nil
                }
            )

            logBluetoothJitterOutcome()
        }
    }

    private var canCaptureRouteTest: Bool {
        audioSession.state == .active &&
        !audioSession.inputs.isEmpty &&
        !audioSession.outputs.isEmpty &&
        microphoneCapture.state == .capturing &&
        microphoneCapture.snapshot.fftTransformCount > 0
    }

    private func routePortSummary(
        _ ports: [AudioRoutePortRecord]
    ) -> String {
        guard !ports.isEmpty else {
            return "None"
        }

        return ports
            .map { "\($0.name) • \($0.type)" }
            .joined(separator: ", ")
    }

    private var adaptiveControllerStatusText: String? {
        switch adaptiveController.state {
        case .idle:
            return nil
        case .starting:
            return "Starting • verifying optimized settings"
        case let .monitoring(iteration):
            return "Iteration \(iteration) • monitoring accepted settings"
        case let .probing(
            dimension,
            value,
            candidate,
            total
        ):
            if dimension == .phase {
                return String(
                    format:
                        "%@ probe %d/%d • %.0f°",
                    dimension.rawValue,
                    candidate,
                    total,
                    value
                )
            }

            return String(
                format:
                    "%@ probe %d/%d • %.0f%%",
                dimension.rawValue,
                candidate,
                total,
                value
            )
        case .running:
            return "Running • accepted settings active"
        case .failed:
            return nil
        }
    }

    private var canStartAdaptiveController: Bool {
        amplitudeSearch.bestResult != nil &&
        beforeAfterMeasurement.baseline != nil &&
        baselineMatchesCurrentTarget &&
        baselineMatchesCurrentHeadPosition &&
        baselineMatchesCurrentRoute &&
        microphoneCapture.state == .capturing &&
        microphoneCapture.analysisMode == .ancFocus &&
        audioSession.state == .active &&
        toneGenerator.state == .playing &&
        !toneGenerator.isMuted &&
        measurementWindowIsUsable &&
        targetEnergyMeasurement != nil &&
        !beforeAfterMeasurement.state.isBusy &&
        !phaseSweep.state.isRunning &&
        !phaseRefinement.state.isRunning &&
        !amplitudeSearch.state.isRunning &&
        !adaptiveController.state.isRunning
    }

    private func startAdaptiveController() {
        guard
            let optimized = amplitudeSearch.bestResult,
            let baseline = beforeAfterMeasurement.baseline
        else {
            return
        }

        let target = baseline.condition.targetFrequencyHz
        let inputRoute = inputRouteSummary
        let outputRoute = outputRouteSummary
        let ceiling = amplitudeSearch.searchCeilingPercent
        let seed = AdaptiveControllerSettings(
            phaseDegrees: optimized.phaseDegrees,
            outputPercent: optimized.outputPercent
        )

        Task { @MainActor in
            await adaptiveController.run(
                seedSettings: seed,
                ceilingPercent: ceiling,
                baseline: baseline,
                applySettings: { settings in
                    toneGenerator.setPhaseDegrees(
                        settings.phaseDegrees
                    )
                    toneGenerator.setOutputPercent(
                        settings.outputPercent
                    )
                },
                measurementProvider: {
                    sequencedMeasurementForTarget(
                        target
                    )
                },
                safetyCheck: {
                    if audioSession.state != .active {
                        return "Audio session became inactive."
                    }

                    if microphoneCapture.state != .capturing {
                        return "Microphone capture stopped."
                    }

                    if microphoneCapture.snapshot.isClipping {
                        return "Microphone input is clipping."
                    }

                    if
                        microphoneCapture.snapshot
                            .analysisDroppedBufferCount > 0
                    {
                        return "Audio analysis dropped frames; restart microphone capture before collecting more evidence."
                    }

                    if microphoneCapture.analysisMode != .ancFocus {
                        return "ANC Focus mode is no longer active."
                    }

                    if toneGenerator.state != .playing {
                        return "Tone generator stopped."
                    }

                    if toneGenerator.isMuted {
                        return "Tone output was muted."
                    }

                    if abs(
                        toneGenerator.frequencyHz -
                        target
                    ) > 0.5 {
                        return "Target frequency changed."
                    }

                    if inputRouteSummary != inputRoute {
                        return "Audio input route changed."
                    }

                    if outputRouteSummary != outputRoute {
                        return "Audio output route changed."
                    }

                    return nil
                },
                onAcceptedComparison: { comparison in
                    let record = experimentRecorder.record(
                        comparison: comparison,
                        inputRoute: inputRoute,
                        outputRoute: outputRoute
                    )
                    logExperimentRecord(
                        record,
                        kind: .comparisonSaved
                    )
                    logExperimentRecord(
                        record,
                        kind: .adaptiveAdjustmentAccepted
                    )
                },
                onFailSafe: { message in
                    logAdaptiveFailure(message)
                    toneGenerator.muteImmediately()
                }
            )

            logAdaptiveStopped()
        }
    }

    private var canStartAmplitudeSearch: Bool {
        phaseRefinement.bestResult != nil &&
        beforeAfterMeasurement.baseline != nil &&
        baselineMatchesCurrentTarget &&
        baselineMatchesCurrentHeadPosition &&
        baselineMatchesCurrentRoute &&
        microphoneCapture.state == .capturing &&
        toneGenerator.state == .playing &&
        !toneGenerator.isMuted &&
        toneGenerator.outputPercent >=
            AmplitudeSearchMath.minimumSearchPercent &&
        measurementWindowIsUsable &&
        targetEnergyMeasurement != nil &&
        !beforeAfterMeasurement.state.isBusy &&
        !phaseSweep.state.isRunning &&
        !phaseRefinement.state.isRunning &&
        !amplitudeSearch.state.isRunning &&
        !adaptiveController.state.isRunning
    }

    private func startAmplitudeSearch() {
        adaptiveController.reset()

        guard
            let refinedBest = phaseRefinement.bestResult,
            let baseline = beforeAfterMeasurement.baseline
        else {
            return
        }

        let target = baseline.condition.targetFrequencyHz
        let fixedPhase = refinedBest.phaseDegrees
        let ceiling = toneGenerator.outputPercent
        let inputRoute = inputRouteSummary
        let outputRoute = outputRouteSummary

        toneGenerator.setPhaseDegrees(fixedPhase)
        amplitudeSearchProgressText =
            "Preparing amplitude search..."

        Task { @MainActor in
            await amplitudeSearch.run(
                refinedPhaseDegrees: fixedPhase,
                ceilingPercent: ceiling,
                baseline: baseline,
                applyOutputPercent: { percent in
                    toneGenerator.setOutputPercent(percent)
                },
                measurementProvider: {
                    sequencedMeasurementForTarget(
                        target
                    )
                },
                onComparison: { comparison in
                    let record = experimentRecorder.record(
                        comparison: comparison,
                        inputRoute: inputRoute,
                        outputRoute: outputRoute
                    )
                    logExperimentRecord(
                        record,
                        kind: .comparisonSaved
                    )
                },
                onProgress: {
                    stage,
                    percent,
                    index,
                    total,
                    collected,
                    required in

                    if
                        let collected,
                        let required
                    {
                        amplitudeSearchProgressText =
                            String(
                                format:
                                    "Stage %d • %d/%d • %.0f%% • %d/%d samples",
                                stage,
                                index,
                                total,
                                percent,
                                collected,
                                required
                            )
                    } else {
                        amplitudeSearchProgressText =
                            String(
                                format:
                                    "Stage %d • %d/%d • %.0f%% • settling...",
                                stage,
                                index,
                                total,
                                percent
                            )
                    }
                }
            )

            logAmplitudeSearchOutcome()

            if amplitudeSearch.state == .completed {
                amplitudeSearchProgressText =
                    "Amplitude search complete"
                toneGenerator.muteImmediately()
            }
        }
    }

    private var canStartPhaseRefinement: Bool {
        phaseSweep.bestResult != nil &&
        beforeAfterMeasurement.baseline != nil &&
        baselineMatchesCurrentTarget &&
        baselineMatchesCurrentHeadPosition &&
        baselineMatchesCurrentRoute &&
        microphoneCapture.state == .capturing &&
        toneGenerator.state == .playing &&
        !toneGenerator.isMuted &&
        toneGenerator.outputPercent > 0 &&
        measurementWindowIsUsable &&
        targetEnergyMeasurement != nil &&
        !beforeAfterMeasurement.state.isBusy &&
        !phaseSweep.state.isRunning &&
        !phaseRefinement.state.isRunning &&
        !amplitudeSearch.state.isRunning &&
        !adaptiveController.state.isRunning
    }

    private func startPhaseRefinement() {
        adaptiveController.reset()
        amplitudeSearch.reset()
        amplitudeSearchProgressText = nil

        guard
            let coarseBest = phaseSweep.bestResult,
            let baseline = beforeAfterMeasurement.baseline
        else {
            return
        }

        let target = baseline.condition.targetFrequencyHz
        let output = toneGenerator.outputPercent
        let inputRoute = inputRouteSummary
        let outputRoute = outputRouteSummary

        phaseRefinementProgressText = "Preparing fine phase search..."

        Task { @MainActor in
            await phaseRefinement.run(
                coarseBestPhaseDegrees:
                    coarseBest.phaseDegrees,
                baseline: baseline,
                outputPercent: output,
                applyPhase: { phase in
                    toneGenerator.setPhaseDegrees(phase)
                },
                measurementProvider: {
                    sequencedMeasurementForTarget(
                        target
                    )
                },
                onComparison: { comparison in
                    let record = experimentRecorder.record(
                        comparison: comparison,
                        inputRoute: inputRoute,
                        outputRoute: outputRoute
                    )
                    logExperimentRecord(
                        record,
                        kind: .comparisonSaved
                    )
                },
                onProgress: {
                    stage,
                    phase,
                    index,
                    total,
                    collected,
                    required in

                    if
                        let collected,
                        let required
                    {
                        phaseRefinementProgressText =
                            String(
                                format:
                                    "Stage %d • %d/%d • %.0f° • %d/%d samples",
                                stage,
                                index,
                                total,
                                phase,
                                collected,
                                required
                            )
                    } else {
                        phaseRefinementProgressText =
                            String(
                                format:
                                    "Stage %d • %d/%d • %.0f° • settling...",
                                stage,
                                index,
                                total,
                                phase
                            )
                    }
                }
            )

            logPhaseRefinementOutcome()

            if phaseRefinement.state == .completed {
                phaseRefinementProgressText =
                    "Fine phase search complete"
                toneGenerator.muteImmediately()
            }
        }
    }

    private var phaseSweepProgressText: String? {
        switch phaseSweep.state {
        case .idle:
            nil
        case let .settling(phaseDegrees, index, total):
            String(
                format: "Phase %d/%d • %.0f° • settling...",
                index,
                total,
                phaseDegrees
            )
        case let .capturing(
            phaseDegrees,
            index,
            total,
            collected,
            required
        ):
            String(
                format: "Phase %d/%d • %.0f° • %d/%d samples",
                index,
                total,
                phaseDegrees,
                collected,
                required
            )
        case .completed:
            "Sweep complete"
        case .failed:
            nil
        }
    }

    private var canStartPhaseSweep: Bool {
        beforeAfterMeasurement.baseline != nil &&
        baselineMatchesCurrentTarget &&
        baselineMatchesCurrentHeadPosition &&
        baselineMatchesCurrentRoute &&
        microphoneCapture.state == .capturing &&
        toneGenerator.state == .playing &&
        !toneGenerator.isMuted &&
        toneGenerator.outputPercent > 0 &&
        measurementWindowIsUsable &&
        targetEnergyMeasurement != nil &&
        !beforeAfterMeasurement.state.isBusy &&
        !phaseSweep.state.isRunning &&
        !phaseRefinement.state.isRunning &&
        !amplitudeSearch.state.isRunning &&
        !adaptiveController.state.isRunning
    }

    private func startPhaseSweep() {
        adaptiveController.reset()
        phaseRefinement.reset()
        phaseRefinementProgressText = nil
        amplitudeSearch.reset()
        amplitudeSearchProgressText = nil

        guard
            let baseline = beforeAfterMeasurement.baseline
        else {
            return
        }

        let target = baseline.condition.targetFrequencyHz
        let output = toneGenerator.outputPercent
        let inputRoute = inputRouteSummary
        let outputRoute = outputRouteSummary

        lastSavedComparisonKey = nil

        Task { @MainActor in
            await phaseSweep.run(
                baseline: baseline,
                outputPercent: output,
                applyPhase: { phase in
                    toneGenerator.setPhaseDegrees(phase)
                },
                measurementProvider: {
                    sequencedMeasurementForTarget(
                        target
                    )
                },
                onComparison: { comparison in
                    let record = experimentRecorder.record(
                        comparison: comparison,
                        inputRoute: inputRoute,
                        outputRoute: outputRoute
                    )
                    logExperimentRecord(
                        record,
                        kind: .comparisonSaved
                    )
                }
            )

            logPhaseSweepOutcome()

            if phaseSweep.state == .completed {
                toneGenerator.muteImmediately()
            }
        }
    }

    private var comparisonProgressText: String? {
        switch beforeAfterMeasurement.state {
        case .idle:
            nil
        case let .settling(window):
            "\(window.rawValue): settling..."
        case let .capturing(window, collected, required):
            "\(window.rawValue): \(collected)/\(required) samples"
        case .failed:
            nil
        }
    }

    private var baselineMatchesCurrentTarget: Bool {
        guard let baseline = beforeAfterMeasurement.baseline else {
            return true
        }

        return abs(
            baseline.condition.targetFrequencyHz -
            toneGenerator.frequencyHz
        ) <= 0.5
    }

    private var baselineMatchesCurrentHeadPosition: Bool {
        guard
            beforeAfterMeasurement
                .baseline != nil
        else {
            return true
        }

        return baselineHeadPosition ==
            selectedHeadPosition
    }

    private var baselineMatchesCurrentRoute: Bool {
        guard
            beforeAfterMeasurement
                .baseline != nil
        else {
            return true
        }

        return
            baselineRouteSignature ==
                audioSession.routeSignature &&
            baselineRouteRevision ==
                audioSession.routeRevision
    }

    private func captureBaseline() {
        lastSavedComparisonKey = nil
        baselineHeadPosition =
            selectedHeadPosition
        baselineRouteSignature =
            audioSession.routeSignature
        baselineRouteRevision =
            audioSession.routeRevision

        if
            toneGenerator.state == .playing,
            !toneGenerator.isMuted
        {
            toneGenerator.muteImmediately()
        }

        let target = toneGenerator.frequencyHz
        let condition = MeasurementCondition(
            targetFrequencyHz: target,
            phaseDegrees: toneGenerator.phaseDegrees,
            outputPercent: toneGenerator.outputPercent,
            toneAudible: false
        )

        Task { @MainActor in
            await beforeAfterMeasurement.capture(
                window: .baseline,
                condition: condition
            ) {
                sequencedMeasurementForTarget(
                    target
                )
            }
        }
    }

    private func captureTreatment() {
        let target = toneGenerator.frequencyHz
        let condition = MeasurementCondition(
            targetFrequencyHz: target,
            phaseDegrees: toneGenerator.phaseDegrees,
            outputPercent: toneGenerator.outputPercent,
            toneAudible: true
        )

        Task { @MainActor in
            await beforeAfterMeasurement.capture(
                window: .treatment,
                condition: condition
            ) {
                sequencedMeasurementForTarget(
                    target
                )
            }
        }
    }

    private func sequencedMeasurementForTarget(
        _ targetFrequencyHz: Double
    ) -> SequencedTargetEnergyMeasurement? {
        let snapshot =
            microphoneCapture.snapshot

        guard
            let measurement =
                measurementForTarget(
                    targetFrequencyHz
                )
        else {
            return nil
        }

        return SequencedTargetEnergyMeasurement(
            sequence:
                snapshot.fftTransformCount,
            measurement: measurement
        )
    }

    private func measurementForTarget(
        _ targetFrequencyHz: Double
    ) -> TargetFrequencyEnergyMeasurement? {
        let snapshot = microphoneCapture.snapshot

        guard
            microphoneCapture.state ==
                .capturing,
            !snapshot.isClipping,
            snapshot.analysisDroppedBufferCount == 0,
            snapshot.musicInterference
                .level != .likely,
            ProcessingLatencyMath
                .analysisFitsBufferBudget(
                    analysisProcessingMilliseconds:
                        snapshot
                            .processingLatency
                            .latestAnalysisProcessingMilliseconds,
                    bufferDurationMilliseconds:
                        snapshot
                            .bufferDurationMilliseconds
                )
        else {
            return nil
        }

        return TargetFrequencyEnergyMeter.measure(
            spectrum: snapshot.smoothedSpectrum.balanced,
            noiseFloor: snapshot.noiseFloor.bins,
            targetFrequencyHz: targetFrequencyHz,
            frequencyResolutionHz: snapshot.fftResolutionHz
        )
    }

    @ViewBuilder
    private func comparisonWindowRow(
        title: String,
        summary: TargetEnergyWindowSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(
                    String(
                        format: "%.2f dBFS",
                        summary.averageBandEnergyDBFS
                    )
                )
                .font(.subheadline.monospacedDigit().weight(.semibold))
            }

            Text(
                String(
                    format: "%.0f Hz • phase %.0f° • output %.0f%% • %@",
                    summary.condition.targetFrequencyHz,
                    summary.condition.phaseDegrees,
                    summary.condition.outputPercent,
                    summary.condition.toneAudible
                        ? "tone audible"
                        : "tone muted/off"
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(
                String(
                    format: "%d samples • %.1f sec • σ %.2f dB",
                    summary.sampleCount,
                    summary.durationSeconds,
                    summary.standardDeviationDB
                )
            )
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func comparisonKey(
        _ comparison: BeforeAfterComparison
    ) -> String {
        String(
            format: "%.3f|%.3f|%.3f|%.3f|%.3f|%.3f",
            comparison.baseline.condition.targetFrequencyHz,
            comparison.baseline.averageBandEnergyDBFS,
            comparison.treatment.condition.phaseDegrees,
            comparison.treatment.condition.outputPercent,
            comparison.treatment.averageBandEnergyDBFS,
            comparison.measuredReductionDB
        )
    }

    private func comparisonResultText(
        _ comparison: BeforeAfterComparison
    ) -> String {
        if abs(comparison.measuredReductionDB) < 0.05 {
            return "No meaningful measured change • 0.00 dB"
        }

        if comparison.measuredReductionDB > 0 {
            return String(
                format: "Reduction %.2f dB",
                comparison.measuredReductionDB
            )
        }

        return String(
            format: "Increase %.2f dB",
            abs(comparison.measuredReductionDB)
        )
    }

    private var measurementWindowIsUsable: Bool {
        let snapshot =
            microphoneCapture.snapshot

        return
            microphoneCapture.state ==
                .capturing &&
            !snapshot.isClipping &&
            snapshot.analysisDroppedBufferCount == 0 &&
            snapshot.musicInterference
                .level != .likely &&
            ProcessingLatencyMath
                .analysisFitsBufferBudget(
                    analysisProcessingMilliseconds:
                        snapshot
                            .processingLatency
                            .latestAnalysisProcessingMilliseconds,
                    bufferDurationMilliseconds:
                        snapshot
                            .bufferDurationMilliseconds
                )
    }

    private var targetEnergyMeasurement: TargetFrequencyEnergyMeasurement? {
        let snapshot = microphoneCapture.snapshot

        return TargetFrequencyEnergyMeter.measure(
            spectrum: snapshot.smoothedSpectrum.balanced,
            noiseFloor: snapshot.noiseFloor.bins,
            targetFrequencyHz: toneGenerator.frequencyHz,
            frequencyResolutionHz: snapshot.fftResolutionHz
        )
    }

    private var bestPersistentTone: PersistentTone? {
        microphoneCapture.snapshot.persistentTones.tones
            .filter { $0.isPersistent }
            .max {
                if abs($0.confidence - $1.confidence) > 0.0001 {
                    return $0.confidence < $1.confidence
                }

                return $0.durationSeconds < $1.durationSeconds
            }
    }

    private var isExperimentReady: Bool {
        audioSession.state == .active &&
        microphoneCapture.analysisMode == .ancFocus &&
        !audioSession.outputs.isEmpty &&
        !audioSession.inputs.isEmpty
    }

    private var bothRunning: Bool {
        microphoneCapture.state == .capturing &&
        toneGenerator.state == .playing
    }

    private var audioConfigurationSignature:
        String
    {
        ExperimentEvidenceQuality
            .audioConfigurationID(
                routeSignature:
                    audioSession.routeSignature,
                sampleRate:
                    audioSession.sampleRate,
                ioBufferDuration:
                    audioSession.ioBufferDuration
            )
    }

    private var inputRouteSummary: String {
        routeSummary(audioSession.inputs)
    }

    private var outputRouteSummary: String {
        routeSummary(audioSession.outputs)
    }

    private func routeSummary(
        _ ports: [AudioSessionModel.Port]
    ) -> String {
        guard !ports.isEmpty else { return "None" }

        return ports
            .map { "\($0.name) • \($0.type)" }
            .joined(separator: ", ")
    }

    @ViewBuilder
    private func readinessRow(
        title: String,
        isReady: Bool,
        detail: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(
                systemName: isReady
                    ? "checkmark.circle.fill"
                    : "xmark.circle"
            )
            .foregroundStyle(
                isReady
                    ? Color.green
                    : Color.secondary
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func phaseButton(
        _ title: String,
        degrees: Double
    ) -> some View {
        Button(title) {
            toneGenerator.setPhaseDegrees(degrees)
        }
        .buttonStyle(.bordered)
    }
}

private extension View {
    func cancellationCard() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .fill(.thinMaterial)
            )
    }
}
