import Foundation

enum ToneConfidence: String, Equatable, Sendable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

struct PersistentTone: Equatable, Sendable, Identifiable {
    let trackID: UInt64
    let frequencyHz: Double
    let durationSeconds: Double
    let observationCount: Int
    let presenceRatio: Double
    let frequencyStdDevHz: Double
    let averageLocalProminenceDB: Double
    let averageTemporalExcessDB: Double
    let confidence: Double
    let confidenceLevel: ToneConfidence
    let isPersistent: Bool

    var id: UInt64 { trackID }
}

struct PersistentToneSnapshot: Equatable, Sendable {
    let tones: [PersistentTone]
    let persistentCount: Int
    let updateCount: UInt64

    static let empty = PersistentToneSnapshot(
        tones: [],
        persistentCount: 0,
        updateCount: 0
    )
}

final class PersistentToneTracker {
    private struct Track {
        let id: UInt64
        let firstSeenSeconds: Double
        var lastSeenSeconds: Double
        var observationCount: Int
        var opportunityCount: Int
        var meanFrequencyHz: Double
        var frequencyM2: Double
        var localProminenceSumDB: Double
        var temporalExcessSumDB: Double

        mutating func add(
            _ candidate: DominantFrequency,
            at timestampSeconds: Double
        ) {
            observationCount += 1
            lastSeenSeconds = timestampSeconds

            let delta = candidate.frequencyHz - meanFrequencyHz
            meanFrequencyHz += delta / Double(observationCount)
            let delta2 = candidate.frequencyHz - meanFrequencyHz
            frequencyM2 += delta * delta2

            localProminenceSumDB += candidate.localProminenceDB
            temporalExcessSumDB += candidate.temporalExcessDB
        }
    }

    private let frequencyToleranceHz: Double
    private let allowedGapSeconds: Double
    private let persistenceThresholdSeconds: Double
    private let minimumPresenceRatio: Double
    private let maximumPersistentStdDevHz: Double
    private let maximumTracks: Int

    private var tracks: [Track] = []
    private var nextTrackID: UInt64 = 1
    private var lastTimestampSeconds: Double?
    private(set) var updateCount: UInt64 = 0

    init(
        frequencyToleranceHz: Double = 12.0,
        allowedGapSeconds: Double = 0.45,
        persistenceThresholdSeconds: Double = 2.0,
        minimumPresenceRatio: Double = 0.60,
        maximumPersistentStdDevHz: Double = 8.0,
        maximumTracks: Int = 8
    ) {
        precondition(frequencyToleranceHz > 0)
        precondition(allowedGapSeconds >= 0)
        precondition(persistenceThresholdSeconds > 0)
        precondition(minimumPresenceRatio > 0 && minimumPresenceRatio <= 1)
        precondition(maximumPersistentStdDevHz > 0)
        precondition(maximumTracks > 0)

        self.frequencyToleranceHz = frequencyToleranceHz
        self.allowedGapSeconds = allowedGapSeconds
        self.persistenceThresholdSeconds = persistenceThresholdSeconds
        self.minimumPresenceRatio = minimumPresenceRatio
        self.maximumPersistentStdDevHz = maximumPersistentStdDevHz
        self.maximumTracks = maximumTracks
    }

    func reset() {
        tracks.removeAll(keepingCapacity: true)
        nextTrackID = 1
        lastTimestampSeconds = nil
        updateCount = 0
    }

