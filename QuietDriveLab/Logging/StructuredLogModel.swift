import Foundation
import Observation

enum StructuredLogEventKind: String, Codable, CaseIterable, Equatable, Sendable {
    case sessionStarted = "session_started"
    case routeTestCaptured = "route_test_captured"
    case calibrationCompleted = "calibration_completed"
    case calibrationFailed = "calibration_failed"
    case comparisonSaved = "comparison_saved"
    case phaseSweepCompleted = "phase_sweep_completed"
    case phaseRefinementCompleted = "phase_refinement_completed"
    case amplitudeSearchCompleted = "amplitude_search_completed"
    case adaptiveAdjustmentAccepted = "adaptive_adjustment_accepted"
    case adaptiveStopped = "adaptive_stopped"
    case adaptiveFailed = "adaptive_failed"
    case workflowFailed = "workflow_failed"
    case bluetoothJitterCompleted = "bluetooth_jitter_completed"
    case soundVibrationCorrelationCompleted = "sound_vibration_correlation_completed"
    case confidenceSnapshot = "confidence_snapshot"
    case captureStarted = "capture_started"
    case captureStopped = "capture_stopped"
    case toneStarted = "tone_started"
    case toneStopped = "tone_stopped"
    case safetyMute = "safety_mute"
}

struct StructuredLogContext: Codable, Equatable, Sendable {
    let routeSignature: String?
    let routeRevision: UInt64?
    let calibrationProfileID: UUID?

    let targetFrequencyHz: Double?
    let phaseDegrees: Double?
    let outputPercent: Double?

    let confidenceScorePercent: Double?
    let evidenceCoveragePercent: Double?
    let confidenceLevel: String?

    static let empty = StructuredLogContext(
        routeSignature: nil,
        routeRevision: nil,
        calibrationProfileID: nil,
        targetFrequencyHz: nil,
        phaseDegrees: nil,
        outputPercent: nil,
        confidenceScorePercent: nil,
        evidenceCoveragePercent: nil,
        confidenceLevel: nil
    )
}

struct StructuredLogEvent: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let recordedAt: Date
    let sessionID: UUID
    let sequence: UInt64
    let kind: StructuredLogEventKind
    let context: StructuredLogContext
    let metrics: [String: Double]
    let text: [String: String]
    let flags: [String: Bool]
    let references: [String: String]

    init(
        id: UUID = UUID(),
        recordedAt: Date = Date(),
        sessionID: UUID,
        sequence: UInt64,
        kind: StructuredLogEventKind,
        context: StructuredLogContext = .empty,
        metrics: [String: Double] = [:],
        text: [String: String] = [:],
        flags: [String: Bool] = [:],
        references: [String: String] = [:]
    ) {
        self.schemaVersion =
            Self.currentSchemaVersion
        self.id = id
        self.recordedAt = recordedAt
        self.sessionID = sessionID
        self.sequence = sequence
        self.kind = kind
        self.context = context
        self.metrics = metrics
        self.text = text
        self.flags = flags
        self.references = references
    }
}

private actor StructuredLogPersistenceWriter {
    private let storageURL: URL
    private var highestSeenRevision: UInt64 = 0

    init(
        storageURL: URL
    ) {
        self.storageURL = storageURL
    }

    func persist(
        events: [StructuredLogEvent],
        revision: UInt64
    ) -> String? {
        guard
            revision >=
                highestSeenRevision
        else {
            return nil
        }

        highestSeenRevision = revision

        do {
            let directory =
                storageURL
                    .deletingLastPathComponent()

            try FileManager.default
                .createDirectory(
                    at: directory,
                    withIntermediateDirectories:
                        true
                )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys
            ]

            try encoder
                .encode(events)
                .write(
                    to: storageURL,
                    options: [.atomic]
                )

            return nil
        } catch {
            return
                "Could not save structured logs: " +
                error.localizedDescription
        }
    }
}

@MainActor
@Observable
final class StructuredLogModel {
    static let maximumEventCount = 10_000

    private(set) var events: [StructuredLogEvent] = []
    private(set) var lastError: String?
    private(set) var currentSessionID: UUID

    @ObservationIgnored
    private let storageURL: URL?

    @ObservationIgnored
    private let fileManager: FileManager

    @ObservationIgnored
    private let persistenceWriter:
        StructuredLogPersistenceWriter?

    @ObservationIgnored
    private var persistenceRevision: UInt64 = 0

    @ObservationIgnored
    private var persistenceTask:
        Task<Void, Never>?

    @ObservationIgnored
    private var nextSequence: UInt64 = 1

