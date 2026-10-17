import Foundation

enum GuidedNoiseTargetSelector {
    static func selectFrequency(
        from tones: [PersistentTone]
    ) -> Double? {
        tones
            .filter { tone in
                tone.isPersistent &&
                tone.confidenceLevel != .low &&
                tone.frequencyHz.isFinite &&
                tone.frequencyHz >=
                    ToneGeneratorMath.minimumFrequencyHz &&
                tone.frequencyHz <=
                    ToneGeneratorMath.maximumFrequencyHz
            }
            .max { first, second in
                if first.confidence != second.confidence {
                    return first.confidence < second.confidence
                }

                return first.durationSeconds <
                    second.durationSeconds
            }?
            .frequencyHz
            .rounded()
    }
}
