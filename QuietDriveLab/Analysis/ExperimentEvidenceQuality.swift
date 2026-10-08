import Foundation

enum ExperimentEvidenceQuality {
    static let minimumDecisionBuildMajor = 4
    static let minimumDecisionBuildMinor = 2
    static let audioConfigurationTextKey =
        "audio_configuration"

    static func decisionEligibleEvents(
        _ events: [StructuredLogEvent]
    ) -> [StructuredLogEvent] {
        var buildBySession:
            [UUID: String] = [:]

        for event in events
        where
            event.kind ==
                .sessionStarted
        {
            if
                let build =
                    event.text[
                        "app_build"
                    ]
            {
                buildBySession[
                    event.sessionID
                ] = build
            }
        }

        return events.filter { event in
            guard
                let build =
                    buildBySession[
                        event.sessionID
                    ]
            else {
                // Final decisions require an explicit session
                // build marker. If retention has pruned it,
                // the remaining events are not decision-eligible.
                return false
            }

            guard
                isDecisionBuildEligible(
                    build
                )
            else {
                return false
            }

            if
                event.kind == .comparisonSaved ||
                event.kind == .confidenceSnapshot
            {
                guard
                    let configuration =
                        event.text[
                            audioConfigurationTextKey
                        ],
                    !configuration.isEmpty
                else {
                    return false
                }
            }

            return true
        }
    }

    static func isDecisionBuildEligible(
        _ build: String
    ) -> Bool {
        let components =
            build.split(
                separator: "."
            )

        guard
            components.count >= 2,
            let major =
                Int(components[0]),
            let minor =
                Int(components[1])
        else {
            return false
        }

        return
            major >
                minimumDecisionBuildMajor ||
            (
                major ==
                    minimumDecisionBuildMajor &&
                minor >=
                    minimumDecisionBuildMinor
            )
    }

    static func audioConfigurationID(
        routeSignature: String,
        sampleRate: Double,
        ioBufferDuration: TimeInterval
    ) -> String {
        let roundedSampleRate =
            Int(sampleRate.rounded())
        let bufferTenthsMilliseconds =
            Int(
                (
                    ioBufferDuration *
                    10_000
                ).rounded()
            )

        return
            routeSignature +
            "|sr=" +
            String(roundedSampleRate) +
            "|buf10ms=" +
            String(
                bufferTenthsMilliseconds
            )
    }

    static func audioConfigurationID(
        for event: StructuredLogEvent
    ) -> String? {
        if
            let configuration =
                event.text[
                    audioConfigurationTextKey
                ],
            !configuration.isEmpty
        {
            return configuration
        }

        guard
            let route =
                event.context
                    .routeSignature,
            !route.isEmpty
        else {
            return nil
        }

        // Standalone analytics may still operate on older or
        // synthetic events. Final-decision filtering separately
        // requires the explicit 4.2+ configuration tag.
        return route
    }

    static func isContaminated(
        _ event: StructuredLogEvent
    ) -> Bool {
        if
            event.flags[
                "quality_filtered_samples_only"
            ] == true
        {
            return false
        }

        return
            event.flags[
                "microphone_clipping"
            ] == true ||
            event.flags[
                "likely_program_interference"
            ] == true
    }

    static func isEligibleComparison(
        _ event: StructuredLogEvent
    ) -> Bool {
        guard
            event.kind == .comparisonSaved,
            let reduction =
                event.metrics[
                    "measured_reduction_db"
                ],
            reduction.isFinite
        else {
            return false
        }

        return !isContaminated(event)
    }

    static func isEligibleDecisionComparison(
        _ event: StructuredLogEvent
    ) -> Bool {
        guard
            isEligibleComparison(event),
            let route =
                event.context
                    .routeSignature,
            !route.isEmpty,
            let frequency =
                event.context
                    .targetFrequencyHz,
            let phase =
                event.context
                    .phaseDegrees,
            let output =
                event.context
                    .outputPercent,
            frequency.isFinite,
            phase.isFinite,
            output.isFinite,
            audioConfigurationID(
                for: event
            ) != nil,
            let rawPosition =
                event.text[
                    "head_position"
                ],
            HeadPositionPreset(
                rawValue:
                    rawPosition
            ) != nil
        else {
            return false
        }

        return true
    }
}
