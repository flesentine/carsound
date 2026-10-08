import Foundation
import Observation

struct CalibrationSample: Equatable, Sendable {
    let fftTransformCount: UInt64
    let motionSampleCount: UInt64

    let microphoneRMSDBFS: Double
    let lowFrequencyFloorDBFS: Double
    let widebandFloorDBFS: Double
    let targetBandEnergyDBFS: Double?

    let callbackJitterMilliseconds: Double
    let spectrumCenterAgeMilliseconds: Double

    let accelerationXG: Double?
    let accelerationYG: Double?
    let accelerationZG: Double?
    let dynamicVibrationRMSG: Double
    let accelerometerObservedRateHz: Double
    let accelerometerIntervalJitterMilliseconds: Double

    let musicInterferenceScore: Double
}

struct CalibrationProfile: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let capturedAt: Date

    let routeSignature: String
    let routeFamily: AudioRouteFamily
    let routeRevision: UInt64
    let inputRoute: String
    let outputRoute: String

    let sampleRate: Double
    let ioBufferMilliseconds: Double
    let inputLatencyMilliseconds: Double
    let outputLatencyMilliseconds: Double

    let sampleCount: Int
    let durationSeconds: Double

    let microphoneRMSDBFS: Double
    let microphoneRMSStandardDeviationDB: Double
    let lowFrequencyFloorDBFS: Double
    let widebandFloorDBFS: Double

    let targetFrequencyHz: Double?
    let targetBandEnergyDBFS: Double?
    let targetBandStandardDeviationDB: Double?

    let accelerationBiasXG: Double?
    let accelerationBiasYG: Double?
    let accelerationBiasZG: Double?
    let dynamicVibrationRMSG: Double
    let accelerometerObservedRateHz: Double
    let accelerometerIntervalJitterMilliseconds: Double

    let callbackJitterMilliseconds: Double
    let spectrumCenterAgeMilliseconds: Double
    let maximumMusicInterferenceScore: Double

    let externalReferenceSPLDB: Double?
    let approximateSPLOffsetDB: Double?

    var hasExternalSPLReference: Bool {
        externalReferenceSPLDB != nil &&
        approximateSPLOffsetDB != nil
    }
}

enum CalibrationMath {
    static let minimumExternalReferenceSPLDB = 20.0
    static let maximumExternalReferenceSPLDB = 140.0

    static func isValidExternalReferenceSPLDB(
        _ value: Double
    ) -> Bool {
        value.isFinite &&
        value >= minimumExternalReferenceSPLDB &&
        value <= maximumExternalReferenceSPLDB
    }

    static func averageDBFromPower(
        _ levelsDB: [Double]
    ) -> Double? {
        guard !levelsDB.isEmpty else {
            return nil
        }

        let averagePower =
            levelsDB
                .map {
                    pow(
                        10.0,
                        $0 / 10.0
                    )
                }
                .reduce(0, +) /
            Double(levelsDB.count)

        guard averagePower > 0 else {
            return nil
        }

        return 10.0 *
            log10(averagePower)
    }

    static func standardDeviation(
        _ values: [Double]
    ) -> Double {
        guard values.count > 1 else {
            return 0
        }

        let mean =
            values.reduce(0, +) /
            Double(values.count)

        let variance =
            values.reduce(0.0) {
                partial,
                value in

                let delta =
                    value - mean
                return
                    partial +
                    delta * delta
            } /
            Double(values.count - 1)

        return sqrt(
            max(
                0,
                variance
            )
        )
    }

    static func average(
        _ values: [Double]
    ) -> Double {
        guard !values.isEmpty else {
            return 0
        }

        return values.reduce(0, +) /
            Double(values.count)
    }

    static func averageOptional(
        _ values: [Double?]
    ) -> Double? {
        let present =
            values.compactMap {
                $0
            }

        guard !present.isEmpty else {
            return nil
        }

        return average(present)
    }

    static func externalSPLOffsetDB(
        referenceSPLDB: Double?,
        measuredRMSDBFS: Double
    ) -> Double? {
        guard
            let referenceSPLDB,
            isValidExternalReferenceSPLDB(
                referenceSPLDB
            )
        else {
            return nil
        }

        return
            referenceSPLDB -
            measuredRMSDBFS
    }

    static func approximateSPLDB(
        rmsDBFS: Double,
        profile: CalibrationProfile,
        currentRouteSignature: String
    ) -> Double? {
        guard
            profile.routeSignature ==
                currentRouteSignature,
            let offset =
                profile
                    .approximateSPLOffsetDB
        else {
            return nil
        }

        return rmsDBFS + offset
    }

    static func routeMatches(
        profile: CalibrationProfile,
        routeSignature: String,
        sampleRate: Double
    ) -> Bool {
        profile.routeSignature ==
            routeSignature &&
        abs(
            profile.sampleRate -
            sampleRate
        ) <= 1.0
    }
}

@MainActor
@Observable
final class CalibrationModel {
    enum State: Equatable {
        case idle
        case capturing(
            collected: Int,
            required: Int
        )
        case completed
        case failed(String)

