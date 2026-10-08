import Foundation

enum ExperimentEvidenceQuality {
    static let minimumDecisionBuildMajor = 4
    static let minimumDecisionBuildMinor = 1

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
                // Synthetic/unit-test events may not include
                // a session-start build marker.
                return true
            }

            return
                isDecisionBuildEligible(
                    build
                )
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
        event.kind == .comparisonSaved &&
        event.metrics[
            "measured_reduction_db"
        ] != nil &&
        !isContaminated(event)
    }
}
