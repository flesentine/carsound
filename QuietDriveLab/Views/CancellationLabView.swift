import SwiftUI

struct CancellationLabView: View {
    @Environment(AudioSessionModel.self) private var audioSession
    @Environment(MicrophoneCaptureModel.self) private var microphoneCapture
    @Environment(ToneGeneratorModel.self) private var toneGenerator
    @Environment(BeforeAfterMeasurementModel.self) private var beforeAfterMeasurement

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                readinessCard
                targetCard
                targetEnergyCard
                beforeAfterCard
                controlsCard
                liveStateCard
                safetyCard
            }
            .padding(20)
        }
        .navigationTitle("Cancellation Lab")
        .navigationBarTitleDisplayMode(.inline)
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
        .disabled(beforeAfterMeasurement.state.isBusy)
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
                    targetEnergyMeasurement == nil ||
                    beforeAfterMeasurement.state.isBusy
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
                    targetEnergyMeasurement == nil ||
                    !baselineMatchesCurrentTarget ||
                    beforeAfterMeasurement.state.isBusy
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
            }

            if
                beforeAfterMeasurement.baseline != nil ||
                beforeAfterMeasurement.treatment != nil
            {
                Button("Reset Comparison") {
                    beforeAfterMeasurement.reset()
                }
                .buttonStyle(.bordered)
                .disabled(beforeAfterMeasurement.state.isBusy)
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
                    } else {
                        microphoneCapture.startCapture()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(audioSession.state != .active)

                Button(
                    toneGenerator.state == .playing
                        ? "Stop Tone"
                        : "Start Tone"
                ) {
                    if toneGenerator.state == .playing {
                        Task {
                            await toneGenerator.stop()
                        }
                    } else {
                        toneGenerator.start()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(audioSession.state != .active)
            }

            Button("Start Capture + Tone") {
                if microphoneCapture.state != .capturing {
                    microphoneCapture.startCapture()
                }

                if toneGenerator.state != .playing {
                    toneGenerator.start()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isExperimentReady || bothRunning)

            Button("Stop All") {
                toneGenerator.stopImmediately()
                microphoneCapture.stopCapture()
            }
            .buttonStyle(.bordered)

            Text("Use Before / After for an averaged A/B result. Experiment recording and saved run history begin in #18.")
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
                } else {
                    toneGenerator.muteImmediately()
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

    private func captureBaseline() {
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
                measurementForTarget(target)
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
                measurementForTarget(target)
            }
        }
    }

    private func measurementForTarget(
        _ targetFrequencyHz: Double
    ) -> TargetFrequencyEnergyMeasurement? {
        let snapshot = microphoneCapture.snapshot

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