    @ObservationIgnored
    private var didRecordSessionStart = false

    init(
        fileManager: FileManager = .default,
        sessionID: UUID = UUID()
    ) {
        self.fileManager = fileManager
        self.currentSessionID = sessionID
        self.storageURL =
            Self.defaultStorageURL(
                fileManager: fileManager
            )
        self.persistenceWriter =
            self.storageURL.map {
                StructuredLogPersistenceWriter(
                    storageURL: $0
                )
            }

        load()
    }

    init(
        storageURL: URL?,
        fileManager: FileManager = .default,
        sessionID: UUID = UUID()
    ) {
        self.fileManager = fileManager
        self.currentSessionID = sessionID
        self.storageURL = storageURL
        self.persistenceWriter =
            storageURL.map {
                StructuredLogPersistenceWriter(
                    storageURL: $0
                )
            }

        load()
    }

    var currentSessionEvents: [StructuredLogEvent] {
        events.filter {
            $0.sessionID ==
                currentSessionID
        }
    }

    var distinctSessionCount: Int {
        Set(
            events.map {
                $0.sessionID
            }
        ).count
    }

    func startSession(
        context: StructuredLogContext = .empty,
        text: [String: String] = [:]
    ) {
        guard !didRecordSessionStart else {
            return
        }

        didRecordSessionStart = true

        record(
            kind: .sessionStarted,
            context: context,
            text: text
        )
    }

    @discardableResult
    func record(
        kind: StructuredLogEventKind,
        context: StructuredLogContext = .empty,
        metrics: [String: Double] = [:],
        text: [String: String] = [:],
        flags: [String: Bool] = [:],
        references: [String: String] = [:],
        recordedAt: Date = Date()
    ) -> StructuredLogEvent {
        let event =
            StructuredLogEvent(
                recordedAt: recordedAt,
                sessionID:
                    currentSessionID,
                sequence:
                    nextSequence,
                kind: kind,
                context: context,
                metrics: metrics,
                text: text,
                flags: flags,
                references: references
            )

        nextSequence &+= 1
        events.append(event)

        if
            events.count >
                Self.maximumEventCount
        {
            events.removeFirst(
                events.count -
                    Self.maximumEventCount
            )
        }

        persist()
        return event
    }

    func clearAll() {
        events.removeAll()
        lastError = nil
        nextSequence = 1
        didRecordSessionStart = false
        persist()
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
                events = []
                lastError = nil
                return
            }

            let data = try Data(
                contentsOf: storageURL
            )

            let decoded = try JSONDecoder()
                .decode(
                    [StructuredLogEvent].self,
                    from: data
                )

            events =
                decoded
                    .sorted {
                        if
                            $0.recordedAt ==
                                $1.recordedAt
                        {
                            if
                                $0.sessionID ==
                                    $1.sessionID
                            {
                                return $0.sequence <
                                    $1.sequence
                            }

                            return $0.sessionID
                                .uuidString <
                                $1.sessionID
                                    .uuidString
                        }

                        return $0.recordedAt <
                            $1.recordedAt
                    }

            if
                events.count >
                    Self.maximumEventCount
            {
                events = Array(
                    events.suffix(
                        Self.maximumEventCount
                    )
                )
            }

            lastError = nil
        } catch {
            events = []
            lastError =
                "Could not load structured logs: " +
                error.localizedDescription
        }
    }

    func flushPersistence() async {
        guard
            let persistenceWriter
        else {
            lastError = nil
            return
        }

        persistenceTask?.cancel()
        persistenceTask = nil

        persistenceRevision &+= 1
        let revision =
            persistenceRevision
        let snapshot = events

        let errorMessage =
            await persistenceWriter
                .persist(
                    events: snapshot,
                    revision: revision
                )

        guard
            revision ==
                persistenceRevision
        else {
            return
        }

        lastError = errorMessage
    }

    private func persist() {
        guard
            let persistenceWriter
        else {
            lastError = nil
            return
        }

        persistenceRevision &+= 1
        let revision =
            persistenceRevision
        let snapshot = events

        persistenceTask?.cancel()
        persistenceTask =
            Task { @MainActor [weak self] in
                guard !Task.isCancelled else {
                    return
                }

                let errorMessage =
                    await persistenceWriter
                        .persist(
                            events: snapshot,
                            revision:
                                revision
                        )

                guard
                    !Task.isCancelled,
                    let self,
                    revision ==
                        self.persistenceRevision
                else {
                    return
                }

                self.lastError =
                    errorMessage
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
                "structured-events.json",
                isDirectory: false
            )
    }
}
