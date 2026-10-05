import Foundation
import Observation

enum SoundVibrationCorrelationLevel: String, Equatable, Sendable {
    case insufficientData = "Insufficient data"
    case noConsistentMatch = "No consistent shared frequency"
    case frequencyAligned = "Frequency aligned"
    case coMoving = "Frequency aligned + co-moving"
}

struct SoundVibrationCorrelationInput: Equatable, Sendable {
    let audioFFTTransformCount: UInt64
    let motionSampleCount: UInt64
    let audioResolutionHz: Double
    let vibrationResolutionHz: Double
    let vibrationMaximumFrequencyHz: Double
    let dominantSoundFrequencies: [DominantFrequency]
    let persistentTones: [PersistentTone]
    let vibrationPeaks: [VibrationPeak]
}

struct SoundVibrationMatch: Equatable, Sendable, Identifiable {
    let soundFrequencyHz: Double
    let vibrationFrequencyHz: Double
    let frequencyDeltaHz: Double
    let toleranceHz: Double
    let frequencyAgreement: Double
    let soundMagnitudeDBFS: Double
    let soundAmplitudeLinear: Double
    let vibrationAmplitudeG: Double
    let soundIsPersistent: Bool
    let soundPersistenceConfidence: Double

    var id: String {
        String(
            format:
                "%.3f-%.3f",
            soundFrequencyHz,
            vibrationFrequencyHz
        )
    }

    var centerFrequencyHz: Double {
        (
            soundFrequencyHz +
            vibrationFrequencyHz
        ) / 2.0
    }
}

struct SoundVibrationObservation: Equatable, Sendable {
    let capturedAtSeconds: Double
    let matches: [SoundVibrationMatch]

    var primaryMatch: SoundVibrationMatch? {
        matches.max {
            SoundVibrationCorrelationMath
                .matchPriority($0) <
            SoundVibrationCorrelationMath
                .matchPriority($1)
        }
    }
}

struct SoundVibrationCorrelationSummary: Equatable, Sendable {
    let opportunityCount: Int
    let matchedObservationCount: Int
    let primaryTrackObservationCount: Int
    let primarySharedFrequencyHz: Double?
    let matchPresenceRatio: Double
    let averageFrequencyDeltaHz: Double?
    let averageFrequencyAgreement: Double?
    let amplitudeCorrelation: Double?
    let persistentSoundRatio: Double
    let averageSoundPersistenceConfidence: Double
    let level: SoundVibrationCorrelationLevel

    static let empty = SoundVibrationCorrelationSummary(
        opportunityCount: 0,
        matchedObservationCount: 0,
        primaryTrackObservationCount: 0,
        primarySharedFrequencyHz: nil,
        matchPresenceRatio: 0,
        averageFrequencyDeltaHz: nil,
        averageFrequencyAgreement: nil,
        amplitudeCorrelation: nil,
        persistentSoundRatio: 0,
        averageSoundPersistenceConfidence: 0,
        level: .insufficientData
    )
}

enum SoundVibrationCorrelationMath {
    static let minimumOpportunitiesForAssessment = 8
    static let minimumTrackMatchesForAssessment = 4
    static let minimumPresenceForAlignment = 0.50
    static let minimumAmplitudeCorrelationForCoMovement = 0.50
    static let minimumMatchingToleranceHz = 2.0
    static let maximumMatchingToleranceHz = 8.0
    static let trackClusteringToleranceHz = 5.0

    static func matchingToleranceHz(
        audioResolutionHz: Double,
        vibrationResolutionHz: Double
    ) -> Double {
        let derived =
            max(0, audioResolutionHz) * 0.5 +
            max(0, vibrationResolutionHz) * 2.0

        return min(
            maximumMatchingToleranceHz,
            max(
                minimumMatchingToleranceHz,
                derived
            )
        )
    }

