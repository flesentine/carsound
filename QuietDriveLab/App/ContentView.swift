import SwiftUI

struct ContentView: View {
    @Environment(MicrophonePermissionModel.self) private var microphonePermission
    @Environment(AudioSessionModel.self) private var audioSession

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    permissionCard

                    if microphonePermission.status == .granted {
                        audioSessionCard
                        routeCard
                    }

                    Text("Lab build 0.2 • No raw microphone audio is stored")
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
                    audioSession.configureAndActivate()
                }
                .buttonStyle(.borderedProminent)

                if audioSession.state == .active {
                    Button("Deactivate") {
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

    private var sampleRateText: String {
        guard audioSession.sampleRate > 0 else { return "—" }
        return String(format: "%.0f Hz", audioSession.sampleRate)
    }

    private var bufferText: String {
        guard audioSession.ioBufferDuration > 0 else { return "—" }
        return String(format: "%.2f ms", audioSession.ioBufferDuration * 1_000)
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
}
