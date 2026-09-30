import Foundation

enum BluetoothProfile: String, Equatable, Sendable {
    case none = "No Bluetooth"
    case a2dp = "A2DP"
    case hfp = "HFP"
    case le = "Bluetooth LE"
    case mixed = "Mixed Bluetooth"
}

enum BluetoothTopology: String, Equatable, Sendable {
    case none = "No Bluetooth path"
    case bluetoothOutputLocalInput = "Bluetooth output + local/non-Bluetooth input"
    case bluetoothDuplex = "Bluetooth input + output"
    case bluetoothInputOnly = "Bluetooth input + non-Bluetooth output"
    case mixed = "Mixed Bluetooth topology"
}

struct BluetoothProfileStatistics: Equatable, Sendable {
    let profile: BluetoothProfile
    let recordCount: Int
    let averageSampleRate: Double
    let averageIOBufferMilliseconds: Double
    let averageInputLatencyMilliseconds: Double
    let averageOutputLatencyMilliseconds: Double
    let averageCallbackJitterMilliseconds: Double
    let averageSpectrumCenterAgeMilliseconds: Double
}

struct BluetoothBehaviorSnapshot: Equatable, Sendable {
    let profile: BluetoothProfile
    let topology: BluetoothTopology
    let hasBluetoothInput: Bool
    let hasBluetoothOutput: Bool
    let routeRevision: UInt64
    let sampleRate: Double
    let ioBufferMilliseconds: Double
    let inputLatencyMilliseconds: Double
    let outputLatencyMilliseconds: Double
    let savedBluetoothTestCount: Int
    let distinctBluetoothRouteCount: Int
    let observedProfiles: [BluetoothProfile]
    let observedProfileSwitchCount: Int
    let currentProfileStatistics: BluetoothProfileStatistics?
    let nonBluetoothOutputLatencyAverageMilliseconds: Double?
    let outputLatencyDeltaVersusNonBluetoothMilliseconds: Double?
}

enum BluetoothBehaviorMath {
    static func profile(
        inputs: [AudioRoutePortRecord],
        outputs: [AudioRoutePortRecord]
    ) -> BluetoothProfile {
        let bluetoothTypes = Set(
            (inputs + outputs)
                .filter(\.isBluetooth)
                .map(\.type)
        )

        if bluetoothTypes.isEmpty {
            return .none
        }

        if bluetoothTypes.count > 1 {
            return .mixed
        }

        guard let type = bluetoothTypes.first else {
            return .none
        }

        switch type {
        case "Bluetooth A2DP":
            return .a2dp
        case "Bluetooth HFP":
            return .hfp
        case "Bluetooth LE":
            return .le
        default:
            return .mixed
        }
    }

    static func topology(
        inputs: [AudioRoutePortRecord],
        outputs: [AudioRoutePortRecord]
    ) -> BluetoothTopology {
        let hasBluetoothInput =
            inputs.contains(where: \.isBluetooth)
        let hasBluetoothOutput =
            outputs.contains(where: \.isBluetooth)

        switch (
            hasBluetoothInput,
            hasBluetoothOutput
        ) {
        case (false, false):
            return .none
        case (false, true):
            return .bluetoothOutputLocalInput
        case (true, true):
            let profile = profile(
                inputs: inputs,
                outputs: outputs
            )

            return profile == .mixed
                ? .mixed
                : .bluetoothDuplex
        case (true, false):
            return .bluetoothInputOnly
        }
    }

    static func statistics(
        for profile: BluetoothProfile,
        records: [AudioRouteTestRecord]
    ) -> BluetoothProfileStatistics? {
        let matches = records.filter {
            bluetoothProfile(for: $0) == profile
        }

        guard !matches.isEmpty else {
            return nil
        }

        return BluetoothProfileStatistics(
            profile: profile,
            recordCount: matches.count,
            averageSampleRate:
                average(matches.map(\.sampleRate)),
            averageIOBufferMilliseconds:
                average(
                    matches.map(
                        \.ioBufferMilliseconds
                    )
                ),
            averageInputLatencyMilliseconds:
                average(
                    matches.map(
                        \.inputLatencyMilliseconds
                    )
                ),
            averageOutputLatencyMilliseconds:
                average(
                    matches.map(
                        \.outputLatencyMilliseconds
                    )
                ),
            averageCallbackJitterMilliseconds:
                average(
                    matches.map(
                        \.callbackJitterMilliseconds
                    )
                ),
            averageSpectrumCenterAgeMilliseconds:
                average(
                    matches.map(
                        \.estimatedSpectrumCenterAgeMilliseconds
                    )
                )
        )
    }