    static func matches(
        input: SoundVibrationCorrelationInput
    ) -> [SoundVibrationMatch] {
        let tolerance = matchingToleranceHz(
            audioResolutionHz:
                input.audioResolutionHz,
            vibrationResolutionHz:
                input.vibrationResolutionHz
        )

        guard
            input.vibrationMaximumFrequencyHz > 0,
            !input.dominantSoundFrequencies.isEmpty,
            !input.vibrationPeaks.isEmpty
        else {
            return []
        }

        struct Candidate {
            let soundIndex: Int
            let vibrationIndex: Int
            let deltaHz: Double
        }

        var candidates: [Candidate] = []

        for (soundIndex, sound)
            in input.dominantSoundFrequencies
                .enumerated()
        {
            guard
                sound.frequencyHz <=
                    input.vibrationMaximumFrequencyHz +
                    tolerance
            else {
                continue
            }

            for (vibrationIndex, vibration)
                in input.vibrationPeaks.enumerated()
            {
                let delta = abs(
                    sound.frequencyHz -
                    vibration.frequencyHz
                )

                guard delta <= tolerance else {
                    continue
                }

                candidates.append(
                    Candidate(
                        soundIndex: soundIndex,
                        vibrationIndex:
                            vibrationIndex,
                        deltaHz: delta
                    )
                )
            }
        }

        candidates.sort {
            if abs($0.deltaHz - $1.deltaHz) >
                0.0001
            {
                return $0.deltaHz <
                    $1.deltaHz
            }

            let left =
                input
                    .dominantSoundFrequencies[
                        $0.soundIndex
                    ]
            let right =
                input
                    .dominantSoundFrequencies[
                        $1.soundIndex
                    ]

            return left.scoreDB > right.scoreDB
        }

        var usedSound = Set<Int>()
        var usedVibration = Set<Int>()
        var result: [SoundVibrationMatch] = []

        for candidate in candidates {
            guard
                !usedSound.contains(
                    candidate.soundIndex
                ),
                !usedVibration.contains(
                    candidate.vibrationIndex
                )
            else {
                continue
            }

            let sound =
                input
                    .dominantSoundFrequencies[
                        candidate.soundIndex
                    ]
            let vibration =
                input
                    .vibrationPeaks[
                        candidate.vibrationIndex
                    ]

            let persistent =
                nearestPersistentTone(
                    to: sound.frequencyHz,
                    tones:
                        input.persistentTones,
                    toleranceHz:
                        tolerance * 1.5
                )

            result.append(
                SoundVibrationMatch(
                    soundFrequencyHz:
                        sound.frequencyHz,
                    vibrationFrequencyHz:
                        vibration.frequencyHz,
                    frequencyDeltaHz:
                        candidate.deltaHz,
                    toleranceHz: tolerance,
                    frequencyAgreement:
                        max(
                            0,
                            1.0 -
                            candidate.deltaHz /
                                max(
                                    tolerance,
                                    0.0001
                                )
                        ),
                    soundMagnitudeDBFS:
                        sound.magnitudeDBFS,
                    soundAmplitudeLinear:
                        pow(
                            10.0,
                            sound.magnitudeDBFS /
                                20.0
                        ),
                    vibrationAmplitudeG:
                        vibration.amplitudeG,
                    soundIsPersistent:
                        persistent?
                            .isPersistent ??
                        false,
                    soundPersistenceConfidence:
                        persistent?
                            .confidence ??
                        0
                )
            )

            usedSound.insert(
                candidate.soundIndex
            )
            usedVibration.insert(
                candidate.vibrationIndex
            )
        }

        return result.sorted {
            matchPriority($0) >
            matchPriority($1)
        }
    }

    static func matchPriority(
        _ match: SoundVibrationMatch
    ) -> Double {
        let persistenceBoost =
            match.soundIsPersistent
            ? (
                0.20 +
                0.20 *
                match
                    .soundPersistenceConfidence
            )
            : 0

        return
            match.frequencyAgreement +
            persistenceBoost
    }

