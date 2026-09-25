import SwiftUI

struct ContentView: View {
    @State private var spectrumDisplayRange: SpectrumDisplayRange = .lowFrequency
    @State private var spectrumRenderMode: SpectrumRenderMode = .smoothed
    @State private var smoothingPreset: SpectrumSmoothingPreset = .balanced

    @Environment(MicrophonePermissionModel.self) private var microphonePermission
    @Environment(AudioSessionModel.self) private var audioSession
    @Environment(MicrophoneCaptureModel.self) private var microphoneCapture

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    permissionCard

                    if microphonePermission.status == .granted {
                        audioSessionCard
                        routeCard
                        captureCard
                        diagnosticsCard
                        fftCard
                        spectrumCard
                        noiseFloorCard
                    }

                    Text("Lab build 0.8 • PCM buffers are analyzed in memory and never written to disk")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
                .padding(24)
            }
            .navigationTitle("Lab")
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            Text("QuietDrive Lab")
                .font(.largeTitle.bold())

            Text("Low-frequency cabin-noise research")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Microphone", systemImage: microphonePermission.status.symbolName)
                .font(.headline)

            Text(microphonePermission.status.message)
                .foregroundStyle(.secondary)

            switch microphonePermission.status {
            case .undetermined:
                Button("Allow Microphone Access") {
                    Task { await microphonePermission.request() }
                }
                .buttonStyle(.borderedProminent)

            case .denied:
                Text("Enable microphone access in Settings → Privacy & Security → Microphone to continue.")
                    .font(.footnote)

            case .granted:
                Label("Ready for audio-session setup", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .cardStyle()
    }

    private var audioSessionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Audio Session", systemImage: "waveform.badge.mic")
                    .font(.headline)
                Spacer()
                Text(audioSession.state.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(audioSession.state == .active ? .green : .secondary)
            }

            Text("Play + record • Measurement mode • Bluetooth A2DP enabled")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if case let .failed(message) = audioSession.state {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Button(audioSession.state == .active ? "Reconfigure" : "Activate Audio Session") {
                    microphoneCapture.stopCapture()
                    audioSession.configureAndActivate()
                }
                .buttonStyle(.borderedProminent)

                if audioSession.state == .active {
                    Button("Deactivate") {
                        microphoneCapture.stopCapture()
                        audioSession.deactivate()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Divider()

            LabeledContent("Sample rate", value: sampleRateText)
            LabeledContent("I/O buffer", value: bufferText)
            LabeledContent("Last route change", value: audioSession.lastRouteChangeReason)
        }
        .cardStyle()
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Current Audio Route", systemImage: "arrow.triangle.branch")
                .font(.headline)

            routeSection(title: "Input", ports: audioSession.inputs)
            Divider()
            routeSection(title: "Output", ports: audioSession.outputs)

            Button("Refresh Route") {
                audioSession.refreshRoute()
            }
            .buttonStyle(.bordered)
        }
        .cardStyle()
    }

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Microphone Capture", systemImage: "mic.and.signal.meter")
                    .font(.headline)

                Spacer()

                Text(microphoneCapture.state.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(microphoneCapture.state == .capturing ? .green : .secondary)
            }

            Text("Streams live PCM buffers into memory. Audio samples are discarded immediately after each buffer is observed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if case let .failed(message) = microphoneCapture.state {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                if microphoneCapture.state == .capturing {
                    Button("Stop Capture") {
                        microphoneCapture.stopCapture()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Start Capture") {
                        microphoneCapture.startCapture()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(audioSession.state != .active)
                }

                Button("Reset Counters") {
                    microphoneCapture.resetCounters()
                }
                .buttonStyle(.bordered)
                .disabled(microphoneCapture.state == .capturing)
            }

            if audioSession.state != .active {
                Text("Activate the audio session before starting microphone capture.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            LabeledContent("Buffers received", value: "\(microphoneCapture.snapshot.bufferCount)")
            LabeledContent("Frames received", value: "\(microphoneCapture.snapshot.frameCount)")
            LabeledContent("Last buffer", value: "\(microphoneCapture.snapshot.lastBufferFrames) frames")
            LabeledContent("Capture rate", value: captureRateText)
            LabeledContent("Channels", value: captureChannelsText)
            LabeledContent("PCM format", value: microphoneCapture.snapshot.formatDescription)
        }
        .cardStyle()
    }

    private var diagnosticsCard: some View {
        let snapshot = microphoneCapture.snapshot

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Raw Audio Diagnostics", systemImage: "waveform.path.ecg")
                    .font(.headline)

                Spacer()

                if microphoneCapture.state == .capturing {
                    Label(
                        snapshot.isClipping ? "Clipping" : "Live",
                        systemImage: snapshot.isClipping ? "exclamationmark.triangle.fill" : "dot.radiowaves.left.and.right"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(snapshot.isClipping ? .red : .green)
                } else {
                    Text("Idle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text("Levels are digital dBFS measurements, not calibrated cabin SPL.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            signalMeter(
                title: "RMS level",
                dbFS: snapshot.rmsDBFS,
                position: AudioLevelAnalyzer.meterPosition(forDBFS: snapshot.rmsDBFS)
            )

            signalMeter(
                title: "Peak level",
                dbFS: snapshot.peakDBFS,
                position: AudioLevelAnalyzer.meterPosition(forDBFS: snapshot.peakDBFS)
            )

            Divider()

            LabeledContent("RMS", value: dbFSText(snapshot.rmsDBFS))
            LabeledContent("Peak", value: dbFSText(snapshot.peakDBFS))
            LabeledContent("Peak hold", value: dbFSText(snapshot.peakHoldDBFS))
            LabeledContent("Peak headroom", value: headroomText(snapshot.peakDBFS))
            LabeledContent(
                "Last buffer clipping",
                value: snapshot.isClipping ? "\(snapshot.lastBufferClippedSampleCount) samples" : "None"
            )
            LabeledContent("Clipped samples total", value: "\(snapshot.totalClippedSampleCount)")
            LabeledContent(
                "Buffer size",
                value: snapshot.lastBufferFrames > 0 ? "\(snapshot.lastBufferFrames) frames" : "—"
            )
            LabeledContent(
                "Buffer duration",
                value: snapshot.bufferDurationMilliseconds > 0
                    ? String(format: "%.2f ms", snapshot.bufferDurationMilliseconds)
                    : "—"
            )
            LabeledContent("Capture rate", value: captureRateText)
            LabeledContent("Channels", value: captureChannelsText)
            LabeledContent("PCM format", value: snapshot.formatDescription)
        }
        .cardStyle()
    }

    private func signalMeter(title: String, dbFS: Double, position: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(dbFSText(dbFS))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: position, total: 1)
                .progressViewStyle(.linear)

            HStack {
                Text("-80")
                Spacer()
                Text("-40")
                Spacer()
                Text("0 dBFS")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private var fftCard: some View {
        let snapshot = microphoneCapture.snapshot
        let nyquist = snapshot.sampleRate > 0 ? snapshot.sampleRate / 2 : 0

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("FFT Processing", systemImage: "waveform.path")
                    .font(.headline)
                Spacer()
                Text(snapshot.spectrumBins.isEmpty ? "Warming up" : "Ready")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(snapshot.spectrumBins.isEmpty ? Color.secondary : Color.green)
            }

            Text("Rolling 4,096-sample Hann-windowed FFT. The live spectrum is computed now; graphing comes in #6.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            LabeledContent("FFT size", value: snapshot.fftSampleCount > 0 ? "\(snapshot.fftSampleCount) samples" : "—")
            LabeledContent("Window", value: snapshot.fftWindowName)
            LabeledContent("Frequency resolution", value: snapshot.fftResolutionHz > 0 ? String(format: "%.2f Hz/bin", snapshot.fftResolutionHz) : "—")
            LabeledContent("Spectrum bins", value: snapshot.spectrumBins.isEmpty ? "—" : "\(snapshot.spectrumBins.count)")
            LabeledContent("Nyquist", value: nyquist > 0 ? String(format: "%.0f Hz", nyquist) : "—")
            LabeledContent("Transforms completed", value: "\(snapshot.fftTransformCount)")
        }
        .cardStyle()
    }

    private var spectrumCard: some View {
        let snapshot = microphoneCapture.snapshot
        let displayedBins: [SpectrumBin]
        let seriesLabel: String

        switch spectrumRenderMode {
        case .raw:
            displayedBins = snapshot.spectrumBins
            seriesLabel = "Raw FFT"
        case .smoothed:
            displayedBins = snapshot.smoothedSpectrum.bins(for: smoothingPreset)
            seriesLabel = "\(smoothingPreset.rawValue) smoothing"
        }

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Live Spectrum", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer()
                Text(microphoneCapture.state == .capturing ? "Live" : "Idle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        microphoneCapture.state == .capturing
                            ? Color.green
                            : Color.secondary
                    )
            }

            Text("Compare the untouched FFT with temporal smoothing calculated in linear power.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Spectrum range", selection: $spectrumDisplayRange) {
                ForEach(SpectrumDisplayRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            Picker("Spectrum processing", selection: $spectrumRenderMode) {
                ForEach(SpectrumRenderMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if spectrumRenderMode == .smoothed {
                Picker("Smoothing", selection: $smoothingPreset) {
                    ForEach(SpectrumSmoothingPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                Text(smoothingPreset.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SpectrumGraphView(
                bins: displayedBins,
                displayRange: spectrumDisplayRange,
                seriesLabel: seriesLabel
            )

            LabeledContent(
                "Displayed range",
                value: spectrumDisplayRange.rawValue
            )
            LabeledContent(
                "Processing",
                value: spectrumRenderMode == .raw
                    ? "Raw"
                    : smoothingPreset.rawValue
            )
            LabeledContent(
                "Bins in range",
                value: "\(SpectrumGraphScale.bins(from: displayedBins, in: spectrumDisplayRange).count)"
            )
        }
        .cardStyle()
    }

    private var noiseFloorCard: some View {
        let floor = microphoneCapture.snapshot.noiseFloor

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Noise Floor", systemImage: "waveform.badge.minus")
                    .font(.headline)

                Spacer()

                Text(floor.updateCount > 0 ? "Tracking" : "Warming up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        floor.updateCount > 0
                            ? Color.green
                            : Color.secondary
                    )
            }

            Text("Adaptive digital background baseline. This is relative dBFS, not calibrated cabin SPL.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            LabeledContent(
                "20–200 Hz floor",
                value: floor.updateCount > 0
                    ? dbFSText(floor.lowFrequencyFloorDBFS)
                    : "—"
            )

            LabeledContent(
                "20–2,000 Hz floor",
                value: floor.updateCount > 0
                    ? dbFSText(floor.widebandFloorDBFS)
                    : "—"
            )

            LabeledContent(
                "Low-frequency above floor",
                value: floor.updateCount > 0
                    ? String(format: "+%.1f dB", floor.lowFrequencyExcessDB)
                    : "—"
            )

            LabeledContent(
                "Wideband above floor",
                value: floor.updateCount > 0
                    ? String(format: "+%.1f dB", floor.widebandExcessDB)
                    : "—"
            )

            LabeledContent(
                "Tracked floor bins",
                value: floor.bins.isEmpty ? "—" : "\(floor.bins.count)"
            )

            LabeledContent(
                "Estimator updates",
                value: "\(floor.updateCount)"
            )
        }
        .cardStyle()
    }

    @ViewBuilder
    private func routeSection(title: String, ports: [AudioSessionModel.Port]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            if ports.isEmpty {
                Text("No active \(title.lowercased()) route")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(ports) { port in
                    HStack(alignment: .top) {
                        Image(systemName: port.isBluetooth ? "wave.3.right" : "speaker.wave.2")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(port.name)
                                .font(.subheadline.weight(.semibold))
                            Text(port.type)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func dbFSText(_ value: Double) -> String {
        guard value > AudioLevelAnalyzer.silenceFloorDBFS else { return "≤ -120.0 dBFS" }
        return String(format: "%.1f dBFS", value)
    }

    private func headroomText(_ peakDBFS: Double) -> String {
        guard peakDBFS > AudioLevelAnalyzer.silenceFloorDBFS else { return "—" }
        return String(format: "%.1f dB", max(0, -peakDBFS))
    }

    private var sampleRateText: String {
        guard audioSession.sampleRate > 0 else { return "—" }
        return String(format: "%.0f Hz", audioSession.sampleRate)
    }

    private var bufferText: String {
        guard audioSession.ioBufferDuration > 0 else { return "—" }
        return String(format: "%.2f ms", audioSession.ioBufferDuration * 1_000)
    }

    private var captureRateText: String {
        guard microphoneCapture.snapshot.sampleRate > 0 else { return "—" }
        return String(format: "%.0f Hz", microphoneCapture.snapshot.sampleRate)
    }

    private var captureChannelsText: String {
        guard microphoneCapture.snapshot.channelCount > 0 else { return "—" }
        return "\(microphoneCapture.snapshot.channelCount)"
    }
}

private extension View {
    func cardStyle() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    ContentView()
        .environment(MicrophonePermissionModel())
        .environment(AudioSessionModel())
        .environment(MicrophoneCaptureModel())
}