    static func behavior(
        inputs: [AudioRoutePortRecord],
        outputs: [AudioRoutePortRecord],
        routeRevision: UInt64,
        sampleRate: Double,
        ioBufferDuration: TimeInterval,
        inputLatency: TimeInterval,
        outputLatency: TimeInterval,
        records: [AudioRouteTestRecord]
    ) -> BluetoothBehaviorSnapshot {
        let currentProfile = profile(
            inputs: inputs,
            outputs: outputs
        )
        let currentTopology = topology(
            inputs: inputs,
            outputs: outputs
        )

        let bluetoothRecords = records.filter {
            bluetoothProfile(for: $0) != .none
        }
        let distinctBluetoothRoutes = Set(
            bluetoothRecords.map(\.routeSignature)
        ).count

        let chronological = bluetoothRecords
            .sorted { $0.capturedAt < $1.capturedAt }
            .map(bluetoothProfile(for:))

        var profileSwitchCount = 0

        if chronological.count > 1 {
            for index in 1..<chronological.count {
                if
                    chronological[index] !=
                    chronological[index - 1]
                {
                    profileSwitchCount += 1
                }
            }
        }

        let observedProfiles = Array(
            Set(chronological)
        )
        .sorted { $0.rawValue < $1.rawValue }

        let nonBluetoothRecords = records.filter {
            bluetoothProfile(for: $0) == .none
        }
        let nonBluetoothOutputAverage: Double?

        if nonBluetoothRecords.isEmpty {
            nonBluetoothOutputAverage = nil
        } else {
            nonBluetoothOutputAverage = average(
                nonBluetoothRecords.map(
                    \.outputLatencyMilliseconds
                )
            )
        }

        let currentOutputMilliseconds =
            outputLatency * 1_000
        let outputDelta =
            nonBluetoothOutputAverage.map {
                currentOutputMilliseconds - $0
            }

        return BluetoothBehaviorSnapshot(
            profile: currentProfile,
            topology: currentTopology,
            hasBluetoothInput:
                inputs.contains(where: \.isBluetooth),
            hasBluetoothOutput:
                outputs.contains(where: \.isBluetooth),
            routeRevision: routeRevision,
            sampleRate: sampleRate,
            ioBufferMilliseconds:
                ioBufferDuration * 1_000,
            inputLatencyMilliseconds:
                inputLatency * 1_000,
            outputLatencyMilliseconds:
                currentOutputMilliseconds,
            savedBluetoothTestCount:
                bluetoothRecords.count,
            distinctBluetoothRouteCount:
                distinctBluetoothRoutes,
            observedProfiles: observedProfiles,
            observedProfileSwitchCount:
                profileSwitchCount,
            currentProfileStatistics:
                statistics(
                    for: currentProfile,
                    records: records
                ),
            nonBluetoothOutputLatencyAverageMilliseconds:
                nonBluetoothOutputAverage,
            outputLatencyDeltaVersusNonBluetoothMilliseconds:
                outputDelta
        )
    }

    static func bluetoothProfile(
        for record: AudioRouteTestRecord
    ) -> BluetoothProfile {
        switch record.family {
        case .bluetoothA2DP:
            return .a2dp
        case .bluetoothHFP:
            return .hfp
        case .bluetoothLE:
            return .le
        default:
            return profile(
                inputs: record.inputs,
                outputs: record.outputs
            )
        }
    }

    private static func average(
        _ values: [Double]
    ) -> Double {
        guard !values.isEmpty else {
            return 0
        }

        return values.reduce(0, +) /
            Double(values.count)
    }
}