    static func summarize(
        observations:
            [SoundVibrationObservation]
    ) -> SoundVibrationCorrelationSummary {
        guard !observations.isEmpty else {
            return .empty
        }

        let matchedObservations =
            observations.filter {
                $0.primaryMatch != nil
            }

        let primaryTrack =
            selectPrimaryTrack(
                matches:
                    matchedObservations
                        .compactMap(
                            .primaryMatch
                        )
            )

        let trackMatches =
            primaryTrack.matches
        let trackCount =
            trackMatches.count
        let opportunityCount =
            observations.count
        let presence =
            Double(trackCount) /
            Double(
                max(
                    1,
                    opportunityCount
                )
            )

        let meanFrequency =
            average(
                trackMatches.map(
                    .centerFrequencyHz
                )
            )
        let meanDelta =
            averageOptional(
                trackMatches.map(
                    .frequencyDeltaHz
                )
            )
        let meanAgreement =
            averageOptional(
                trackMatches.map(
                    .frequencyAgreement
                )
            )
        let amplitudeCorrelation =
            pearsonCorrelation(
                x:
                    trackMatches.map(
                        .soundAmplitudeLinear
                    ),
                y:
                    trackMatches.map(
                        .vibrationAmplitudeG
                    )
            )

        let persistentCount =
            trackMatches.filter(
                .soundIsPersistent
            ).count
        let persistentRatio =
            trackCount > 0
            ? Double(persistentCount) /
                Double(trackCount)
            : 0
        let persistenceConfidence =
            trackCount > 0
            ? average(
                trackMatches.map(
                    .soundPersistenceConfidence
                )
            )
            : 0

        let level: SoundVibrationCorrelationLevel

        if
            opportunityCount <
                minimumOpportunitiesForAssessment ||
            trackCount <
                minimumTrackMatchesForAssessment
        {
            level = .insufficientData
        } else if
            presence <
                minimumPresenceForAlignment
        {
            level = .noConsistentMatch
        } else if
            let amplitudeCorrelation,
            amplitudeCorrelation >=
                minimumAmplitudeCorrelationForCoMovement
        {
            level = .coMoving
        } else {
            level = .frequencyAligned
        }

        return SoundVibrationCorrelationSummary(
            opportunityCount:
                opportunityCount,
            matchedObservationCount:
                matchedObservations.count,
            primaryTrackObservationCount:
                trackCount,
            primarySharedFrequencyHz:
                trackCount > 0
                ? meanFrequency
                : nil,
            matchPresenceRatio:
                presence,
            averageFrequencyDeltaHz:
                meanDelta,
            averageFrequencyAgreement:
                meanAgreement,
            amplitudeCorrelation:
                amplitudeCorrelation,
            persistentSoundRatio:
                persistentRatio,
            averageSoundPersistenceConfidence:
                persistenceConfidence,
            level: level
        )
    }

    static func pearsonCorrelation(
        x: [Double],
        y: [Double]
    ) -> Double? {
        let count = min(
            x.count,
            y.count
        )

        guard count >= 4 else {
            return nil
        }

        let xValues =
            Array(x.prefix(count))
        let yValues =
            Array(y.prefix(count))

        let meanX = average(xValues)
        let meanY = average(yValues)

        var covariance = 0.0
        var varianceX = 0.0
        var varianceY = 0.0

        for index in 0..<count {
            let dx =
                xValues[index] -
                meanX
            let dy =
                yValues[index] -
                meanY

            covariance += dx * dy
            varianceX += dx * dx
            varianceY += dy * dy
        }

        guard
            varianceX > 1e-18,
            varianceY > 1e-18
        else {
            return nil
        }

        return max(
            -1,
            min(
                1,
                covariance /
                sqrt(
                    varianceX *
                    varianceY
                )
            )
        )
    }

    private static func selectPrimaryTrack(
        matches:
            [SoundVibrationMatch]
    ) -> (
        centerFrequencyHz: Double?,
        matches: [SoundVibrationMatch]
    ) {
        guard !matches.isEmpty else {
            return (nil, [])
        }

        struct Track {
            var meanFrequencyHz: Double
            var matches: [SoundVibrationMatch]
        }

        var tracks: [Track] = []

        for match in matches {
            let matchingTrackIndex =
                tracks.indices.min {
                    abs(
                        tracks[$0]
                            .meanFrequencyHz -
                        match.centerFrequencyHz
                    ) <
                    abs(
                        tracks[$1]
                            .meanFrequencyHz -
                        match.centerFrequencyHz
                    )
                }

            if
                let index =
                    matchingTrackIndex,
                abs(
                    tracks[index]
                        .meanFrequencyHz -
                    match.centerFrequencyHz
                ) <=
                    trackClusteringToleranceHz
            {
                tracks[index]
                    .matches
                    .append(match)
                tracks[index]
                    .meanFrequencyHz =
                    average(
                        tracks[index]
                            .matches
                            map {
                                $0.centerFrequencyHz
                            }
                    )
            } else {
                tracks.append(
                    Track(
                        meanFrequencyHz:
                            match.centerFrequencyHz,
                        matches: [match]
                    )
                )
            }
        }

        let best = tracks.max {
            if
                $0.matches.count !=
                    $1.matches.count
            {
                return $0.matches.count <
                    $1.matches.count
            }

            let leftAgreement =
                average(
                    $0.matches.map {
                        $0.frequencyAgreement
                    }
                )
            let rightAgreement =
                average(
                    $1.matches.map {
                        $0.frequencyAgreement
                    }
                )

            return leftAgreement <
                rightAgreement
        }

        return (
            best?.meanFrequencyHz,
            best?.matches ?? []
        )
    }

