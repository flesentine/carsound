import Foundation
import Observation

enum AudioRouteFamily: String, Codable, CaseIterable, Equatable, Sendable {
    case builtIn = "Built-in"
    case wired = "Wired analog"
    case usb = "USB audio"
    case carAudio = "Car audio"
    case bluetoothA2DP = "Bluetooth A2DP"
    case bluetoothHFP = "Bluetooth HFP"
    case bluetoothLE = "Bluetooth LE"
    case airPlay = "AirPlay"
    case hdmi = "HDMI"
    case mixed = "Mixed route"
    case unknown = "Unknown"

    var isBluetooth: Bool {
        switch self {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            true
        default:
            false
        }
    }
}

struct AudioRoutePortRecord: Codable, Equatable, Sendable {
    let name: String
    let type: String
    let isBluetooth: Bool
}

struct AudioRouteTestRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let capturedAt: Date

    let family: AudioRouteFamily
    let routeSignature: String
    let routeRevision: UInt64

    let inputs: [AudioRoutePortRecord]
    let outputs: [AudioRoutePortRecord]

    let sampleRate: Double
    let ioBufferMilliseconds: Double
    let inputLatencyMilliseconds: Double
    let outputLatencyMilliseconds: Double

    let microphoneBufferMilliseconds: Double
    let callbackAverageMilliseconds: Double
    let callbackJitterMilliseconds: Double
    let analysisAverageMilliseconds: Double
    let analysisMaximumMilliseconds: Double
    let fftWindowMilliseconds: Double
    let snapshotAgeMilliseconds: Double
    let estimatedSpectrumCenterAgeMilliseconds: Double

    let microphoneBufferCount: UInt64
    let fftTransformCount: UInt64
}

enum AudioRouteTestingMath {
    static func classify(
        inputs: [AudioRoutePortRecord],
        outputs: [AudioRoutePortRecord]
    ) -> AudioRouteFamily {
        let all = inputs + outputs
        let types = Set(all.map(\.type))

        if types.contains("Bluetooth A2DP") {
            return .bluetoothA2DP
        }

        if types.contains("Bluetooth HFP") {
            return .bluetoothHFP
        }

        if types.contains("Bluetooth LE") {
            return .bluetoothLE
        }

        if types.contains("Car audio") {
            return .carAudio
        }

        if types.contains("USB audio") {
            return .usb
        }

        if types.contains("AirPlay") {
            return .airPlay
        }

        if types.contains("HDMI") {
            return .hdmi
        }

        let wiredTypes: Set<String> = [
            "Headphones",
            "Headset microphone",
            "Line in",
            "Line out"
        ]

        if !types.isDisjoint(with: wiredTypes) {
            return .wired
        }

        let builtInTypes: Set<String> = [
            "Built-in microphone",
            "Built-in speaker"
        ]

        if
            !types.isEmpty,
            types.isSubset(of: builtInTypes)
        {
            return .builtIn
        }

        if all.isEmpty {
            return .unknown
        }

        return .mixed
    }

    static func signature(
        inputs: [AudioRoutePortRecord],
        outputs: [AudioRoutePortRecord]
    ) -> String {
        let inputParts = inputs
            .map {
                "IN:\($0.type):\($0.name)"
            }
            .sorted()

        let outputParts = outputs
            .map {
                "OUT:\($0.type):\($0.name)"
            }
            .sorted()

        return (inputParts + outputParts)
            .joined(separator: "|")
    }

    static func records(
        from ports: [AudioSessionModel.Port]
    ) -> [AudioRoutePortRecord] {
        ports.map {
            AudioRoutePortRecord(
                name: $0.name,
                type: $0.type,
                isBluetooth: $0.isBluetooth
            )
        }
    }
}

@MainActor
@Observable
final class AudioRouteTestingModel {
    private(set) var records: [AudioRouteTestRecord] = []
    private(set) var lastError: String?

    @ObservationIgnored
    private let storageURL: URL?

    @ObservationIgnored
    private let fileManager: FileManager

    init(
        storageURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager

        if let storageURL {
            self.storageURL = storageURL
        } else {
            self.storageURL = Self.defaultStorageURL(
                fileManager: fileManager
            )
        }

        load()
    }

