import Foundation

enum ExperimentEvidenceQuality {
    static func isContaminated(
        _ event: StructuredLogEvent
    ) -> Bool {
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