    private static func nearestPersistentTone(
        to frequencyHz: Double,
        tones: [PersistentTone],
        toleranceHz: Double
    ) -> PersistentTone? {
        tones
            .filter {
                abs(
                    $0.frequencyHz -
                    frequencyHz
                ) <= toleranceHz
            }
            .min {
                abs(
                    $0.frequencyHz -
                    frequencyHz
                ) <
                abs(
                    $1.frequencyHz -
                    frequencyHz
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

    private static func averageOptional(
        _ values: [Double]
    ) -> Double? {
        guard !values.isEmpty else {
            return nil
        }

        return average(values)
    }
}

@MainActor
@Observable
final class SoundVibrationCorrelationModel {
    enum State: Equatable {
        case idle
        case running
        case completed
        case failed(String)

        var isRunning: Bool {
            self == .running
        }
    }

    static let sampleIntervalSeconds = 0.50
    static let maximumObservations = 60
    static let maximumConsecutiveStalePolls = 12

    private(set) var state: State = .idle
    private(set) var observations:
        [SoundVibrationObservation] = []
    private(set) var summary:
        SoundVibrationCorrelationSummary = .empty
    private(set) var latestMatches:
        [SoundVibrationMatch] = []

    private var generation: UInt64 = 0

    func reset() {
        generation += 1
        state = .idle
        observations = []
        summary = .empty
        latestMatches = []
    }

    func stop() {
        generation += 1
        state = observations.isEmpty
            ? .idle
            : .completed
        summary =
            SoundVibrationCorrelationMath
                .summarize(
                    observations:
                        observations
                )
    }

    func run(
        sampleProvider:
            @escaping @MainActor
            () -> SoundVibrationCorrelationInput?,
        safetyCheck:
            @escaping @MainActor
            () -> String?
    ) async {
        guard !state.isRunning else {
            return
        }

        generation += 1
        let currentGeneration = generation

        observations = []
        summary = .empty
        latestMatches = []
        state = .running

        var lastAudioTransform: UInt64?
        var lastMotionSampleCount: UInt64?
        var stalePolls = 0
        let startedAt =
            ProcessInfo.processInfo
                .systemUptime

        while
            currentGeneration == generation,
            !Task.isCancelled,
            observations.count <
                Self.maximumObservations
        {
            if let reason = safetyCheck() {
                state = .failed(reason)
                generation += 1
                return
            }

            if let input = sampleProvider() {
                let audioFresh =
                    lastAudioTransform == nil ||
                    input.audioFFTTransformCount >
                        (lastAudioTransform ?? 0)
                let motionFresh =
                    lastMotionSampleCount == nil ||
                    input.motionSampleCount >
                        (lastMotionSampleCount ?? 0)

                if audioFresh && motionFresh {
                    lastAudioTransform =
                        input.audioFFTTransformCount
                    lastMotionSampleCount =
                        input.motionSampleCount
                    stalePolls = 0

                    let matches =
                        SoundVibrationCorrelationMath
                            .matches(
                                input: input
                            )
                    latestMatches = matches

                    observations.append(
                        SoundVibrationObservation(
                            capturedAtSeconds:
                                ProcessInfo
                                    .processInfo
                                    .systemUptime -
                                startedAt,
                            matches: matches
                        )
                    )

                    summary =
                        SoundVibrationCorrelationMath
                            .summarize(
                                observations:
                                    observations
                            )
                } else {
                    stalePolls += 1
                }
            } else {
                stalePolls += 1
            }

            if
                stalePolls >=
                    Self.maximumConsecutiveStalePolls
            {
                state = .failed(
                    "Fresh paired sound and vibration measurements stopped arriving."
                )
                generation += 1
                return
            }

            try? await Task.sleep(
                nanoseconds: UInt64(
                    Self.sampleIntervalSeconds *
                    1_000_000_000
                )
            )
        }

        guard
            currentGeneration == generation
        else {
            return
        }

        state = .completed
        summary =
            SoundVibrationCorrelationMath
                .summarize(
                    observations:
                        observations
                )
    }
}