    var distinctRouteCount: Int {
        Set(records.map(\.routeSignature)).count
    }

    @discardableResult
    func capture(
        inputs: [AudioSessionModel.Port],
        outputs: [AudioSessionModel.Port],
        routeRevision: UInt64,
        sampleRate: Double,
        ioBufferDuration: TimeInterval,
        inputLatency: TimeInterval,
        outputLatency: TimeInterval,
        microphoneSnapshot: MicrophoneCaptureModel.Snapshot,
        capturedAt: Date = Date()
    ) -> AudioRouteTestRecord {
        let inputRecords =
            AudioRouteTestingMath.records(from: inputs)
        let outputRecords =
            AudioRouteTestingMath.records(from: outputs)
        let latency =
            microphoneSnapshot.processingLatency

        let record = AudioRouteTestRecord(
            id: UUID(),
            capturedAt: capturedAt,
            family: AudioRouteTestingMath.classify(
                inputs: inputRecords,
                outputs: outputRecords
            ),
            routeSignature:
                AudioRouteTestingMath.signature(
                    inputs: inputRecords,
                    outputs: outputRecords
                ),
            routeRevision: routeRevision,
            inputs: inputRecords,
            outputs: outputRecords,
            sampleRate: sampleRate,
            ioBufferMilliseconds:
                ioBufferDuration * 1_000,
            inputLatencyMilliseconds:
                inputLatency * 1_000,
            outputLatencyMilliseconds:
                outputLatency * 1_000,
            microphoneBufferMilliseconds:
                microphoneSnapshot
                    .bufferDurationMilliseconds,
            callbackAverageMilliseconds:
                latency
                    .averageCallbackIntervalMilliseconds,
            callbackJitterMilliseconds:
                latency.callbackJitterMilliseconds,
            analysisAverageMilliseconds:
                latency
                    .averageAnalysisProcessingMilliseconds,
            analysisMaximumMilliseconds:
                latency
                    .maximumAnalysisProcessingMilliseconds,
            fftWindowMilliseconds:
                latency.fftWindowMilliseconds,
            snapshotAgeMilliseconds:
                latency.snapshotAgeMilliseconds,
            estimatedSpectrumCenterAgeMilliseconds:
                latency
                    .estimatedSpectrumCenterAgeMilliseconds,
            microphoneBufferCount:
                microphoneSnapshot.bufferCount,
            fftTransformCount:
                microphoneSnapshot.fftTransformCount
        )

        return save(record)
    }

    @discardableResult
    func save(
        _ record: AudioRouteTestRecord
    ) -> AudioRouteTestRecord {
        records.insert(record, at: 0)
        persist()
        return record
    }

    func delete(id: UUID) {
        records.removeAll { $0.id == id }
        persist()
    }

    func clearAll() {
        records.removeAll()
        persist()
    }

    private func load() {
        guard let storageURL else { return }

        do {
            guard fileManager.fileExists(
                atPath: storageURL.path
            ) else {
                records = []
                lastError = nil
                return
            }

            let data = try Data(
                contentsOf: storageURL
            )
            let decoded = try JSONDecoder()
                .decode(
                    [AudioRouteTestRecord].self,
                    from: data
                )

            records = decoded.sorted {
                $0.capturedAt > $1.capturedAt
            }
            lastError = nil
        } catch {
            records = []
            lastError =
                "Could not load route tests: " +
                error.localizedDescription
        }
    }

    private func persist() {
        guard let storageURL else { return }

        do {
            let directoryURL =
                storageURL.deletingLastPathComponent()

            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys
            ]

            let data = try encoder.encode(records)

            try data.write(
                to: storageURL,
                options: [.atomic]
            )

            lastError = nil
        } catch {
            lastError =
                "Could not save route tests: " +
                error.localizedDescription
        }
    }

    private static func defaultStorageURL(
        fileManager: FileManager
    ) -> URL? {
        guard
            let applicationSupport =
                fileManager.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first
        else {
            return nil
        }

        return applicationSupport
            .appendingPathComponent(
                "QuietDriveLab",
                isDirectory: true
            )
            .appendingPathComponent(
                "route-tests.json",
                isDirectory: false
            )
    }
}