    func process(
        _ candidates: [DominantFrequency],
        timestampSeconds: Double
    ) -> PersistentToneSnapshot {
        guard timestampSeconds >= 0 else {
            return makeSnapshot()
        }

        if let lastTimestampSeconds, timestampSeconds < lastTimestampSeconds {
            reset()
        }

        self.lastTimestampSeconds = timestampSeconds
        updateCount += 1

        for index in tracks.indices {
            tracks[index].opportunityCount += 1
        }

        var unmatchedTrackIndices = Set(tracks.indices)
        let rankedCandidates = candidates.sorted {
            $0.scoreDB > $1.scoreDB
        }

        for candidate in rankedCandidates {
            let matchingIndex = unmatchedTrackIndices
                .compactMap { index -> (Int, Double)? in
                    let distance = abs(
                        tracks[index].meanFrequencyHz -
                        candidate.frequencyHz
                    )

                    guard distance <= frequencyToleranceHz else {
                        return nil
                    }

                    return (index, distance)
                }
                .min { $0.1 < $1.1 }?
                .0

            if let matchingIndex {
                tracks[matchingIndex].add(
                    candidate,
                    at: timestampSeconds
                )
                unmatchedTrackIndices.remove(matchingIndex)
            } else {
                let newTrack = Track(
                    id: nextTrackID,
                    firstSeenSeconds: timestampSeconds,
                    lastSeenSeconds: timestampSeconds,
                    observationCount: 1,
                    opportunityCount: 1,
                    meanFrequencyHz: candidate.frequencyHz,
                    frequencyM2: 0,
                    localProminenceSumDB: candidate.localProminenceDB,
                    temporalExcessSumDB: candidate.temporalExcessDB
                )

                nextTrackID += 1
                tracks.append(newTrack)
            }
        }

        tracks.removeAll {
            timestampSeconds - $0.lastSeenSeconds > allowedGapSeconds
        }

        if tracks.count > maximumTracks {
            tracks = tracks
                .sorted {
                    trackPriority($0) > trackPriority($1)
                }
                .prefix(maximumTracks)
                .map { $0 }
        }

        return makeSnapshot()
    }

    private func makeSnapshot() -> PersistentToneSnapshot {
        let tones = tracks
            .map(makeTone)
            .sorted {
                if $0.isPersistent != $1.isPersistent {
                    return $0.isPersistent && !$1.isPersistent
                }

                if abs($0.confidence - $1.confidence) > 0.0001 {
                    return $0.confidence > $1.confidence
                }

                return $0.durationSeconds > $1.durationSeconds
            }

        return PersistentToneSnapshot(
            tones: tones,
            persistentCount: tones.filter(\.isPersistent).count,
            updateCount: updateCount
        )
    }

    private func makeTone(
        _ track: Track
    ) -> PersistentTone {
        let duration = max(
            0,
            track.lastSeenSeconds - track.firstSeenSeconds
        )
        let presence = Double(track.observationCount) /
            Double(max(1, track.opportunityCount))
        let variance = track.observationCount > 1
            ? track.frequencyM2 / Double(track.observationCount - 1)
            : 0
        let stdDev = sqrt(max(0, variance))
        let averageProminence =
            track.localProminenceSumDB /
            Double(track.observationCount)
        let averageTemporalExcess =
            track.temporalExcessSumDB /
            Double(track.observationCount)

        let durationScore = min(
            1,
            duration / 5.0
        )
        let presenceScore = min(
            1,
            max(
                0,
                (presence - 0.40) / 0.60
            )
        )
        let stabilityScore = min(
            1,
            max(
                0,
                1.0 - stdDev / maximumPersistentStdDevHz
            )
        )
        let strengthScore = min(
            1,
            max(
                0,
                (
                    averageProminence +
                    0.5 * averageTemporalExcess
                ) / 12.0
            )
        )

        let confidence = min(
            1,
            max(
                0,
                0.35 * durationScore +
                0.25 * presenceScore +
                0.25 * stabilityScore +
                0.15 * strengthScore
            )
        )

        let isPersistent =
            duration >= persistenceThresholdSeconds &&
            presence >= minimumPresenceRatio &&
            stdDev <= maximumPersistentStdDevHz

        let confidenceLevel: ToneConfidence

        switch confidence {
        case 0.75...:
            confidenceLevel = .high
        case 0.45..<0.75:
            confidenceLevel = .medium
        default:
            confidenceLevel = .low
        }

        return PersistentTone(
            trackID: track.id,
            frequencyHz: track.meanFrequencyHz,
            durationSeconds: duration,
            observationCount: track.observationCount,
            presenceRatio: presence,
            frequencyStdDevHz: stdDev,
            averageLocalProminenceDB: averageProminence,
            averageTemporalExcessDB: averageTemporalExcess,
            confidence: confidence,
            confidenceLevel: confidenceLevel,
            isPersistent: isPersistent
        )
    }

    private func trackPriority(
        _ track: Track
    ) -> Double {
        let duration = max(
            0,
            track.lastSeenSeconds - track.firstSeenSeconds
        )
        let presence = Double(track.observationCount) /
            Double(max(1, track.opportunityCount))

        return duration +
            presence +
            0.02 * track.localProminenceSumDB
    }
}
