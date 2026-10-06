import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum StructuredLogExportFormat: String, CaseIterable, Identifiable, Sendable {
    case json
    case csv

    var id: String {
        rawValue
    }

    var title: String {
        rawValue.uppercased()
    }

    var contentType: UTType {
        switch self {
        case .json:
            return .json
        case .csv:
            return .commaSeparatedText
        }
    }

    var fileExtension: String {
        rawValue
    }
}

enum StructuredLogExportScope: String, CaseIterable, Identifiable, Sendable {
    case allEvents
    case currentSession

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .allEvents:
            return "All saved"
        case .currentSession:
            return "Current session"
        }
    }

    var filenameToken: String {
        switch self {
        case .allEvents:
            return "all"
        case .currentSession:
            return "session"
        }
    }
}

struct StructuredLogExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [
            .json,
            .commaSeparatedText
        ]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(
        configuration: ReadConfiguration
    ) throws {
        data =
            configuration.file
                .regularFileContents ??
            Data()
    }

    func fileWrapper(
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        FileWrapper(
            regularFileWithContents:
                data
        )
    }
}

enum StructuredLogExporter {
    static func selectedEvents(
        from events: [StructuredLogEvent],
        scope: StructuredLogExportScope,
        currentSessionID: UUID
    ) -> [StructuredLogEvent] {
        switch scope {
        case .allEvents:
            return events
        case .currentSession:
            return events.filter {
                $0.sessionID ==
                    currentSessionID
            }
        }
    }

    static func data(
        for format: StructuredLogExportFormat,
        events: [StructuredLogEvent]
    ) throws -> Data {
        switch format {
        case .json:
            return try jsonData(
                events: events
            )
        case .csv:
            return Data(
                csvString(
                    events: events
                ).utf8
            )
        }
    }

    static func jsonData(
        events: [StructuredLogEvent]
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]
        encoder.dateEncodingStrategy =
            .iso8601

        return try encoder.encode(events)
    }

    static func csvString(
        events: [StructuredLogEvent]
    ) -> String {
        let metricKeys =
            sortedKeys(
                events.flatMap {
                    $0.metrics.keys
                }
            )
        let textKeys =
            sortedKeys(
                events.flatMap {
                    $0.text.keys
                }
            )
        let flagKeys =
            sortedKeys(
                events.flatMap {
                    $0.flags.keys
                }
            )
        let referenceKeys =
            sortedKeys(
                events.flatMap {
                    $0.references.keys
                }
            )

        let fixedHeader = [
            "schema_version",
            "event_id",
            "recorded_at_utc",
            "session_id",
            "sequence",
            "event_kind",
            "route_signature",
            "route_revision",
            "calibration_profile_id",
            "target_frequency_hz",
            "phase_degrees",
            "output_percent",
            "confidence_score_percent",
            "evidence_coverage_percent",
            "confidence_level"
        ]

        let dynamicHeader =
            metricKeys.map {
                "metrics." + $0
            } +
            textKeys.map {
                "text." + $0
            } +
            flagKeys.map {
                "flags." + $0
            } +
            referenceKeys.map {
                "references." + $0
            }

        var rows = [
            (fixedHeader + dynamicHeader)
                .map(csvField)
                .joined(separator: ",")
        ]

        let dateFormatter =
            makeISO8601Formatter(
                includingFractionalSeconds:
                    true
            )

        for event in events {
            var values = [
                String(
                    event.schemaVersion
                ),
                event.id.uuidString,
                dateFormatter.string(
                    from:
                        event.recordedAt
                ),
                event.sessionID.uuidString,
                String(event.sequence),
                event.kind.rawValue,
                event.context
                    .routeSignature ?? "",
                event.context
                    .routeRevision
                    .map {
                        String($0)
                    } ?? "",
                event.context
                    .calibrationProfileID?
                    .uuidString ?? "",
                numberString(
                    event.context
                        .targetFrequencyHz
                ),
                numberString(
                    event.context
                        .phaseDegrees
                ),
                numberString(
                    event.context
                        .outputPercent
                ),
                numberString(
                    event.context
                        .confidenceScorePercent
                ),
                numberString(
                    event.context
                        .evidenceCoveragePercent
                ),
                event.context
                    .confidenceLevel ?? ""
            ]

            values += metricKeys.map {
                numberString(
                    event.metrics[$0]
                )
            }
            values += textKeys.map {
                event.text[$0] ?? ""
            }
            values += flagKeys.map {
                guard
                    let value =
                        event.flags[$0]
                else {
                    return ""
                }

                return value
                    ? "true"
                    : "false"
            }
            values += referenceKeys.map {
                event.references[$0] ?? ""
            }

            rows.append(
                values
                    .map(csvField)
                    .joined(separator: ",")
            )
        }

        return rows.joined(
            separator: "\r\n"
        ) + "\r\n"
    }

    static func suggestedFilename(
        format: StructuredLogExportFormat,
        scope: StructuredLogExportScope,
        exportedAt: Date = Date()
    ) -> String {
        let formatter =
            makeISO8601Formatter(
                includingFractionalSeconds:
                    false
            )

        let timestamp =
            formatter
                .string(from: exportedAt)
                .replacingOccurrences(
                    of: "-",
                    with: ""
                )
                .replacingOccurrences(
                    of: ":",
                    with: ""
                )

        return [
            "quietdrive-structured-events",
            scope.filenameToken,
            timestamp
        ]
        .joined(separator: "-") +
        "." +
        format.fileExtension
    }

    private static func sortedKeys<S>(
        _ keys: S
    ) -> [String]
    where S: Sequence,
          S.Element == String
    {
        Array(Set(keys)).sorted()
    }

    private static func csvField(
        _ value: String
    ) -> String {
        let needsQuotes =
            value.contains(",") ||
            value.contains(""") ||
            value.contains("\n") ||
            value.contains("\r")

        guard needsQuotes else {
            return value
        }

        return "\"" +
            value.replacingOccurrences(
                of: "\"",
                with: "\"\""
            ) +
            "\""
    }

    private static func numberString(
        _ value: Double?
    ) -> String {
        guard let value else {
            return ""
        }

        return String(
            format: "%.17g",
            locale:
                Locale(
                    identifier:
                        "en_US_POSIX"
                ),
            value
        )
    }

    private static func makeISO8601Formatter(
        includingFractionalSeconds: Bool
    ) -> ISO8601DateFormatter {
        let formatter =
            ISO8601DateFormatter()

        formatter.timeZone =
            TimeZone(
                secondsFromGMT: 0
            )

        if includingFractionalSeconds {
            formatter.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds
            ]
        } else {
            formatter.formatOptions = [
                .withInternetDateTime
            ]
        }

        return formatter
    }
}
