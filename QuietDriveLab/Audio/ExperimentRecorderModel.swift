import Foundation
import Observation

struct ExperimentRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let recordedAt: Date

    let targetFrequencyHz: Double
    let phaseDegrees: Double
    let outputPercent: Double

    let baselineBandEnergyDBFS: Double
    let treatmentBandEnergyDBFS: Double
    let treatmentMinusBaselineDB: Double
    let measuredReductionDB: Double

    let baselineCenterLevelDBFS: Double
    let treatmentCenterLevelDBFS: Double
    let baselineStandardDeviationDB: Double
    let treatmentStandardDeviationDB: Double

    let baselineSampleCount: Int
    let treatmentSampleCount: Int
    let baselineDurationSeconds: Double
    let treatmentDurationSeconds: Double

    let inputRoute: String
    let outputRoute: String

    init(
        id: UUID = UUID(),
        recordedAt: Date = Date(),
        comparison: BeforeAfterComparison,
        inputRoute: String,
        outputRoute: String
    ) {
        self.id = id
        self.recordedAt = recordedAt

        targetFrequencyHz =
            comparison.treatment.condition.targetFrequencyHz
        phaseDegrees =
            comparison.treatment.condition.phaseDegrees
        outputPercent =
            comparison.treatment.condition.outputPercent

        baselineBandEnergyDBFS =
            comparison.baseline.averageBandEnergyDBFS
        treatmentBandEnergyDBFS =
            comparison.treatment.averageBandEnergyDBFS
        treatmentMinusBaselineDB =
            comparison.treatmentMinusBaselineDB
        measuredReductionDB =
            comparison.measuredReductionDB

        baselineCenterLevelDBFS =
            comparison.baseline.averageCenterLevelDBFS
        treatmentCenterLevelDBFS =
            comparison.treatment.averageCenterLevelDBFS
        baselineStandardDeviationDB =
            comparison.baseline.standardDeviationDB
        treatmentStandardDeviationDB =
            comparison.treatment.standardDeviationDB

        baselineSampleCount =
            comparison.baseline.sampleCount
        treatmentSampleCount =
            comparison.treatment.sampleCount
        baselineDurationSeconds =
            comparison.baseline.durationSeconds
        treatmentDurationSeconds =
            comparison.treatment.durationSeconds

        self.inputRoute = inputRoute
        self.outputRoute = outputRoute
    }
}

@MainActor
@Observable
final class ExperimentRecorderModel {
    private(set) var records: [ExperimentRecord] = []
    private(set) var lastError: String?

    @ObservationIgnored
    private let storageURL: URL?

    @ObservationIgnored
    private let fileManager: FileManager

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

    @discardableResult
    func record(
        comparison: BeforeAfterComparison,
        inputRoute: String,
        outputRoute: String,
        recordedAt: Date = Date()
    ) -> ExperimentRecord {
        let record = ExperimentRecord(
            recordedAt: recordedAt,
            comparison: comparison,
            inputRoute: inputRoute,
            outputRoute: outputRoute
        )

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
                    [ExperimentRecord].self,
                    from: data
                )

            records = decoded.sorted {
                $0.recordedAt > $1.recordedAt
            }
            lastError = nil
        } catch {
            records = []
            lastError =
                "Could not load saved experiments: " +
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
                "Could not save experiment history: " +
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
                "experiments.json",
                isDirectory: false
            )
    }
}
