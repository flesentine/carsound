import XCTest
@testable import QuietDriveLab

final class QuietDriveLabTests: XCTestCase {
    func testProjectBootstraps() {
        XCTAssertTrue(true)
    }

    func testDBFSConversionAtFullScale() {
        XCTAssertEqual(
            AudioLevelAnalyzer.decibelsFS(forAmplitude: 1.0),
            0.0,
            accuracy: 0.0001
        )
    }

    func testDBFSConversionAtHalfScale() {
        XCTAssertEqual(
            AudioLevelAnalyzer.decibelsFS(forAmplitude: 0.5),
            -6.0206,
            accuracy: 0.001
        )
    }

    func testSilenceUsesFiniteFloor() {
        XCTAssertEqual(
            AudioLevelAnalyzer.decibelsFS(forAmplitude: 0),
            AudioLevelAnalyzer.silenceFloorDBFS
        )
    }

    func testMeterPositionClampsToRange() {
        XCTAssertEqual(AudioLevelAnalyzer.meterPosition(forDBFS: -80), 0, accuracy: 0.0001)
        XCTAssertEqual(AudioLevelAnalyzer.meterPosition(forDBFS: -40), 0.5, accuracy: 0.0001)
        XCTAssertEqual(AudioLevelAnalyzer.meterPosition(forDBFS: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(AudioLevelAnalyzer.meterPosition(forDBFS: 12), 1, accuracy: 0.0001)
        XCTAssertEqual(AudioLevelAnalyzer.meterPosition(forDBFS: -120), 0, accuracy: 0.0001)
    }

    func testFFTWaitsForAFullWindow() {
        let analyzer = FFTAnalyzer(size: 1_024)
        let samples = Array(repeating: Float.zero, count: 512)
        XCTAssertNil(analyzer.ingest(samples: samples, sampleRate: 1_024))
    }

    func testFFTFindsKnownSineTone() throws {
        let analyzer = FFTAnalyzer(size: 1_024)
        let sampleRate = 1_024.0
        let frequency = 64.0
        let amplitude: Float = 0.5

        let samples = (0..<1_024).map { index in
            amplitude * Float(sin(2.0 * .pi * frequency * Double(index) / sampleRate))
        }

        let snapshot = try XCTUnwrap(analyzer.ingest(samples: samples, sampleRate: sampleRate))
        let strongest = try XCTUnwrap(snapshot.bins.dropFirst().max { $0.magnitudeDBFS < $1.magnitudeDBFS })

        XCTAssertEqual(snapshot.frequencyResolutionHz, 1.0, accuracy: 0.0001)
        XCTAssertEqual(strongest.frequencyHz, frequency, accuracy: 0.01)
        XCTAssertEqual(strongest.magnitudeDBFS, -6.0206, accuracy: 0.15)
    }

    func testSpectrumSmootherSeedsFromFirstFrame() {
        let smoother = SpectrumSmoother(alpha: 0.15)
        let bins = [
            SpectrumBin(frequencyHz: 64, magnitudeDBFS: -30),
            SpectrumBin(frequencyHz: 128, magnitudeDBFS: -45)
        ]

        XCTAssertEqual(smoother.process(bins), bins)
    }

    func testStableSmoothingMovesLessThanResponsive() throws {
        let bank = SpectrumSmoothingBank()
        let baseline = [
            SpectrumBin(frequencyHz: 64, magnitudeDBFS: -60)
        ]
        let step = [
            SpectrumBin(frequencyHz: 64, magnitudeDBFS: -20)
        ]

        _ = bank.process(baseline)
        let smoothed = bank.process(step)

        let responsive = try XCTUnwrap(smoothed.responsive.first)
        let stable = try XCTUnwrap(smoothed.stable.first)

        XCTAssertGreaterThan(responsive.magnitudeDBFS, stable.magnitudeDBFS)
        XCTAssertLessThan(responsive.magnitudeDBFS, -20)
        XCTAssertGreaterThan(responsive.magnitudeDBFS, -60)
        XCTAssertLessThan(stable.magnitudeDBFS, -20)
        XCTAssertGreaterThan(stable.magnitudeDBFS, -60)
    }

    func testSmoothingBankLimitsWorkToTwoKilohertz() {
        let bank = SpectrumSmoothingBank()
        let bins = [
            SpectrumBin(frequencyHz: 20, magnitudeDBFS: -40),
            SpectrumBin(frequencyHz: 1_000, magnitudeDBFS: -30),
            SpectrumBin(frequencyHz: 2_000, magnitudeDBFS: -20),
            SpectrumBin(frequencyHz: 2_100, magnitudeDBFS: -10)
        ]

        let snapshot = bank.process(bins)

        XCTAssertEqual(
            snapshot.balanced.map(\.frequencyHz),
            [20, 1_000, 2_000]
        )
    }

    func testNoiseFloorSeedsFromFirstSpectrum() {
        let estimator = NoiseFloorEstimator(
            downwardAlpha: 0.30,
            upwardAlpha: 0.01
        )
        let bins = [
            SpectrumBin(frequencyHz: 50, magnitudeDBFS: -60),
            SpectrumBin(frequencyHz: 100, magnitudeDBFS: -50),
            SpectrumBin(frequencyHz: 500, magnitudeDBFS: -40)
        ]

        let snapshot = estimator.process(bins)

        XCTAssertEqual(snapshot.updateCount, 1)
        XCTAssertEqual(snapshot.bins, bins)
        XCTAssertEqual(snapshot.lowFrequencyFloorDBFS, -52.60, accuracy: 0.1)
        XCTAssertEqual(snapshot.widebandFloorDBFS, -50.0, accuracy: 0.1)
        XCTAssertEqual(snapshot.lowFrequencyExcessDB, 0, accuracy: 0.001)
        XCTAssertEqual(snapshot.widebandExcessDB, 0, accuracy: 0.001)
    }

    func testNoiseFloorRisesSlowlyForSuddenLoudSignal() throws {
        let estimator = NoiseFloorEstimator(
            downwardAlpha: 0.30,
            upwardAlpha: 0.01
        )

        _ = estimator.process([
            SpectrumBin(frequencyHz: 100, magnitudeDBFS: -60)
        ])

        let snapshot = estimator.process([
            SpectrumBin(frequencyHz: 100, magnitudeDBFS: -20)
        ])

        let floor = try XCTUnwrap(snapshot.bins.first)

        XCTAssertLessThan(floor.magnitudeDBFS, -35)
        XCTAssertGreaterThan(snapshot.lowFrequencyExcessDB, 15)
    }

    func testNoiseFloorFallsFasterForQuieterSignal() throws {
        let estimator = NoiseFloorEstimator(
            downwardAlpha: 0.30,
            upwardAlpha: 0.01
        )

        _ = estimator.process([
            SpectrumBin(frequencyHz: 100, magnitudeDBFS: -20)
        ])

        let snapshot = estimator.process([
            SpectrumBin(frequencyHz: 100, magnitudeDBFS: -60)
        ])

        let floor = try XCTUnwrap(snapshot.bins.first)

        XCTAssertLessThan(floor.magnitudeDBFS, -21)
        XCTAssertGreaterThan(floor.magnitudeDBFS, -60)
    }

    func testNoiseFloorIgnoresBinsOutsideAnalysisBand() {
        let estimator = NoiseFloorEstimator()
        let snapshot = estimator.process([
            SpectrumBin(frequencyHz: 10, magnitudeDBFS: -20),
            SpectrumBin(frequencyHz: 20, magnitudeDBFS: -30),
            SpectrumBin(frequencyHz: 2_000, magnitudeDBFS: -40),
            SpectrumBin(frequencyHz: 2_100, magnitudeDBFS: -10)
        ])

        XCTAssertEqual(
            snapshot.bins.map(\.frequencyHz),
            [20, 2_000]
        )
    }

    func testDominantFrequencyFindsClearLowFrequencyPeak() throws {
        let detector = DominantFrequencyDetector()
        let spectrum = [
            SpectrumBin(frequencyHz: 20, magnitudeDBFS: -62),
            SpectrumBin(frequencyHz: 40, magnitudeDBFS: -58),
            SpectrumBin(frequencyHz: 60, magnitudeDBFS: -48),
            SpectrumBin(frequencyHz: 80, magnitudeDBFS: -22),
            SpectrumBin(frequencyHz: 100, magnitudeDBFS: -46),
            SpectrumBin(frequencyHz: 120, magnitudeDBFS: -57),
            SpectrumBin(frequencyHz: 140, magnitudeDBFS: -61)
        ]
        let floor = spectrum.map {
            SpectrumBin(
                frequencyHz: $0.frequencyHz,
                magnitudeDBFS: -60
            )
        }

        let result = detector.detect(
            spectrum: spectrum,
            noiseFloor: floor
        )
        let strongest = try XCTUnwrap(result.frequencies.first)

        XCTAssertEqual(strongest.frequencyHz, 80, accuracy: 2)
        XCTAssertEqual(strongest.magnitudeDBFS, -22, accuracy: 0.001)
        XCTAssertGreaterThan(strongest.temporalExcessDB, 30)
        XCTAssertGreaterThan(strongest.localProminenceDB, 25)
    }

    func testDominantFrequencyStillFindsPeakWhenTemporalFloorContainsIt() throws {
        let detector = DominantFrequencyDetector()
        let spectrum = [
            SpectrumBin(frequencyHz: 40, magnitudeDBFS: -60),
            SpectrumBin(frequencyHz: 60, magnitudeDBFS: -52),
            SpectrumBin(frequencyHz: 80, magnitudeDBFS: -24),
            SpectrumBin(frequencyHz: 100, magnitudeDBFS: -51),
            SpectrumBin(frequencyHz: 120, magnitudeDBFS: -59),
            SpectrumBin(frequencyHz: 140, magnitudeDBFS: -61),
            SpectrumBin(frequencyHz: 160, magnitudeDBFS: -62)
        ]

        let result = detector.detect(
            spectrum: spectrum,
            noiseFloor: spectrum
        )
        let strongest = try XCTUnwrap(result.frequencies.first)

        XCTAssertEqual(strongest.frequencyHz, 80, accuracy: 2)
        XCTAssertEqual(strongest.temporalExcessDB, 0, accuracy: 0.001)
        XCTAssertGreaterThan(strongest.localProminenceDB, 20)
    }

    func testDominantFrequencyRejectsFlatSpectrum() {
        let detector = DominantFrequencyDetector()
        let spectrum = stride(from: 20.0, through: 200.0, by: 20.0).map {
            SpectrumBin(frequencyHz: $0, magnitudeDBFS: -45)
        }

        let result = detector.detect(
            spectrum: spectrum,
            noiseFloor: spectrum
        )

        XCTAssertTrue(result.frequencies.isEmpty)
    }

    func testDominantFrequencyRespectsMinimumSeparation() {
        let detector = DominantFrequencyDetector(
            maximumResults: 5,
            minimumSeparationHz: 18,
            minimumLocalProminenceDB: 2.5,
            minimumScoreDB: 3
        )
        let spectrum = [
            SpectrumBin(frequencyHz: 50, magnitudeDBFS: -60),
            SpectrumBin(frequencyHz: 60, magnitudeDBFS: -58),
            SpectrumBin(frequencyHz: 70, magnitudeDBFS: -50),
            SpectrumBin(frequencyHz: 80, magnitudeDBFS: -20),
            SpectrumBin(frequencyHz: 90, magnitudeDBFS: -50),
            SpectrumBin(frequencyHz: 100, magnitudeDBFS: -24),
            SpectrumBin(frequencyHz: 110, magnitudeDBFS: -52),
            SpectrumBin(frequencyHz: 120, magnitudeDBFS: -60),
            SpectrumBin(frequencyHz: 130, magnitudeDBFS: -62)
        ]
        let floor = spectrum.map {
            SpectrumBin(frequencyHz: $0.frequencyHz, magnitudeDBFS: -65)
        }

        let result = detector.detect(
            spectrum: spectrum,
            noiseFloor: floor
        )

        XCTAssertEqual(result.frequencies.count, 2)
        XCTAssertGreaterThanOrEqual(
            abs(
                result.frequencies[0].frequencyHz -
                result.frequencies[1].frequencyHz
            ),
            18
        )
    }

    func testDominantFrequencyOnlyAnalyzesTwentyToTwoHundredHertz() {
        let detector = DominantFrequencyDetector()
        let spectrum = [
            SpectrumBin(frequencyHz: 10, magnitudeDBFS: -10),
            SpectrumBin(frequencyHz: 20, magnitudeDBFS: -60),
            SpectrumBin(frequencyHz: 40, magnitudeDBFS: -55),
            SpectrumBin(frequencyHz: 60, magnitudeDBFS: -20),
            SpectrumBin(frequencyHz: 80, magnitudeDBFS: -55),
            SpectrumBin(frequencyHz: 100, magnitudeDBFS: -60),
            SpectrumBin(frequencyHz: 220, magnitudeDBFS: -5)
        ]
        let floor = spectrum.map {
            SpectrumBin(frequencyHz: $0.frequencyHz, magnitudeDBFS: -65)
        }

        let result = detector.detect(
            spectrum: spectrum,
            noiseFloor: floor
        )

        XCTAssertEqual(result.analyzedBinCount, 5)
        XCTAssertTrue(
            result.frequencies.allSatisfy {
                $0.frequencyHz >= 20 &&
                $0.frequencyHz <= 200
            }
        )
    }

    func testPersistentToneBecomesPersistentAfterTwoSeconds() throws {
        let tracker = PersistentToneTracker()
        var snapshot = PersistentToneSnapshot.empty

        for step in 0...24 {
            let time = Double(step) * 0.1
            let frequency = 74.0 + (step.isMultiple(of: 2) ? 0.4 : -0.4)

            snapshot = tracker.process(
                [
                    DominantFrequency(
                        frequencyHz: frequency,
                        magnitudeDBFS: -25,
                        temporalExcessDB: 10,
                        localProminenceDB: 12,
                        scoreDB: 17
                    )
                ],
                timestampSeconds: time
            )
        }

        let tone = try XCTUnwrap(snapshot.tones.first)

        XCTAssertTrue(tone.isPersistent)
        XCTAssertEqual(snapshot.persistentCount, 1)
        XCTAssertEqual(tone.frequencyHz, 74, accuracy: 0.2)
        XCTAssertGreaterThanOrEqual(tone.durationSeconds, 2.0)
        XCTAssertEqual(tone.presenceRatio, 1.0, accuracy: 0.001)
        XCTAssertLessThan(tone.frequencyStdDevHz, 1.0)
    }

    func testPersistentToneAllowsBriefDropout() throws {
        let tracker = PersistentToneTracker(
            frequencyToleranceHz: 12,
            allowedGapSeconds: 0.45,
            persistenceThresholdSeconds: 0.5,
            minimumPresenceRatio: 0.60,
            maximumPersistentStdDevHz: 8
        )

        _ = tracker.process(
            [
                DominantFrequency(
                    frequencyHz: 80,
                    magnitudeDBFS: -25,
                    temporalExcessDB: 8,
                    localProminenceDB: 10,
                    scoreDB: 14
                )
            ],
            timestampSeconds: 0
        )

        _ = tracker.process([], timestampSeconds: 0.1)
        _ = tracker.process([], timestampSeconds: 0.2)

        var snapshot = PersistentToneSnapshot.empty

        for step in 3...8 {
            snapshot = tracker.process(
                [
                    DominantFrequency(
                        frequencyHz: 80.5,
                        magnitudeDBFS: -24,
                        temporalExcessDB: 9,
                        localProminenceDB: 11,
                        scoreDB: 15.5
                    )
                ],
                timestampSeconds: Double(step) * 0.1
            )
        }

        let tone = try XCTUnwrap(snapshot.tones.first)

        XCTAssertTrue(tone.isPersistent)
        XCTAssertGreaterThan(tone.presenceRatio, 0.60)
        XCTAssertLessThan(tone.presenceRatio, 1.0)
    }

    func testPersistentToneExpiresAfterLongGap() {
        let tracker = PersistentToneTracker(
            frequencyToleranceHz: 12,
            allowedGapSeconds: 0.45,
            persistenceThresholdSeconds: 2,
            minimumPresenceRatio: 0.60,
            maximumPersistentStdDevHz: 8
        )

        _ = tracker.process(
            [
                DominantFrequency(
                    frequencyHz: 90,
                    magnitudeDBFS: -25,
                    temporalExcessDB: 8,
                    localProminenceDB: 10,
                    scoreDB: 14
                )
            ],
            timestampSeconds: 0
        )

        _ = tracker.process([], timestampSeconds: 0.2)
        let snapshot = tracker.process([], timestampSeconds: 0.5)

        XCTAssertTrue(snapshot.tones.isEmpty)
    }

    func testPersistentToneRejectsUnstableFrequency() throws {
        let tracker = PersistentToneTracker(
            frequencyToleranceHz: 12,
            allowedGapSeconds: 0.45,
            persistenceThresholdSeconds: 0.5,
            minimumPresenceRatio: 0.60,
            maximumPersistentStdDevHz: 2.0
        )

        var snapshot = PersistentToneSnapshot.empty

        for step in 0...8 {
            let frequency = step.isMultiple(of: 2) ? 70.0 : 76.0

            snapshot = tracker.process(
                [
                    DominantFrequency(
                        frequencyHz: frequency,
                        magnitudeDBFS: -25,
                        temporalExcessDB: 8,
                        localProminenceDB: 10,
                        scoreDB: 14
                    )
                ],
                timestampSeconds: Double(step) * 0.1
            )
        }

        let tone = try XCTUnwrap(snapshot.tones.first)

        XCTAssertGreaterThan(tone.frequencyStdDevHz, 2.0)
        XCTAssertFalse(tone.isPersistent)
    }

    func testPersistentToneRejectsLowPresenceRatio() throws {
        let tracker = PersistentToneTracker(
            frequencyToleranceHz: 12,
            allowedGapSeconds: 0.45,
            persistenceThresholdSeconds: 0.5,
            minimumPresenceRatio: 0.80,
            maximumPersistentStdDevHz: 8
        )

        let candidate = DominantFrequency(
            frequencyHz: 72,
            magnitudeDBFS: -25,
            temporalExcessDB: 8,
            localProminenceDB: 10,
            scoreDB: 14
        )

        _ = tracker.process([candidate], timestampSeconds: 0.0)
        _ = tracker.process([], timestampSeconds: 0.1)
        _ = tracker.process([candidate], timestampSeconds: 0.2)
        _ = tracker.process([], timestampSeconds: 0.3)
        _ = tracker.process([candidate], timestampSeconds: 0.4)
        let snapshot = tracker.process([candidate], timestampSeconds: 0.5)

        let tone = try XCTUnwrap(snapshot.tones.first)

        XCTAssertLessThan(tone.presenceRatio, 0.80)
        XCTAssertFalse(tone.isPersistent)
    }

    func testLowFrequencyGraphRangeFiltersBins() {
        let bins = [
            SpectrumBin(frequencyHz: 10, magnitudeDBFS: -40),
            SpectrumBin(frequencyHz: 20, magnitudeDBFS: -30),
            SpectrumBin(frequencyHz: 100, magnitudeDBFS: -20),
            SpectrumBin(frequencyHz: 200, magnitudeDBFS: -25),
            SpectrumBin(frequencyHz: 250, magnitudeDBFS: -35)
        ]

        let filtered = SpectrumGraphScale.bins(from: bins, in: .lowFrequency)

        XCTAssertEqual(filtered.map(\.frequencyHz), [20, 100, 200])
    }

    func testSpectrumGraphCoordinateScaling() {
        XCTAssertEqual(
            SpectrumGraphScale.xPosition(
                frequencyHz: 110,
                range: 20...200,
                width: 180
            ),
            90,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            SpectrumGraphScale.yPosition(dbFS: 0, height: 120),
            0,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            SpectrumGraphScale.yPosition(dbFS: -60, height: 120),
            60,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            SpectrumGraphScale.yPosition(dbFS: -120, height: 120),
            120,
            accuracy: 0.0001
        )
    }
}