        var isRunning: Bool {
            if case .capturing = self {
                return true
            }

            return false
        }
    }

    static let requiredSamples = 50
    static let sampleIntervalSeconds = 0.10
    static let maximumAttempts = 100

    private(set) var state: State = .idle
    private(set) var profiles: [CalibrationProfile] = []
    private(set) var lastCapturedProfile: CalibrationProfile?
    private(set) var lastError: String?

    @ObservationIgnored
    private let storageURL: URL?

    @ObservationIgnored
    private let fileManager: FileManager

    @ObservationIgnored
    private var generation: UInt64 = 0

    init(
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.storageURL =
            Self.defaultStorageURL(
                fileManager: fileManager
            )

        load()
    }

    init(
        storageURL: URL?,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.storageURL = storageURL

        load()
    }

    func resetCaptureState() {
        generation += 1
        state = .idle
        lastCapturedProfile = nil
    }

    func cancel() {
        generation += 1

        if state.isRunning {
            state = .idle
        }
    }

    func latestMatchingProfile(
        routeSignature: String,
        sampleRate: Double
    ) -> CalibrationProfile? {
        profiles.first {
            CalibrationMath.routeMatches(
                profile: $0,
                routeSignature:
                    routeSignature,
                sampleRate:
                    sampleRate
            )
        }
    }

    @discardableResult
    func save(
        _ profile: CalibrationProfile
    ) -> CalibrationProfile {
        profiles.removeAll {
            $0.id == profile.id
        }
        profiles.insert(
            profile,
            at: 0
        )
        persist()
        return profile
    }

    func delete(
        id: UUID
    ) {
        profiles.removeAll {
            $0.id == id
        }
        persist()
    }

    func clearAll() {
        profiles.removeAll()
        lastCapturedProfile = nil
        persist()
    }

