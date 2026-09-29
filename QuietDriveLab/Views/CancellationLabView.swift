import SwiftUI

struct CancellationLabView: View {
    @Environment(AudioSessionModel.self) private var audioSession
    @Environment(MicrophoneCaptureModel.self) private var microphoneCapture
    @Environment(ToneGeneratorModel.self) private var toneGenerator

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                readinessCard
                targetCard
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

            Text("This screen only gives you manual control. It does not yet decide whether a phase setting improved or worsened the target tone; measurement begins in #16.")
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