    func run(
        routeSignature: String,
        routeFamily: AudioRouteFamily,
        routeRevision: UInt64,
        inputRoute: String,
        outputRoute: String,
        sampleRate: Double,
        ioBufferDuration: TimeInterval,
        inputLatency: TimeInterval,
        outputLatency: TimeInterval,
        targetFrequencyHz: Double?,
        externalReferenceSPLDB: Double?,
        sampleProvider:
            @escaping @MainActor
            () -> CalibrationSample?,
        safetyCheck:
            @escaping @MainActor
            () -> String?
    ) async {
        guard !state.isRunning else {
            return
        }

        if
            let externalReferenceSPLDB,
            !CalibrationMath
                .isValidExternalReferenceSPLDB(
                    externalReferenceSPLDB
                )
        {
            state = .failed(
                "External SPL reference must be between 20 and 140 dB."
            )
            return
        }

        generation += 1
        let currentGeneration =
            generation

        state = .capturing(
            collected: 0,
            required:
                Self.requiredSamples
        )
        lastCapturedProfile = nil

        var samples:
            [CalibrationSample] = []
        samples.reserveCapacity(
            Self.requiredSamples
        )

        var attempts = 0
        var lastFFTTransformCount: UInt64?
        var lastMotionSampleCount: UInt64?

        while
            samples.count <
                Self.requiredSamples,
            attempts <
                Self.maximumAttempts,
            currentGeneration ==
                generation,
            !Task.isCancelled
        {
            attempts += 1

            if let reason = safetyCheck() {
                state = .failed(reason)
                generation += 1
                return
            }

            if let sample =
                sampleProvider()
            {
                let audioFresh =
                    lastFFTTransformCount == nil ||
                    sample
                        .fftTransformCount >
                    (
                        lastFFTTransformCount ??
                        0
                    )
                let motionFresh =
                    lastMotionSampleCount == nil ||
                    sample.motionSampleCount >
                    (
                        lastMotionSampleCount ??
                        0
                    )

                if audioFresh &&
                    motionFresh
                {
                    lastFFTTransformCount =
                        sample
                            .fftTransformCount
                    lastMotionSampleCount =
                        sample
                            .motionSampleCount

                    samples.append(sample)

                    state = .capturing(
                        collected:
                            samples.count,
                        required:
                            Self.requiredSamples
                    )
                }
            }

            try? await Task.sleep(
                nanoseconds: UInt64(
                    Self.sampleIntervalSeconds *
                    1_000_000_000
                )
            )
        }

        guard
            currentGeneration ==
                generation,
            !Task.isCancelled
        else {
            return
        }

        guard
            samples.count ==
                Self.requiredSamples
        else {
            state = .failed(
                "Not enough fresh paired microphone and accelerometer calibration samples were available."
            )
            return
        }

        let rmsLevels =
            samples.map {
                $0.microphoneRMSDBFS
            }
        let lowFloors =
            samples.map {
                $0.lowFrequencyFloorDBFS
            }
        let wideFloors =
            samples.map {
                $0.widebandFloorDBFS
            }
        let targetLevels =
            samples.compactMap {
                $0.targetBandEnergyDBFS
            }

        guard
            let averageRMS =
                CalibrationMath
                    .averageDBFromPower(
                        rmsLevels
                    ),
            let averageLowFloor =
                CalibrationMath
                    .averageDBFromPower(
                        lowFloors
                    ),
            let averageWideFloor =
                CalibrationMath
                    .averageDBFromPower(
                        wideFloors
                    )
        else {
            state = .failed(
                "Calibration statistics could not be calculated."
            )
            return
        }

        let averageTarget:
            Double?

        if targetLevels.isEmpty {
            averageTarget = nil
        } else {
            averageTarget =
                CalibrationMath
                    .averageDBFromPower(
                        targetLevels
                    )
        }

        let profile =
            CalibrationProfile(
                id: UUID(),
                capturedAt: Date(),
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
                    sampleRate,
                ioBufferMilliseconds:
                    ioBufferDuration *
                    1_000,
                inputLatencyMilliseconds:
                    inputLatency *
                    1_000,
                outputLatencyMilliseconds:
                    outputLatency *
                    1_000,
                sampleCount:
                    samples.count,
                durationSeconds:
                    Double(
                        max(
                            0,
                            samples.count - 1
                        )
                    ) *
                    Self.sampleIntervalSeconds,
                microphoneRMSDBFS:
                    averageRMS,
                microphoneRMSStandardDeviationDB:
                    CalibrationMath
                        .standardDeviation(
                            rmsLevels
                        ),
                lowFrequencyFloorDBFS:
                    averageLowFloor,
                widebandFloorDBFS:
                    averageWideFloor,
                targetFrequencyHz:
                    averageTarget == nil
                    ? nil
                    : targetFrequencyHz,
                targetBandEnergyDBFS:
                    averageTarget,
                targetBandStandardDeviationDB:
                    targetLevels.isEmpty
                    ? nil
                    : CalibrationMath
                        .standardDeviation(
                            targetLevels
                        ),
                accelerationBiasXG:
                    CalibrationMath
                        .averageOptional(
                            samples.map {
                                $0.accelerationXG
                            }
                        ),
                accelerationBiasYG:
                    CalibrationMath
                        .averageOptional(
                            samples.map {
                                $0.accelerationYG
                            }
                        ),
                accelerationBiasZG:
                    CalibrationMath
                        .averageOptional(
                            samples.map {
                                $0.accelerationZG
                            }
                        ),
                dynamicVibrationRMSG:
                    CalibrationMath
                        .average(
                            samples.map {
                                $0.dynamicVibrationRMSG
                            }
                        ),
                accelerometerObservedRateHz:
                    CalibrationMath
                        .average(
                            samples.map {
                                $0.accelerometerObservedRateHz
                            }
                        ),
                accelerometerIntervalJitterMilliseconds:
                    CalibrationMath
                        .average(
                            samples.map {
                                $0.accelerometerIntervalJitterMilliseconds
                            }
                        ),
                callbackJitterMilliseconds:
                    CalibrationMath
                        .average(
                            samples.map {
                                $0.callbackJitterMilliseconds
                            }
                        ),
                spectrumCenterAgeMilliseconds:
                    CalibrationMath
                        .average(
                            samples.map {
                                $0.spectrumCenterAgeMilliseconds
                            }
                        ),
                maximumMusicInterferenceScore:
                    samples
                        .map {
                            $0.musicInterferenceScore
                        }
                        .max() ??
                    0,
                externalReferenceSPLDB:
                    externalReferenceSPLDB,
                approximateSPLOffsetDB:
                    CalibrationMath
                        .externalSPLOffsetDB(
                            referenceSPLDB:
                                externalReferenceSPLDB,
                            measuredRMSDBFS:
                                averageRMS
                        )
            )

        save(profile)
        lastCapturedProfile =
            profile

        state = .completed
    }

    private func load() {
        guard let storageURL else {
            return
        }

        do {
            guard
                fileManager.fileExists(
                    atPath:
                        storageURL.path
                )
            else {
                profiles = []
                lastError = nil
                return
            }

            let data = try Data(
                contentsOf:
                    storageURL
            )
            profiles = try JSONDecoder()
                .decode(
                    [CalibrationProfile].self,
                    from: data
                )
                .sorted {
                    $0.capturedAt >
                    $1.capturedAt
                }
            lastError = nil
        } catch {
            profiles = []
            lastError =
                "Could not load calibrations: " +
                error.localizedDescription
        }
    }

    private func persist() {
        guard let storageURL else {
            return
        }

        do {
            let directory =
                storageURL
                    .deletingLastPathComponent()

            try fileManager
                .createDirectory(
                    at: directory,
                    withIntermediateDirectories:
                        true
                )

            let encoder =
                JSONEncoder()
            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys
            ]

            try encoder
                .encode(profiles)
                .write(
                    to: storageURL,
                    options: [.atomic]
                )

            lastError = nil
        } catch {
            lastError =
                "Could not save calibrations: " +
                error.localizedDescription
        }
    }

    private static func defaultStorageURL(
        fileManager: FileManager
    ) -> URL? {
        guard
            let applicationSupport =
                fileManager.urls(
                    for:
                        .applicationSupportDirectory,
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
                "calibrations.json",
                isDirectory: false
            )
    }
}
