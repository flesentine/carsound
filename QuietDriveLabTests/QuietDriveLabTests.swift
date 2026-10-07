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

    func testToneFrequencySanitizesToSupportedIntegerRange() {
        XCTAssertEqual(
            ToneGeneratorMath.sanitizedFrequency(12.4),
            20
        )
        XCTAssertEqual(
            ToneGeneratorMath.sanitizedFrequency(79.6),
            80
        )
        XCTAssertEqual(
            ToneGeneratorMath.sanitizedFrequency(250.2),
            200
        )
    }

    func testToneLoopContainsExactlyOneSecondOfFrames() {
        let samples = ToneGeneratorMath.makeOneSecondLoop(
            frequencyHz: 80,
            sampleRate: 48_000
        )

        XCTAssertEqual(samples.count, 48_000)
    }

    func testToneGeneratorNeverExceedsHardMaximumAmplitude() throws {
        let samples = ToneGeneratorMath.makeOneSecondLoop(
            frequencyHz: 137,
            sampleRate: 48_000
        )
        let peak = try XCTUnwrap(
            samples.map { abs($0) }.max()
        )

        XCTAssertLessThanOrEqual(
            peak,
            ToneGeneratorMath.maximumAmplitude + 0.000001
        )
    }

    func testToneLoopWrapIsPhaseContinuousForIntegerFrequency() throws {
        let samples = ToneGeneratorMath.makeOneSecondLoop(
            frequencyHz: 80,
            sampleRate: 48_000
        )
        let first = try XCTUnwrap(samples.first)
        let second = samples[1]
        let last = try XCTUnwrap(samples.last)

        let normalStep = second - first
        let wrapStep = first - last

        XCTAssertEqual(
            wrapStep,
            normalStep,
            accuracy: 0.00001
        )
    }

    func testTonePhaseNormalizesIntoOneCycle() {
        XCTAssertEqual(
            ToneGeneratorMath.normalizedPhaseDegrees(0),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ToneGeneratorMath.normalizedPhaseDegrees(360),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ToneGeneratorMath.normalizedPhaseDegrees(450),
            90,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ToneGeneratorMath.normalizedPhaseDegrees(-90),
            270,
            accuracy: 0.0001
        )
    }

    func testToneInvertAddsOneHundredEightyDegreesModuloCycle() {
        XCTAssertEqual(
            ToneGeneratorMath.invertedPhaseDegrees(0),
            180,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ToneGeneratorMath.invertedPhaseDegrees(225),
            45,
            accuracy: 0.0001
        )
    }

    func testNinetyDegreeToneStartsAtPositivePeak() throws {
        let samples = ToneGeneratorMath.makeOneSecondLoop(
            frequencyHz: 80,
            sampleRate: 48_000,
            phaseDegrees: 90
        )
        let first = try XCTUnwrap(samples.first)

        XCTAssertEqual(
            first,
            ToneGeneratorMath.maximumAmplitude,
            accuracy: 0.000001
        )
    }

    func testOneHundredEightyDegreePhaseInvertsWaveform() {
        let zeroPhase = ToneGeneratorMath.makeOneSecondLoop(
            frequencyHz: 80,
            sampleRate: 48_000,
            phaseDegrees: 0
        )
        let inverted = ToneGeneratorMath.makeOneSecondLoop(
            frequencyHz: 80,
            sampleRate: 48_000,
            phaseDegrees: 180
        )

        XCTAssertEqual(zeroPhase.count, inverted.count)

        for index in stride(
            from: 0,
            to: zeroPhase.count,
            by: 997
        ) {
            XCTAssertEqual(
                inverted[index],
                -zeroPhase[index],
                accuracy: 0.000001
            )
        }
    }

    func testPhasedToneLoopStillWrapsContinuously() throws {
        let samples = ToneGeneratorMath.makeOneSecondLoop(
            frequencyHz: 113,
            sampleRate: 48_000,
            phaseDegrees: 137
        )
        let first = try XCTUnwrap(samples.first)
        let second = samples[1]
        let last = try XCTUnwrap(samples.last)

        XCTAssertEqual(
            first - last,
            second - first,
            accuracy: 0.00002
        )
    }

    func testToneOutputPercentIsHardClamped() {
        XCTAssertEqual(
            ToneGeneratorMath.sanitizedOutputPercent(-10),
            0
        )
        XCTAssertEqual(
            ToneGeneratorMath.sanitizedOutputPercent(42),
            42
        )
        XCTAssertEqual(
            ToneGeneratorMath.sanitizedOutputPercent(125),
            100
        )
    }

    func testToneDefaultOutputPreservesPreviousMinusFortyDBFSLevel() {
        XCTAssertEqual(
            ToneGeneratorMath.defaultOutputPercent,
            50,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ToneGeneratorMath.effectiveAmplitude(
                forPercent: ToneGeneratorMath.defaultOutputPercent
            ),
            0.01,
            accuracy: 0.000001
        )
        XCTAssertEqual(
            ToneGeneratorMath.levelDBFS(
                forOutputPercent: ToneGeneratorMath.defaultOutputPercent
            ),
            -40,
            accuracy: 0.001
        )
    }

    func testToneHardCeilingIsAboutMinusThirtyFourDBFS() {
        XCTAssertEqual(
            ToneGeneratorMath.maximumAmplitude,
            0.02,
            accuracy: 0.000001
        )
        XCTAssertEqual(
            ToneGeneratorMath.maximumLevelDBFS,
            -33.9794,
            accuracy: 0.001
        )
    }

    func testZeroToneOutputUsesFiniteSilenceFloor() {
        XCTAssertEqual(
            ToneGeneratorMath.levelDBFS(
                forOutputPercent: 0
            ),
            AudioLevelAnalyzer.silenceFloorDBFS
        )
    }

    func testTargetEnergyUsesNarrowMultiBinBand() throws {
        let spectrum = [
            SpectrumBin(frequencyHz: 60, magnitudeDBFS: -60),
            SpectrumBin(frequencyHz: 70, magnitudeDBFS: -40),
            SpectrumBin(frequencyHz: 80, magnitudeDBFS: -30),
            SpectrumBin(frequencyHz: 90, magnitudeDBFS: -40),
            SpectrumBin(frequencyHz: 100, magnitudeDBFS: -60)
        ]

        let measurement = try XCTUnwrap(
            TargetFrequencyEnergyMeter.measure(
                spectrum: spectrum,
                noiseFloor: [],
                targetFrequencyHz: 80,
                frequencyResolutionHz: 10
            )
        )

        XCTAssertEqual(measurement.binCount, 3)
        XCTAssertEqual(measurement.lowerFrequencyHz, 70, accuracy: 0.001)
        XCTAssertEqual(measurement.upperFrequencyHz, 90, accuracy: 0.001)
        XCTAssertEqual(measurement.nearestBinFrequencyHz, 80, accuracy: 0.001)
        XCTAssertEqual(measurement.centerLevelDBFS, -30, accuracy: 0.001)
    }

    func testTargetEnergySumsLinearPowerAcrossBand() {
        let bins = [
            SpectrumBin(frequencyHz: 70, magnitudeDBFS: -40),
            SpectrumBin(frequencyHz: 80, magnitudeDBFS: -40),
            SpectrumBin(frequencyHz: 90, magnitudeDBFS: -40)
        ]

        XCTAssertEqual(
            TargetFrequencyEnergyMeter.bandEnergyDBFS(bins),
            -35.2288,
            accuracy: 0.001
        )
    }

    func testTargetEnergyReportsTenDBAboveMatchingFloor() throws {
        let spectrum = [
            SpectrumBin(frequencyHz: 70, magnitudeDBFS: -30),
            SpectrumBin(frequencyHz: 80, magnitudeDBFS: -30),
            SpectrumBin(frequencyHz: 90, magnitudeDBFS: -30)
        ]
        let floor = [
            SpectrumBin(frequencyHz: 70, magnitudeDBFS: -40),
            SpectrumBin(frequencyHz: 80, magnitudeDBFS: -40),
            SpectrumBin(frequencyHz: 90, magnitudeDBFS: -40)
        ]

        let measurement = try XCTUnwrap(
            TargetFrequencyEnergyMeter.measure(
                spectrum: spectrum,
                noiseFloor: floor,
                targetFrequencyHz: 80,
                frequencyResolutionHz: 10
            )
        )

        XCTAssertEqual(
            try XCTUnwrap(measurement.excessDB),
            10,
            accuracy: 0.001
        )
    }

    func testTargetEnergyWithIncompleteFloorLeavesFloorUnavailable() throws {
        let spectrum = [
            SpectrumBin(frequencyHz: 70, magnitudeDBFS: -35),
            SpectrumBin(frequencyHz: 80, magnitudeDBFS: -25),
            SpectrumBin(frequencyHz: 90, magnitudeDBFS: -35)
        ]
        let incompleteFloor = [
            SpectrumBin(frequencyHz: 80, magnitudeDBFS: -45)
        ]

        let measurement = try XCTUnwrap(
            TargetFrequencyEnergyMeter.measure(
                spectrum: spectrum,
                noiseFloor: incompleteFloor,
                targetFrequencyHz: 80,
                frequencyResolutionHz: 10
            )
        )

        XCTAssertNil(measurement.floorBandEnergyDBFS)
        XCTAssertNil(measurement.excessDB)
    }

    func testTargetEnergyInterpolatesInLinearPower() throws {
        let bins = [
            SpectrumBin(frequencyHz: 70, magnitudeDBFS: -40),
            SpectrumBin(frequencyHz: 90, magnitudeDBFS: -20)
        ]

        let interpolated = try XCTUnwrap(
            TargetFrequencyEnergyMeter.interpolatedPowerDBFS(
                bins: bins,
                targetFrequencyHz: 80
            )
        )

        XCTAssertEqual(interpolated, -22.9671, accuracy: 0.001)
    }

    func testBeforeAfterWindowAveragesInLinearPower() throws {
        let condition = MeasurementCondition(
            targetFrequencyHz: 80,
            phaseDegrees: 0,
            outputPercent: 50,
            toneAudible: false
        )
        let measurements = [
            TargetFrequencyEnergyMeasurement(
                targetFrequencyHz: 80,
                nearestBinFrequencyHz: 82,
                centerLevelDBFS: -40,
                bandEnergyDBFS: -40,
                floorBandEnergyDBFS: nil,
                excessDB: nil,
                lowerFrequencyHz: 70,
                upperFrequencyHz: 90,
                binCount: 3,
                frequencyResolutionHz: 10
            ),
            TargetFrequencyEnergyMeasurement(
                targetFrequencyHz: 80,
                nearestBinFrequencyHz: 82,
                centerLevelDBFS: -20,
                bandEnergyDBFS: -20,
                floorBandEnergyDBFS: nil,
                excessDB: nil,
                lowerFrequencyHz: 70,
                upperFrequencyHz: 90,
                binCount: 3,
                frequencyResolutionHz: 10
            )
        ]

        let summary = try XCTUnwrap(
            BeforeAfterMeasurementMath.summarize(
                measurements,
                condition: condition,
                sampleIntervalSeconds: 0.1
            )
        )

        XCTAssertEqual(
            summary.averageBandEnergyDBFS,
            -22.9671,
            accuracy: 0.001
        )
        XCTAssertEqual(summary.sampleCount, 2)
        XCTAssertEqual(
            summary.durationSeconds,
            0.1,
            accuracy: 0.0001
        )
    }

    func testBeforeAfterComparisonReportsPositiveReduction() throws {
        let baselineCondition = MeasurementCondition(
            targetFrequencyHz: 80,
            phaseDegrees: 0,
            outputPercent: 50,
            toneAudible: false
        )
        let treatmentCondition = MeasurementCondition(
            targetFrequencyHz: 80,
            phaseDegrees: 180,
            outputPercent: 50,
            toneAudible: true
        )

        let baseline = TargetEnergyWindowSummary(
            condition: baselineCondition,
            sampleCount: 20,
            durationSeconds: 1.9,
            averageBandEnergyDBFS: -25,
            minimumBandEnergyDBFS: -26,
            maximumBandEnergyDBFS: -24,
            averageCenterLevelDBFS: -28,
            standardDeviationDB: 0.6
        )
        let treatment = TargetEnergyWindowSummary(
            condition: treatmentCondition,
            sampleCount: 20,
            durationSeconds: 1.9,
            averageBandEnergyDBFS: -29,
            minimumBandEnergyDBFS: -30,
            maximumBandEnergyDBFS: -28,
            averageCenterLevelDBFS: -32,
            standardDeviationDB: 0.5
        )

        let comparison = try XCTUnwrap(
            BeforeAfterMeasurementMath.compare(
                baseline: baseline,
                treatment: treatment
            )
        )

        XCTAssertEqual(
            comparison.treatmentMinusBaselineDB,
            -4,
            accuracy: 0.001
        )
        XCTAssertEqual(
            comparison.measuredReductionDB,
            4,
            accuracy: 0.001
        )
        XCTAssertTrue(comparison.improved)
    }

    func testBeforeAfterComparisonReportsIncrease() throws {
        let condition = MeasurementCondition(
            targetFrequencyHz: 80,
            phaseDegrees: 0,
            outputPercent: 50,
            toneAudible: false
        )
        let baseline = TargetEnergyWindowSummary(
            condition: condition,
            sampleCount: 20,
            durationSeconds: 1.9,
            averageBandEnergyDBFS: -30,
            minimumBandEnergyDBFS: -31,
            maximumBandEnergyDBFS: -29,
            averageCenterLevelDBFS: -32,
            standardDeviationDB: 0.5
        )
        let treatment = TargetEnergyWindowSummary(
            condition: MeasurementCondition(
                targetFrequencyHz: 80,
                phaseDegrees: 90,
                outputPercent: 50,
                toneAudible: true
            ),
            sampleCount: 20,
            durationSeconds: 1.9,
            averageBandEnergyDBFS: -27,
            minimumBandEnergyDBFS: -28,
            maximumBandEnergyDBFS: -26,
            averageCenterLevelDBFS: -29,
            standardDeviationDB: 0.6
        )

        let comparison = try XCTUnwrap(
            BeforeAfterMeasurementMath.compare(
                baseline: baseline,
                treatment: treatment
            )
        )

        XCTAssertEqual(
            comparison.measuredReductionDB,
            -3,
            accuracy: 0.001
        )
        XCTAssertFalse(comparison.improved)
    }

    func testBeforeAfterComparisonRejectsChangedTarget() {
        let baseline = TargetEnergyWindowSummary(
            condition: MeasurementCondition(
                targetFrequencyHz: 80,
                phaseDegrees: 0,
                outputPercent: 50,
                toneAudible: false
            ),
            sampleCount: 20,
            durationSeconds: 1.9,
            averageBandEnergyDBFS: -30,
            minimumBandEnergyDBFS: -31,
            maximumBandEnergyDBFS: -29,
            averageCenterLevelDBFS: -32,
            standardDeviationDB: 0.5
        )
        let treatment = TargetEnergyWindowSummary(
            condition: MeasurementCondition(
                targetFrequencyHz: 90,
                phaseDegrees: 180,
                outputPercent: 50,
                toneAudible: true
            ),
            sampleCount: 20,
            durationSeconds: 1.9,
            averageBandEnergyDBFS: -35,
            minimumBandEnergyDBFS: -36,
            maximumBandEnergyDBFS: -34,
            averageCenterLevelDBFS: -37,
            standardDeviationDB: 0.4
        )

        XCTAssertNil(
            BeforeAfterMeasurementMath.compare(
                baseline: baseline,
                treatment: treatment
            )
        )
    }

    func testBeforeAfterSummaryRejectsMixedTargetSamples() {
        let condition = MeasurementCondition(
            targetFrequencyHz: 80,
            phaseDegrees: 0,
            outputPercent: 50,
            toneAudible: false
        )
        let measurements = [
            TargetFrequencyEnergyMeasurement(
                targetFrequencyHz: 80,
                nearestBinFrequencyHz: 82,
                centerLevelDBFS: -30,
                bandEnergyDBFS: -28,
                floorBandEnergyDBFS: nil,
                excessDB: nil,
                lowerFrequencyHz: 70,
                upperFrequencyHz: 90,
                binCount: 3,
                frequencyResolutionHz: 10
            ),
            TargetFrequencyEnergyMeasurement(
                targetFrequencyHz: 90,
                nearestBinFrequencyHz: 94,
                centerLevelDBFS: -30,
                bandEnergyDBFS: -28,
                floorBandEnergyDBFS: nil,
                excessDB: nil,
                lowerFrequencyHz: 80,
                upperFrequencyHz: 100,
                binCount: 3,
                frequencyResolutionHz: 10
            )
        ]

        XCTAssertNil(
            BeforeAfterMeasurementMath.summarize(
                measurements,
                condition: condition,
                sampleIntervalSeconds: 0.1
            )
        )
    }

    func testExperimentRecordCapturesComparisonAndRoutes() throws {
        let comparison = try XCTUnwrap(
            BeforeAfterMeasurementMath.compare(
                baseline: TargetEnergyWindowSummary(
                    condition: MeasurementCondition(
                        targetFrequencyHz: 80,
                        phaseDegrees: 0,
                        outputPercent: 50,
                        toneAudible: false
                    ),
                    sampleCount: 20,
                    durationSeconds: 1.9,
                    averageBandEnergyDBFS: -25,
                    minimumBandEnergyDBFS: -26,
                    maximumBandEnergyDBFS: -24,
                    averageCenterLevelDBFS: -28,
                    standardDeviationDB: 0.6
                ),
                treatment: TargetEnergyWindowSummary(
                    condition: MeasurementCondition(
                        targetFrequencyHz: 80,
                        phaseDegrees: 180,
                        outputPercent: 42,
                        toneAudible: true
                    ),
                    sampleCount: 20,
                    durationSeconds: 1.9,
                    averageBandEnergyDBFS: -29,
                    minimumBandEnergyDBFS: -30,
                    maximumBandEnergyDBFS: -28,
                    averageCenterLevelDBFS: -32,
                    standardDeviationDB: 0.4
                )
            )
        )

        let record = ExperimentRecord(
            id: UUID(
                uuidString: "00000000-0000-0000-0000-000000000001"
            )!,
            recordedAt: Date(timeIntervalSince1970: 1_000),
            comparison: comparison,
            inputRoute: "iPhone Microphone",
            outputRoute: "Car Audio"
        )

        XCTAssertEqual(record.targetFrequencyHz, 80, accuracy: 0.001)
        XCTAssertEqual(record.phaseDegrees, 180, accuracy: 0.001)
        XCTAssertEqual(record.outputPercent, 42, accuracy: 0.001)
        XCTAssertEqual(record.measuredReductionDB, 4, accuracy: 0.001)
        XCTAssertEqual(record.baselineStandardDeviationDB, 0.6, accuracy: 0.001)
        XCTAssertEqual(record.treatmentStandardDeviationDB, 0.4, accuracy: 0.001)
        XCTAssertEqual(record.inputRoute, "iPhone Microphone")
        XCTAssertEqual(record.outputRoute, "Car Audio")
    }

    @MainActor
    func testExperimentRecorderPersistsAndReloadsHistory() throws {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "quietdrive-experiment-\(UUID().uuidString).json"
            )
        defer {
            try? FileManager.default.removeItem(at: storageURL)
        }

        let comparison = try XCTUnwrap(
            BeforeAfterMeasurementMath.compare(
                baseline: TargetEnergyWindowSummary(
                    condition: MeasurementCondition(
                        targetFrequencyHz: 74,
                        phaseDegrees: 0,
                        outputPercent: 50,
                        toneAudible: false
                    ),
                    sampleCount: 20,
                    durationSeconds: 1.9,
                    averageBandEnergyDBFS: -24,
                    minimumBandEnergyDBFS: -25,
                    maximumBandEnergyDBFS: -23,
                    averageCenterLevelDBFS: -27,
                    standardDeviationDB: 0.5
                ),
                treatment: TargetEnergyWindowSummary(
                    condition: MeasurementCondition(
                        targetFrequencyHz: 74,
                        phaseDegrees: 135,
                        outputPercent: 40,
                        toneAudible: true
                    ),
                    sampleCount: 20,
                    durationSeconds: 1.9,
                    averageBandEnergyDBFS: -27.5,
                    minimumBandEnergyDBFS: -28,
                    maximumBandEnergyDBFS: -27,
                    averageCenterLevelDBFS: -30,
                    standardDeviationDB: 0.4
                )
            )
        )

        let recorder = ExperimentRecorderModel(
            storageURL: storageURL
        )
        let saved = recorder.record(
            comparison: comparison,
            inputRoute: "Built-in microphone",
            outputRoute: "Bluetooth A2DP",
            recordedAt: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(recorder.records.count, 1)
        XCTAssertNil(recorder.lastError)

        let reloaded = ExperimentRecorderModel(
            storageURL: storageURL
        )

        XCTAssertEqual(reloaded.records.count, 1)
        XCTAssertEqual(reloaded.records.first?.id, saved.id)
        XCTAssertEqual(
            try XCTUnwrap(
                reloaded.records.first?.measuredReductionDB
            ),
            3.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            reloaded.records.first?.outputRoute,
            "Bluetooth A2DP"
        )
    }

    @MainActor
    func testExperimentRecorderDeleteAndClearPersist() throws {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "quietdrive-experiment-delete-\(UUID().uuidString).json"
            )
        defer {
            try? FileManager.default.removeItem(at: storageURL)
        }

        func makeComparison(
            phase: Double,
            reduction: Double
        ) throws -> BeforeAfterComparison {
            try XCTUnwrap(
                BeforeAfterMeasurementMath.compare(
                    baseline: TargetEnergyWindowSummary(
                        condition: MeasurementCondition(
                            targetFrequencyHz: 80,
                            phaseDegrees: 0,
                            outputPercent: 50,
                            toneAudible: false
                        ),
                        sampleCount: 20,
                        durationSeconds: 1.9,
                        averageBandEnergyDBFS: -25,
                        minimumBandEnergyDBFS: -26,
                        maximumBandEnergyDBFS: -24,
                        averageCenterLevelDBFS: -28,
                        standardDeviationDB: 0.5
                    ),
                    treatment: TargetEnergyWindowSummary(
                        condition: MeasurementCondition(
                            targetFrequencyHz: 80,
                            phaseDegrees: phase,
                            outputPercent: 50,
                            toneAudible: true
                        ),
                        sampleCount: 20,
                        durationSeconds: 1.9,
                        averageBandEnergyDBFS: -25 - reduction,
                        minimumBandEnergyDBFS: -26 - reduction,
                        maximumBandEnergyDBFS: -24 - reduction,
                        averageCenterLevelDBFS: -28 - reduction,
                        standardDeviationDB: 0.4
                    )
                )
            )
        }

        let recorder = ExperimentRecorderModel(
            storageURL: storageURL
        )
        let first = recorder.record(
            comparison: try makeComparison(
                phase: 90,
                reduction: 1
            ),
            inputRoute: "Mic",
            outputRoute: "Car"
        )
        _ = recorder.record(
            comparison: try makeComparison(
                phase: 180,
                reduction: 3
            ),
            inputRoute: "Mic",
            outputRoute: "Car"
        )

        XCTAssertEqual(recorder.records.count, 2)

        recorder.delete(id: first.id)
        XCTAssertEqual(recorder.records.count, 1)

        let afterDelete = ExperimentRecorderModel(
            storageURL: storageURL
        )
        XCTAssertEqual(afterDelete.records.count, 1)

        recorder.clearAll()
        XCTAssertTrue(recorder.records.isEmpty)

        let afterClear = ExperimentRecorderModel(
            storageURL: storageURL
        )
        XCTAssertTrue(afterClear.records.isEmpty)
    }

    func testPhaseSweepDefaultGridCoversEightCoarsePhases() {
        XCTAssertEqual(
            PhaseSweepMath.defaultPhases,
            [0, 45, 90, 135, 180, 225, 270, 315]
        )
    }

    func testPhaseSweepNormalizesAndDeduplicatesPhases() {
        XCTAssertEqual(
            PhaseSweepMath.normalizedUniquePhases(
                [0, 360, -45, 315, 450]
            ),
            [0, 315, 90]
        )
    }

    func testPhaseSweepBestResultChoosesLowestTreatmentEnergy() throws {
        func makeResult(
            phase: Double,
            treatmentEnergy: Double,
            standardDeviation: Double
        ) throws -> PhaseSweepResult {
            let baseline = TargetEnergyWindowSummary(
                condition: MeasurementCondition(
                    targetFrequencyHz: 80,
                    phaseDegrees: 0,
                    outputPercent: 50,
                    toneAudible: false
                ),
                sampleCount: 20,
                durationSeconds: 1.9,
                averageBandEnergyDBFS: -25,
                minimumBandEnergyDBFS: -26,
                maximumBandEnergyDBFS: -24,
                averageCenterLevelDBFS: -28,
                standardDeviationDB: 0.5
            )
            let treatment = TargetEnergyWindowSummary(
                condition: MeasurementCondition(
                    targetFrequencyHz: 80,
                    phaseDegrees: phase,
                    outputPercent: 50,
                    toneAudible: true
                ),
                sampleCount: 20,
                durationSeconds: 1.9,
                averageBandEnergyDBFS: treatmentEnergy,
                minimumBandEnergyDBFS: treatmentEnergy - 1,
                maximumBandEnergyDBFS: treatmentEnergy + 1,
                averageCenterLevelDBFS: treatmentEnergy - 2,
                standardDeviationDB: standardDeviation
            )
            let comparison = try XCTUnwrap(
                BeforeAfterMeasurementMath.compare(
                    baseline: baseline,
                    treatment: treatment
                )
            )

            return PhaseSweepResult(
                phaseDegrees: phase,
                treatment: treatment,
                comparison: comparison
            )
        }

        let results = [
            try makeResult(
                phase: 0,
                treatmentEnergy: -27,
                standardDeviation: 0.4
            ),
            try makeResult(
                phase: 90,
                treatmentEnergy: -31,
                standardDeviation: 0.8
            ),
            try makeResult(
                phase: 180,
                treatmentEnergy: -29,
                standardDeviation: 0.3
            )
        ]

        let best = try XCTUnwrap(
            PhaseSweepMath.bestResult(from: results)
        )

        XCTAssertEqual(best.phaseDegrees, 90, accuracy: 0.001)
        XCTAssertEqual(
            best.treatment.averageBandEnergyDBFS,
            -31,
            accuracy: 0.001
        )
        XCTAssertEqual(
            best.comparison.measuredReductionDB,
            6,
            accuracy: 0.001
        )
    }

    func testPhaseSweepBestResultUsesVariabilityAsTieBreaker() throws {
        func makeResult(
            phase: Double,
            standardDeviation: Double
        ) throws -> PhaseSweepResult {
            let baseline = TargetEnergyWindowSummary(
                condition: MeasurementCondition(
                    targetFrequencyHz: 80,
                    phaseDegrees: 0,
                    outputPercent: 50,
                    toneAudible: false
                ),
                sampleCount: 20,
                durationSeconds: 1.9,
                averageBandEnergyDBFS: -25,
                minimumBandEnergyDBFS: -26,
                maximumBandEnergyDBFS: -24,
                averageCenterLevelDBFS: -28,
                standardDeviationDB: 0.5
            )
            let treatment = TargetEnergyWindowSummary(
                condition: MeasurementCondition(
                    targetFrequencyHz: 80,
                    phaseDegrees: phase,
                    outputPercent: 50,
                    toneAudible: true
                ),
                sampleCount: 20,
                durationSeconds: 1.9,
                averageBandEnergyDBFS: -30,
                minimumBandEnergyDBFS: -31,
                maximumBandEnergyDBFS: -29,
                averageCenterLevelDBFS: -32,
                standardDeviationDB: standardDeviation
            )
            let comparison = try XCTUnwrap(
                BeforeAfterMeasurementMath.compare(
                    baseline: baseline,
                    treatment: treatment
                )
            )

            return PhaseSweepResult(
                phaseDegrees: phase,
                treatment: treatment,
                comparison: comparison
            )
        }

        let best = try XCTUnwrap(
            PhaseSweepMath.bestResult(
                from: [
                    try makeResult(
                        phase: 45,
                        standardDeviation: 0.8
                    ),
                    try makeResult(
                        phase: 90,
                        standardDeviation: 0.3
                    )
                ]
            )
        )

        XCTAssertEqual(best.phaseDegrees, 90, accuracy: 0.001)
    }

    func testPhaseRefinementStageOneUsesFifteenDegreeGrid() {
        XCTAssertEqual(
            PhaseRefinementMath.stageOnePhases(
                coarseCenterPhaseDegrees: 135
            ),
            [105, 120, 135, 150, 165]
        )
    }

    func testPhaseRefinementStageOneWrapsAcrossZeroDegrees() {
        XCTAssertEqual(
            PhaseRefinementMath.stageOnePhases(
                coarseCenterPhaseDegrees: 350
            ),
            [320, 335, 350, 5, 20]
        )
    }

    func testPhaseRefinementStageTwoUsesFiveDegreeGrid() {
        XCTAssertEqual(
            PhaseRefinementMath.stageTwoPhases(
                fineCenterPhaseDegrees: 140
            ),
            [130, 135, 140, 145, 150]
        )
    }

    func testPhaseRefinementStageTwoWrapsAcrossZeroDegrees() {
        XCTAssertEqual(
            PhaseRefinementMath.stageTwoPhases(
                fineCenterPhaseDegrees: 5
            ),
            [355, 0, 5, 10, 15]
        )
    }

    func testPhaseRefinementBestResultUsesLowestEnergyAcrossStages() throws {
        func makeResult(
            phase: Double,
            energy: Double,
            deviation: Double
        ) throws -> PhaseSweepResult {
            let baseline = TargetEnergyWindowSummary(
                condition: MeasurementCondition(
                    targetFrequencyHz: 80,
                    phaseDegrees: 0,
                    outputPercent: 50,
                    toneAudible: false
                ),
                sampleCount: 20,
                durationSeconds: 1.9,
                averageBandEnergyDBFS: -25,
                minimumBandEnergyDBFS: -26,
                maximumBandEnergyDBFS: -24,
                averageCenterLevelDBFS: -28,
                standardDeviationDB: 0.5
            )
            let treatment = TargetEnergyWindowSummary(
                condition: MeasurementCondition(
                    targetFrequencyHz: 80,
                    phaseDegrees: phase,
                    outputPercent: 50,
                    toneAudible: true
                ),
                sampleCount: 20,
                durationSeconds: 1.9,
                averageBandEnergyDBFS: energy,
                minimumBandEnergyDBFS: energy - 1,
                maximumBandEnergyDBFS: energy + 1,
                averageCenterLevelDBFS: energy - 2,
                standardDeviationDB: deviation
            )
            let comparison = try XCTUnwrap(
                BeforeAfterMeasurementMath.compare(
                    baseline: baseline,
                    treatment: treatment
                )
            )

            return PhaseSweepResult(
                phaseDegrees: phase,
                treatment: treatment,
                comparison: comparison
            )
        }

        let stages = [
            PhaseRefinementStageResult(
                stage: 1,
                centerPhaseDegrees: 135,
                stepDegrees: 15,
                results: [
                    try makeResult(
                        phase: 120,
                        energy: -30,
                        deviation: 0.4
                    ),
                    try makeResult(
                        phase: 135,
                        energy: -31,
                        deviation: 0.5
                    )
                ]
            ),
            PhaseRefinementStageResult(
                stage: 2,
                centerPhaseDegrees: 135,
                stepDegrees: 5,
                results: [
                    try makeResult(
                        phase: 130,
                        energy: -31.5,
                        deviation: 0.4
                    ),
                    try makeResult(
                        phase: 140,
                        energy: -32,
                        deviation: 0.6
                    )
                ]
            )
        ]

        let best = try XCTUnwrap(
            PhaseRefinementMath.bestResult(
                from: stages
            )
        )

        XCTAssertEqual(best.phaseDegrees, 140, accuracy: 0.001)
        XCTAssertEqual(
            best.treatment.averageBandEnergyDBFS,
            -32,
            accuracy: 0.001
        )
        XCTAssertEqual(
            best.comparison.measuredReductionDB,
            7,
            accuracy: 0.001
        )
    }

    func testAmplitudeSearchCoarseGridHonorsUserCeiling() {
        XCTAssertEqual(
            AmplitudeSearchMath.coarseLevels(
                ceilingPercent: 50
            ),
            [10, 20, 30, 40, 50]
        )

        XCTAssertEqual(
            AmplitudeSearchMath.coarseLevels(
                ceilingPercent: 42
            ),
            [10, 20, 30, 40, 42]
        )
    }

    func testAmplitudeSearchNeverBuildsLevelsAboveCeiling() {
        let levels =
            AmplitudeSearchMath.normalizedUniqueLevels(
                [5, 25, 55, 120],
                ceilingPercent: 50
            )

        XCTAssertEqual(levels, [5, 25, 50])
        XCTAssertTrue(
            levels.allSatisfy { $0 <= 50 }
        )
    }

    func testAmplitudeSearchRejectsCeilingBelowMinimum() {
        XCTAssertTrue(
            AmplitudeSearchMath.coarseLevels(
                ceilingPercent: 1
            ).isEmpty
        )
    }

    func testAmplitudeSearchFineGridUsesTwoPercentSteps() {
        XCTAssertEqual(
            AmplitudeSearchMath.fineLevels(
                centeredAt: 30,
                ceilingPercent: 50
            ),
            [
                20, 22, 24, 26, 28, 30,
                32, 34, 36, 38, 40
            ]
        )
    }

    func testAmplitudeSearchFineGridClampsToUserCeiling() {
        XCTAssertEqual(
            AmplitudeSearchMath.fineLevels(
                centeredAt: 48,
                ceilingPercent: 50
            ),
            [38, 40, 42, 44, 46, 48, 50]
        )
    }

    func testAmplitudeSearchBestResultChoosesLowestEnergy() throws {
        func makeResult(
            outputPercent: Double,
            energy: Double,
            deviation: Double
        ) throws -> AmplitudeSearchResult {
            let baseline = TargetEnergyWindowSummary(
                condition: MeasurementCondition(
                    targetFrequencyHz: 80,
                    phaseDegrees: 0,
                    outputPercent: 50,
                    toneAudible: false
                ),
                sampleCount: 20,
                durationSeconds: 1.9,
                averageBandEnergyDBFS: -25,
                minimumBandEnergyDBFS: -26,
                maximumBandEnergyDBFS: -24,
                averageCenterLevelDBFS: -28,
                standardDeviationDB: 0.5
            )
            let treatment = TargetEnergyWindowSummary(
                condition: MeasurementCondition(
                    targetFrequencyHz: 80,
                    phaseDegrees: 140,
                    outputPercent: outputPercent,
                    toneAudible: true
                ),
                sampleCount: 20,
                durationSeconds: 1.9,
                averageBandEnergyDBFS: energy,
                minimumBandEnergyDBFS: energy - 1,
                maximumBandEnergyDBFS: energy + 1,
                averageCenterLevelDBFS: energy - 2,
                standardDeviationDB: deviation
            )
            let comparison = try XCTUnwrap(
                BeforeAfterMeasurementMath.compare(
                    baseline: baseline,
                    treatment: treatment
                )
            )

            return AmplitudeSearchResult(
                outputPercent: outputPercent,
                phaseDegrees: 140,
                treatment: treatment,
                comparison: comparison
            )
        }

        let best = try XCTUnwrap(
            AmplitudeSearchMath.bestResult(
                from: [
                    try makeResult(
                        outputPercent: 20,
                        energy: -28,
                        deviation: 0.4
                    ),
                    try makeResult(
                        outputPercent: 30,
                        energy: -32,
                        deviation: 0.6
                    ),
                    try makeResult(
                        outputPercent: 40,
                        energy: -30,
                        deviation: 0.3
                    )
                ]
            )
        )

        XCTAssertEqual(
            best.outputPercent,
            30,
            accuracy: 0.001
        )
        XCTAssertEqual(
            best.comparison.measuredReductionDB,
            7,
            accuracy: 0.001
        )
    }

    func testAmplitudeSearchTiePrefersLowerOutputAfterVariabilityTie() throws {
        func makeResult(
            outputPercent: Double
        ) throws -> AmplitudeSearchResult {
            let baseline = TargetEnergyWindowSummary(
                condition: MeasurementCondition(
                    targetFrequencyHz: 80,
                    phaseDegrees: 0,
                    outputPercent: 50,
                    toneAudible: false
                ),
                sampleCount: 20,
                durationSeconds: 1.9,
                averageBandEnergyDBFS: -25,
                minimumBandEnergyDBFS: -26,
                maximumBandEnergyDBFS: -24,
                averageCenterLevelDBFS: -28,
                standardDeviationDB: 0.5
            )
            let treatment = TargetEnergyWindowSummary(
                condition: MeasurementCondition(
                    targetFrequencyHz: 80,
                    phaseDegrees: 140,
                    outputPercent: outputPercent,
                    toneAudible: true
                ),
                sampleCount: 20,
                durationSeconds: 1.9,
                averageBandEnergyDBFS: -30,
                minimumBandEnergyDBFS: -31,
                maximumBandEnergyDBFS: -29,
                averageCenterLevelDBFS: -32,
                standardDeviationDB: 0.4
            )
            let comparison = try XCTUnwrap(
                BeforeAfterMeasurementMath.compare(
                    baseline: baseline,
                    treatment: treatment
                )
            )

            return AmplitudeSearchResult(
                outputPercent: outputPercent,
                phaseDegrees: 140,
                treatment: treatment,
                comparison: comparison
            )
        }

        let best = try XCTUnwrap(
            AmplitudeSearchMath.bestResult(
                from: [
                    try makeResult(outputPercent: 40),
                    try makeResult(outputPercent: 20)
                ]
            )
        )

        XCTAssertEqual(
            best.outputPercent,
            20,
            accuracy: 0.001
        )
    }

    func testAdaptivePhaseCandidatesWrapAroundCycle() {
        XCTAssertEqual(
            AdaptiveControllerMath.phaseCandidates(
                around: 358
            ),
            [3, 353]
        )
    }

    func testAdaptiveAmplitudeCandidatesStayInsideCeiling() {
        XCTAssertEqual(
            AdaptiveControllerMath.amplitudeCandidates(
                around: 30,
                ceilingPercent: 50
            ),
            [28, 32]
        )

        XCTAssertEqual(
            AdaptiveControllerMath.amplitudeCandidates(
                around: 50,
                ceilingPercent: 50
            ),
            [48]
        )

        XCTAssertEqual(
            AdaptiveControllerMath.amplitudeCandidates(
                around: 2,
                ceilingPercent: 50
            ),
            [4]
        )
    }

    func testAdaptiveControllerRequiresMinimumImprovement() throws {
        let current = try makeAdaptiveObservation(
            phase: 140,
            output: 30,
            baselineEnergy: -25,
            treatmentEnergy: -30,
            deviation: 0.4
        )
        let tooSmall = try makeAdaptiveObservation(
            phase: 145,
            output: 30,
            baselineEnergy: -25,
            treatmentEnergy: -30.2,
            deviation: 0.4
        )
        let enough = try makeAdaptiveObservation(
            phase: 145,
            output: 30,
            baselineEnergy: -25,
            treatmentEnergy: -30.5,
            deviation: 0.4
        )

        XCTAssertFalse(
            AdaptiveControllerMath.shouldAccept(
                current: current,
                candidate: tooSmall
            )
        )
        XCTAssertTrue(
            AdaptiveControllerMath.shouldAccept(
                current: current,
                candidate: enough
            )
        )
    }

    func testAdaptiveControllerRejectsUnstableCandidate() throws {
        let current = try makeAdaptiveObservation(
            phase: 140,
            output: 30,
            baselineEnergy: -25,
            treatmentEnergy: -30,
            deviation: 0.4
        )
        let unstable = try makeAdaptiveObservation(
            phase: 145,
            output: 30,
            baselineEnergy: -25,
            treatmentEnergy: -31,
            deviation: 3.0
        )

        XCTAssertFalse(
            AdaptiveControllerMath.shouldAccept(
                current: current,
                candidate: unstable
            )
        )
        XCTAssertFalse(
            AdaptiveControllerMath.isStable(unstable)
        )
    }

    func testAdaptiveControllerDetectsThreeDBAmplification() throws {
        let unsafe = try makeAdaptiveObservation(
            phase: 140,
            output: 30,
            baselineEnergy: -30,
            treatmentEnergy: -27,
            deviation: 0.4
        )

        XCTAssertTrue(
            AdaptiveControllerMath.isUnsafeAmplification(
                unsafe
            )
        )
    }

    func testAdaptiveBestObservationPrefersLowerEnergyThenLowerOutput() throws {
        let lowerEnergy = try makeAdaptiveObservation(
            phase: 140,
            output: 30,
            baselineEnergy: -25,
            treatmentEnergy: -32,
            deviation: 0.8
        )
        let higherEnergy = try makeAdaptiveObservation(
            phase: 135,
            output: 28,
            baselineEnergy: -25,
            treatmentEnergy: -31,
            deviation: 0.2
        )

        XCTAssertEqual(
            try XCTUnwrap(
                AdaptiveControllerMath.bestObservation(
                    from: [higherEnergy, lowerEnergy]
                )
            ).settings.outputPercent,
            30,
            accuracy: 0.001
        )

        let sameEnergyHighOutput =
            try makeAdaptiveObservation(
                phase: 140,
                output: 34,
                baselineEnergy: -25,
                treatmentEnergy: -32,
                deviation: 0.4
            )
        let sameEnergyLowOutput =
            try makeAdaptiveObservation(
                phase: 140,
                output: 30,
                baselineEnergy: -25,
                treatmentEnergy: -32,
                deviation: 0.4
            )

        XCTAssertEqual(
            try XCTUnwrap(
                AdaptiveControllerMath.bestObservation(
                    from: [
                        sameEnergyHighOutput,
                        sameEnergyLowOutput
                    ]
                )
            ).settings.outputPercent,
            30,
            accuracy: 0.001
        )
    }

    @MainActor
    func testAdaptiveControllerImmediateSafetyFailureMutesPath() async {
        let baseline = TargetEnergyWindowSummary(
            condition: MeasurementCondition(
                targetFrequencyHz: 80,
                phaseDegrees: 0,
                outputPercent: 30,
                toneAudible: false
            ),
            sampleCount: 20,
            durationSeconds: 1.9,
            averageBandEnergyDBFS: -25,
            minimumBandEnergyDBFS: -26,
            maximumBandEnergyDBFS: -24,
            averageCenterLevelDBFS: -28,
            standardDeviationDB: 0.4
        )
        let controller = AdaptiveControllerModel()
        var failSafeReason: String?

        await controller.run(
            seedSettings: AdaptiveControllerSettings(
                phaseDegrees: 140,
                outputPercent: 30
            ),
            ceilingPercent: 50,
            baseline: baseline,
            applySettings: { _ in },
            measurementProvider: { nil },
            safetyCheck: {
                "Audio output route changed."
            },
            onAcceptedComparison: { _ in },
            onFailSafe: { reason in
                failSafeReason = reason
            }
        )

        XCTAssertEqual(
            failSafeReason,
            "Audio output route changed."
        )

        if case let .failed(message) = controller.state {
            XCTAssertEqual(
                message,
                "Audio output route changed."
            )
        } else {
            XCTFail("Expected adaptive controller fail-safe state.")
        }
    }

    private func makeAdaptiveObservation(
        phase: Double,
        output: Double,
        baselineEnergy: Double,
        treatmentEnergy: Double,
        deviation: Double
    ) throws -> AdaptiveControllerObservation {
        let baseline = TargetEnergyWindowSummary(
            condition: MeasurementCondition(
                targetFrequencyHz: 80,
                phaseDegrees: 0,
                outputPercent: output,
                toneAudible: false
            ),
            sampleCount: 20,
            durationSeconds: 1.9,
            averageBandEnergyDBFS: baselineEnergy,
            minimumBandEnergyDBFS: baselineEnergy - 1,
            maximumBandEnergyDBFS: baselineEnergy + 1,
            averageCenterLevelDBFS: baselineEnergy - 2,
            standardDeviationDB: 0.4
        )
        let treatment = TargetEnergyWindowSummary(
            condition: MeasurementCondition(
                targetFrequencyHz: 80,
                phaseDegrees: phase,
                outputPercent: output,
                toneAudible: true
            ),
            sampleCount: 10,
            durationSeconds: 0.9,
            averageBandEnergyDBFS: treatmentEnergy,
            minimumBandEnergyDBFS: treatmentEnergy - 1,
            maximumBandEnergyDBFS: treatmentEnergy + 1,
            averageCenterLevelDBFS: treatmentEnergy - 2,
            standardDeviationDB: deviation
        )
        let comparison = try XCTUnwrap(
            BeforeAfterMeasurementMath.compare(
                baseline: baseline,
                treatment: treatment
            )
        )

        return AdaptiveControllerObservation(
            settings: AdaptiveControllerSettings(
                phaseDegrees: phase,
                outputPercent: output
            ),
            treatment: treatment,
            comparison: comparison
        )
    }

    func testAdaptiveStabilityGuardLimitsTrustedEnvelope() {
        let guardState = AdaptiveStabilityGuard(
            seed: AdaptiveControllerSettings(
                phaseDegrees: 350,
                outputPercent: 30
            )
        )

        XCTAssertTrue(
            guardState.allows(
                AdaptiveControllerSettings(
                    phaseDegrees: 10,
                    outputPercent: 38
                ),
                ceilingPercent: 50
            )
        )

        XCTAssertFalse(
            guardState.allows(
                AdaptiveControllerSettings(
                    phaseDegrees: 15,
                    outputPercent: 30
                ),
                ceilingPercent: 50
            )
        )

        XCTAssertFalse(
            guardState.allows(
                AdaptiveControllerSettings(
                    phaseDegrees: 350,
                    outputPercent: 39
                ),
                ceilingPercent: 50
            )
        )
    }

    func testAdaptiveStabilityGuardUsesShortestPhaseExcursion() {
        let guardState = AdaptiveStabilityGuard(
            seed: AdaptiveControllerSettings(
                phaseDegrees: 355,
                outputPercent: 30
            )
        )

        XCTAssertEqual(
            guardState.phaseExcursionDegrees(
                for: AdaptiveControllerSettings(
                    phaseDegrees: 5,
                    outputPercent: 30
                )
            ),
            10,
            accuracy: 0.001
        )

        XCTAssertEqual(
            AdaptiveStabilityGuard
                .signedPhaseDeltaDegrees(
                    from: 5,
                    to: 355
                ),
            -10,
            accuracy: 0.001
        )
    }

    func testAdaptiveStabilityGuardAddsCooldownAfterAcceptance() {
        var guardState = AdaptiveStabilityGuard(
            seed: AdaptiveControllerSettings(
                phaseDegrees: 140,
                outputPercent: 30
            )
        )

        let reason = guardState.recordAcceptance(
            from: AdaptiveControllerSettings(
                phaseDegrees: 140,
                outputPercent: 30
            ),
            to: AdaptiveControllerSettings(
                phaseDegrees: 145,
                outputPercent: 30
            ),
            dimension: .phase
        )

        XCTAssertNil(reason)
        XCTAssertEqual(
            guardState.holdIterationsRemaining,
            AdaptiveStabilityGuard
                .cooldownIterationsAfterAcceptance
        )
        XCTAssertTrue(
            guardState.consumeHoldIteration()
        )
        XCTAssertFalse(
            guardState.consumeHoldIteration()
        )
    }

    func testAdaptiveStabilityGuardBacksOffAfterRollbackStreak() {
        var guardState = AdaptiveStabilityGuard(
            seed: AdaptiveControllerSettings(
                phaseDegrees: 140,
                outputPercent: 30
            )
        )

        for _ in 0..<AdaptiveStabilityGuard.rollbackStreakBeforeHold {
            guardState.recordRollback()
        }

        XCTAssertEqual(guardState.holdCount, 1)
        XCTAssertEqual(
            guardState.holdIterationsRemaining,
            AdaptiveStabilityGuard
                .holdIterationsAfterRollbackStreak
        )
        XCTAssertEqual(guardState.rollbackStreak, 0)
    }

    func testAdaptiveStabilityGuardDetectsRepeatedPhaseOscillation() {
        var guardState = AdaptiveStabilityGuard(
            seed: AdaptiveControllerSettings(
                phaseDegrees: 140,
                outputPercent: 30
            )
        )

        var previous = AdaptiveControllerSettings(
            phaseDegrees: 140,
            outputPercent: 30
        )

        let sequence = [145.0, 140.0, 145.0, 140.0]
        var reason: String?

        for phase in sequence {
            let next = AdaptiveControllerSettings(
                phaseDegrees: phase,
                outputPercent: 30
            )
            reason = guardState.recordAcceptance(
                from: previous,
                to: next,
                dimension: .phase
            )
            previous = next
        }

        XCTAssertEqual(
            reason,
            "Adaptive phase adjustments oscillated direction repeatedly."
        )
        XCTAssertGreaterThanOrEqual(
            guardState.phaseReversalStreak,
            AdaptiveStabilityGuard
                .maximumConsecutiveDirectionReversals
        )
    }

    func testAdaptiveStabilityGuardDetectsRepeatedAmplitudeOscillation() {
        var guardState = AdaptiveStabilityGuard(
            seed: AdaptiveControllerSettings(
                phaseDegrees: 140,
                outputPercent: 30
            )
        )

        var previous = AdaptiveControllerSettings(
            phaseDegrees: 140,
            outputPercent: 30
        )

        let sequence = [32.0, 30.0, 32.0, 30.0]
        var reason: String?

        for output in sequence {
            let next = AdaptiveControllerSettings(
                phaseDegrees: 140,
                outputPercent: output
            )
            reason = guardState.recordAcceptance(
                from: previous,
                to: next,
                dimension: .amplitude
            )
            previous = next
        }

        XCTAssertEqual(
            reason,
            "Adaptive amplitude adjustments oscillated direction repeatedly."
        )
    }

    func testProcessingLatencyFFTWindowAtFortyEightKilohertz() {
        XCTAssertEqual(
            ProcessingLatencyMath.fftWindowMilliseconds(
                sampleCount: 4_096,
                sampleRate: 48_000
            ),
            85.3333,
            accuracy: 0.001
        )
    }

    func testProcessingLatencySpectrumCenterAgeAddsHalfWindowProcessingAndPublishAge() {
        XCTAssertEqual(
            ProcessingLatencyMath
                .estimatedSpectrumCenterAgeMilliseconds(
                    fftWindowMilliseconds: 80,
                    analysisProcessingMilliseconds: 3,
                    snapshotAgeMilliseconds: 7
                ),
            50,
            accuracy: 0.001
        )
    }

    func testLatencyRunningStatisticsTracksMeanRangeAndJitter() {
        var statistics = LatencyRunningStatistics()

        statistics.record(20)
        statistics.record(22)
        statistics.record(24)

        XCTAssertEqual(
            statistics.meanMilliseconds,
            22,
            accuracy: 0.001
        )
        XCTAssertEqual(
            statistics.minimumMilliseconds,
            20,
            accuracy: 0.001
        )
        XCTAssertEqual(
            statistics.maximumMilliseconds,
            24,
            accuracy: 0.001
        )
        XCTAssertEqual(
            statistics.standardDeviationMilliseconds,
            2,
            accuracy: 0.001
        )
    }

    func testProcessingLatencyTrackerMeasuresCallbackDSPAndSnapshotAge() {
        var tracker = ProcessingLatencyTracker()

        tracker.record(
            callbackStartedNanoseconds: 1_000_000_000,
            analysisCompletedNanoseconds: 1_002_000_000
        )
        tracker.record(
            callbackStartedNanoseconds: 1_021_000_000,
            analysisCompletedNanoseconds: 1_024_000_000
        )

        let snapshot = tracker.snapshot(
            nowNanoseconds: 1_030_000_000,
            fftSampleCount: 4_096,
            sampleRate: 48_000
        )

        XCTAssertEqual(
            snapshot.latestCallbackIntervalMilliseconds,
            21,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.averageCallbackIntervalMilliseconds,
            21,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.latestAnalysisProcessingMilliseconds,
            3,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.averageAnalysisProcessingMilliseconds,
            2.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.maximumAnalysisProcessingMilliseconds,
            3,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.snapshotAgeMilliseconds,
            6,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.fftWindowMilliseconds,
            85.3333,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.estimatedSpectrumCenterAgeMilliseconds,
            51.6667,
            accuracy: 0.002
        )
    }

    func testProcessingLatencyTrackerCallbackJitterUsesIntervals() {
        var tracker = ProcessingLatencyTracker()

        tracker.record(
            callbackStartedNanoseconds: 1_000_000_000,
            analysisCompletedNanoseconds: 1_001_000_000
        )
        tracker.record(
            callbackStartedNanoseconds: 1_020_000_000,
            analysisCompletedNanoseconds: 1_021_000_000
        )
        tracker.record(
            callbackStartedNanoseconds: 1_042_000_000,
            analysisCompletedNanoseconds: 1_043_000_000
        )

        let snapshot = tracker.snapshot(
            nowNanoseconds: 1_045_000_000,
            fftSampleCount: 4_096,
            sampleRate: 48_000
        )

        XCTAssertEqual(
            snapshot.averageCallbackIntervalMilliseconds,
            21,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.callbackJitterMilliseconds,
            1.4142,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.minimumCallbackIntervalMilliseconds,
            20,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.maximumCallbackIntervalMilliseconds,
            22,
            accuracy: 0.001
        )
    }

    func testAudioRouteClassificationBuiltIn() {
        let inputs = [
            AudioRoutePortRecord(
                name: "iPhone Microphone",
                type: "Built-in microphone",
                isBluetooth: false
            )
        ]
        let outputs = [
            AudioRoutePortRecord(
                name: "iPhone Speaker",
                type: "Built-in speaker",
                isBluetooth: false
            )
        ]

        XCTAssertEqual(
            AudioRouteTestingMath.classify(
                inputs: inputs,
                outputs: outputs
            ),
            .builtIn
        )
    }

    func testAudioRouteClassificationDistinguishesBluetoothProfiles() {
        XCTAssertEqual(
            AudioRouteTestingMath.classify(
                inputs: [],
                outputs: [
                    AudioRoutePortRecord(
                        name: "Car",
                        type: "Bluetooth A2DP",
                        isBluetooth: true
                    )
                ]
            ),
            .bluetoothA2DP
        )

        XCTAssertEqual(
            AudioRouteTestingMath.classify(
                inputs: [
                    AudioRoutePortRecord(
                        name: "Car Mic",
                        type: "Bluetooth HFP",
                        isBluetooth: true
                    )
                ],
                outputs: [
                    AudioRoutePortRecord(
                        name: "Car",
                        type: "Bluetooth HFP",
                        isBluetooth: true
                    )
                ]
            ),
            .bluetoothHFP
        )

        XCTAssertEqual(
            AudioRouteTestingMath.classify(
                inputs: [],
                outputs: [
                    AudioRoutePortRecord(
                        name: "LE Device",
                        type: "Bluetooth LE",
                        isBluetooth: true
                    )
                ]
            ),
            .bluetoothLE
        )
    }

    func testAudioRouteClassificationCarUSBAndWired() {
        XCTAssertEqual(
            AudioRouteTestingMath.classify(
                inputs: [],
                outputs: [
                    AudioRoutePortRecord(
                        name: "CarPlay",
                        type: "Car audio",
                        isBluetooth: false
                    )
                ]
            ),
            .carAudio
        )

        XCTAssertEqual(
            AudioRouteTestingMath.classify(
                inputs: [],
                outputs: [
                    AudioRoutePortRecord(
                        name: "USB DAC",
                        type: "USB audio",
                        isBluetooth: false
                    )
                ]
            ),
            .usb
        )

        XCTAssertEqual(
            AudioRouteTestingMath.classify(
                inputs: [],
                outputs: [
                    AudioRoutePortRecord(
                        name: "Headphones",
                        type: "Headphones",
                        isBluetooth: false
                    )
                ]
            ),
            .wired
        )
    }

    func testAudioRouteSignatureIsStableAcrossPortOrdering() {
        let firstInputs = [
            AudioRoutePortRecord(
                name: "Mic B",
                type: "USB audio",
                isBluetooth: false
            ),
            AudioRoutePortRecord(
                name: "Mic A",
                type: "USB audio",
                isBluetooth: false
            )
        ]
        let secondInputs = firstInputs.reversed()
        let outputs = [
            AudioRoutePortRecord(
                name: "DAC",
                type: "USB audio",
                isBluetooth: false
            )
        ]

        XCTAssertEqual(
            AudioRouteTestingMath.signature(
                inputs: firstInputs,
                outputs: outputs
            ),
            AudioRouteTestingMath.signature(
                inputs: Array(secondInputs),
                outputs: outputs
            )
        )
    }

    @MainActor
    func testAudioRouteTestingPersistsAndReloadsRecords() throws {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "quietdrive-route-test-\(UUID().uuidString).json"
            )
        defer {
            try? FileManager.default.removeItem(at: storageURL)
        }

        let record = AudioRouteTestRecord(
            id: UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000025"
            )!,
            capturedAt: Date(timeIntervalSince1970: 2_500),
            family: .usb,
            routeSignature:
                "IN:USB audio:Mic|OUT:USB audio:DAC",
            routeRevision: 4,
            inputs: [
                AudioRoutePortRecord(
                    name: "Mic",
                    type: "USB audio",
                    isBluetooth: false
                )
            ],
            outputs: [
                AudioRoutePortRecord(
                    name: "DAC",
                    type: "USB audio",
                    isBluetooth: false
                )
            ],
            sampleRate: 48_000,
            ioBufferMilliseconds: 5,
            inputLatencyMilliseconds: 2,
            outputLatencyMilliseconds: 3,
            microphoneBufferMilliseconds: 21.33,
            callbackAverageMilliseconds: 21.4,
            callbackJitterMilliseconds: 0.2,
            analysisAverageMilliseconds: 2.1,
            analysisMaximumMilliseconds: 3.2,
            fftWindowMilliseconds: 85.33,
            snapshotAgeMilliseconds: 8,
            estimatedSpectrumCenterAgeMilliseconds: 52.77,
            microphoneBufferCount: 100,
            fftTransformCount: 96
        )

        let recorder = AudioRouteTestingModel(
            storageURL: storageURL
        )
        recorder.save(record)

        XCTAssertEqual(recorder.records.count, 1)
        XCTAssertEqual(recorder.distinctRouteCount, 1)
        XCTAssertNil(recorder.lastError)

        let reloaded = AudioRouteTestingModel(
            storageURL: storageURL
        )

        XCTAssertEqual(reloaded.records, [record])
        XCTAssertEqual(reloaded.distinctRouteCount, 1)

        reloaded.delete(id: record.id)

        let afterDelete = AudioRouteTestingModel(
            storageURL: storageURL
        )
        XCTAssertTrue(afterDelete.records.isEmpty)
    }

    @MainActor
    func testAudioRouteTestingCountsDistinctSignatures() {
        let model = AudioRouteTestingModel(
            storageURL: nil
        )

        func makeRecord(
            id: String,
            signature: String
        ) -> AudioRouteTestRecord {
            AudioRouteTestRecord(
                id: UUID(uuidString: id)!,
                capturedAt: Date(),
                family: .builtIn,
                routeSignature: signature,
                routeRevision: 1,
                inputs: [],
                outputs: [],
                sampleRate: 48_000,
                ioBufferMilliseconds: 5,
                inputLatencyMilliseconds: 0,
                outputLatencyMilliseconds: 0,
                microphoneBufferMilliseconds: 21,
                callbackAverageMilliseconds: 21,
                callbackJitterMilliseconds: 0.1,
                analysisAverageMilliseconds: 2,
                analysisMaximumMilliseconds: 3,
                fftWindowMilliseconds: 85,
                snapshotAgeMilliseconds: 8,
                estimatedSpectrumCenterAgeMilliseconds: 52,
                microphoneBufferCount: 10,
                fftTransformCount: 6
            )
        }

        model.save(
            makeRecord(
                id: "00000000-0000-0000-0000-000000000001",
                signature: "A"
            )
        )
        model.save(
            makeRecord(
                id: "00000000-0000-0000-0000-000000000002",
                signature: "A"
            )
        )
        model.save(
            makeRecord(
                id: "00000000-0000-0000-0000-000000000003",
                signature: "B"
            )
        )

        XCTAssertEqual(model.records.count, 3)
        XCTAssertEqual(model.distinctRouteCount, 2)
    }

    func testBluetoothProfileDetectionSeparatesA2DPHFPAndLE() {
        XCTAssertEqual(
            BluetoothBehaviorMath.profile(
                inputs: [],
                outputs: [
                    AudioRoutePortRecord(
                        name: "Car",
                        type: "Bluetooth A2DP",
                        isBluetooth: true
                    )
                ]
            ),
            .a2dp
        )

        XCTAssertEqual(
            BluetoothBehaviorMath.profile(
                inputs: [
                    AudioRoutePortRecord(
                        name: "Car Mic",
                        type: "Bluetooth HFP",
                        isBluetooth: true
                    )
                ],
                outputs: [
                    AudioRoutePortRecord(
                        name: "Car",
                        type: "Bluetooth HFP",
                        isBluetooth: true
                    )
                ]
            ),
            .hfp
        )

        XCTAssertEqual(
            BluetoothBehaviorMath.profile(
                inputs: [],
                outputs: [
                    AudioRoutePortRecord(
                        name: "LE",
                        type: "Bluetooth LE",
                        isBluetooth: true
                    )
                ]
            ),
            .le
        )
    }

    func testBluetoothTopologyDetectsLocalMicWithBluetoothOutput() {
        let topology = BluetoothBehaviorMath.topology(
            inputs: [
                AudioRoutePortRecord(
                    name: "iPhone Mic",
                    type: "Built-in microphone",
                    isBluetooth: false
                )
            ],
            outputs: [
                AudioRoutePortRecord(
                    name: "Car",
                    type: "Bluetooth A2DP",
                    isBluetooth: true
                )
            ]
        )

        XCTAssertEqual(
            topology,
            .bluetoothOutputLocalInput
        )
    }

    func testBluetoothTopologyDetectsBluetoothDuplex() {
        let topology = BluetoothBehaviorMath.topology(
            inputs: [
                AudioRoutePortRecord(
                    name: "Car Mic",
                    type: "Bluetooth HFP",
                    isBluetooth: true
                )
            ],
            outputs: [
                AudioRoutePortRecord(
                    name: "Car",
                    type: "Bluetooth HFP",
                    isBluetooth: true
                )
            ]
        )

        XCTAssertEqual(topology, .bluetoothDuplex)
    }

    func testBluetoothStatisticsAverageMatchingProfileOnly() throws {
        let records = [
            makeRouteRecord(
                id: "00000000-0000-0000-0000-000000000101",
                time: 1,
                family: .bluetoothA2DP,
                signature: "A2DP-1",
                sampleRate: 48_000,
                ioBuffer: 10,
                inputLatency: 2,
                outputLatency: 120,
                jitter: 1,
                centerAge: 60
            ),
            makeRouteRecord(
                id: "00000000-0000-0000-0000-000000000102",
                time: 2,
                family: .bluetoothA2DP,
                signature: "A2DP-1",
                sampleRate: 48_000,
                ioBuffer: 12,
                inputLatency: 4,
                outputLatency: 140,
                jitter: 3,
                centerAge: 64
            ),
            makeRouteRecord(
                id: "00000000-0000-0000-0000-000000000103",
                time: 3,
                family: .builtIn,
                signature: "BuiltIn",
                sampleRate: 48_000,
                ioBuffer: 5,
                inputLatency: 1,
                outputLatency: 8,
                jitter: 0.2,
                centerAge: 50
            )
        ]

        let stats = try XCTUnwrap(
            BluetoothBehaviorMath.statistics(
                for: .a2dp,
                records: records
            )
        )

        XCTAssertEqual(stats.recordCount, 2)
        XCTAssertEqual(
            stats.averageIOBufferMilliseconds,
            11,
            accuracy: 0.001
        )
        XCTAssertEqual(
            stats.averageOutputLatencyMilliseconds,
            130,
            accuracy: 0.001
        )
        XCTAssertEqual(
            stats.averageCallbackJitterMilliseconds,
            2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            stats.averageSpectrumCenterAgeMilliseconds,
            62,
            accuracy: 0.001
        )
    }

    func testBluetoothBehaviorCountsProfileSwitchesAndLatencyDelta() {
        let records = [
            makeRouteRecord(
                id: "00000000-0000-0000-0000-000000000111",
                time: 1,
                family: .bluetoothA2DP,
                signature: "A2DP",
                sampleRate: 48_000,
                ioBuffer: 10,
                inputLatency: 2,
                outputLatency: 120,
                jitter: 1,
                centerAge: 60
            ),
            makeRouteRecord(
                id: "00000000-0000-0000-0000-000000000112",
                time: 2,
                family: .bluetoothHFP,
                signature: "HFP",
                sampleRate: 16_000,
                ioBuffer: 20,
                inputLatency: 20,
                outputLatency: 70,
                jitter: 2,
                centerAge: 75
            ),
            makeRouteRecord(
                id: "00000000-0000-0000-0000-000000000113",
                time: 3,
                family: .bluetoothA2DP,
                signature: "A2DP",
                sampleRate: 48_000,
                ioBuffer: 10,
                inputLatency: 2,
                outputLatency: 130,
                jitter: 1,
                centerAge: 61
            ),
            makeRouteRecord(
                id: "00000000-0000-0000-0000-000000000114",
                time: 4,
                family: .builtIn,
                signature: "BuiltIn",
                sampleRate: 48_000,
                ioBuffer: 5,
                inputLatency: 1,
                outputLatency: 10,
                jitter: 0.2,
                centerAge: 50
            )
        ]

        let snapshot = BluetoothBehaviorMath.behavior(
            inputs: [
                AudioRoutePortRecord(
                    name: "iPhone Mic",
                    type: "Built-in microphone",
                    isBluetooth: false
                )
            ],
            outputs: [
                AudioRoutePortRecord(
                    name: "Car",
                    type: "Bluetooth A2DP",
                    isBluetooth: true
                )
            ],
            routeRevision: 9,
            sampleRate: 48_000,
            ioBufferDuration: 0.01,
            inputLatency: 0.002,
            outputLatency: 0.125,
            records: records
        )

        XCTAssertEqual(snapshot.profile, .a2dp)
        XCTAssertEqual(
            snapshot.topology,
            .bluetoothOutputLocalInput
        )
        XCTAssertEqual(snapshot.savedBluetoothTestCount, 3)
        XCTAssertEqual(snapshot.distinctBluetoothRouteCount, 2)
        XCTAssertEqual(snapshot.observedProfileSwitchCount, 2)
        XCTAssertEqual(
            Set(snapshot.observedProfiles),
            Set([.a2dp, .hfp])
        )
        XCTAssertEqual(
            try XCTUnwrap(
                snapshot
                    .nonBluetoothOutputLatencyAverageMilliseconds
            ),
            10,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(
                snapshot
                    .outputLatencyDeltaVersusNonBluetoothMilliseconds
            ),
            115,
            accuracy: 0.001
        )
    }

    private func makeRouteRecord(
        id: String,
        time: TimeInterval,
        family: AudioRouteFamily,
        signature: String,
        sampleRate: Double,
        ioBuffer: Double,
        inputLatency: Double,
        outputLatency: Double,
        jitter: Double,
        centerAge: Double
    ) -> AudioRouteTestRecord {
        let bluetooth = family.isBluetooth
        let portType: String

        switch family {
        case .bluetoothA2DP:
            portType = "Bluetooth A2DP"
        case .bluetoothHFP:
            portType = "Bluetooth HFP"
        case .bluetoothLE:
            portType = "Bluetooth LE"
        case .builtIn:
            portType = "Built-in speaker"
        default:
            portType = family.rawValue
        }

        return AudioRouteTestRecord(
            id: UUID(uuidString: id)!,
            capturedAt: Date(
                timeIntervalSince1970: time
            ),
            family: family,
            routeSignature: signature,
            routeRevision: 1,
            inputs: bluetooth && family == .bluetoothHFP
                ? [
                    AudioRoutePortRecord(
                        name: "Input",
                        type: portType,
                        isBluetooth: true
                    )
                ]
                : [],
            outputs: [
                AudioRoutePortRecord(
                    name: "Output",
                    type: portType,
                    isBluetooth: bluetooth
                )
            ],
            sampleRate: sampleRate,
            ioBufferMilliseconds: ioBuffer,
            inputLatencyMilliseconds: inputLatency,
            outputLatencyMilliseconds: outputLatency,
            microphoneBufferMilliseconds: 21,
            callbackAverageMilliseconds: 21,
            callbackJitterMilliseconds: jitter,
            analysisAverageMilliseconds: 2,
            analysisMaximumMilliseconds: 3,
            fftWindowMilliseconds: 85,
            snapshotAgeMilliseconds: 8,
            estimatedSpectrumCenterAgeMilliseconds:
                centerAge,
            microphoneBufferCount: 100,
            fftTransformCount: 90
        )
    }

    func testBluetoothJitterStableAssessmentNeedsEnoughSamples() {
        let samples = (0..<8).map { index in
            BluetoothJitterSample(
                capturedAtSeconds:
                    Double(index) * 0.25,
                fftTransformCount:
                    UInt64(index + 1),
                profile: .a2dp,
                routeRevision: 1,
                sampleRate: 48_000,
                ioBufferMilliseconds: 10,
                inputLatencyMilliseconds: 2,
                outputLatencyMilliseconds: 120,
                callbackIntervalMilliseconds:
                    21.0 + (index.isMultiple(of: 2) ? 0.2 : -0.2),
                spectrumCenterAgeMilliseconds:
                    60.0 + (index.isMultiple(of: 2) ? 1.0 : -1.0)
            )
        }

        let snapshot =
            BluetoothJitterMath.snapshot(
                samples: samples
            )

        XCTAssertEqual(
            snapshot?.stability,
            .stable
        )
        XCTAssertEqual(
            snapshot?.sampleCount,
            8
        )
        XCTAssertEqual(
            snapshot?.routeRevisionChangeCount,
            0
        )
        XCTAssertEqual(
            snapshot?.profileChangeCount,
            0
        )
    }

    func testBluetoothJitterInsufficientAssessmentBeforeEightSamples() {
        let samples = (0..<7).map { index in
            BluetoothJitterSample(
                capturedAtSeconds:
                    Double(index) * 0.25,
                fftTransformCount:
                    UInt64(index + 1),
                profile: .a2dp,
                routeRevision: 1,
                sampleRate: 48_000,
                ioBufferMilliseconds: 10,
                inputLatencyMilliseconds: 2,
                outputLatencyMilliseconds: 120,
                callbackIntervalMilliseconds: 21,
                spectrumCenterAgeMilliseconds: 60
            )
        }

        XCTAssertEqual(
            BluetoothJitterMath.snapshot(
                samples: samples
            )?.stability,
            .insufficientData
        )
    }

    func testBluetoothJitterDetectsRouteProfileBufferAndSampleRateChanges() {
        let samples = [
            BluetoothJitterSample(
                capturedAtSeconds: 0,
                fftTransformCount: 1,
                profile: .a2dp,
                routeRevision: 1,
                sampleRate: 48_000,
                ioBufferMilliseconds: 10,
                inputLatencyMilliseconds: 2,
                outputLatencyMilliseconds: 120,
                callbackIntervalMilliseconds: 21,
                spectrumCenterAgeMilliseconds: 60
            ),
            BluetoothJitterSample(
                capturedAtSeconds: 0.25,
                fftTransformCount: 2,
                profile: .hfp,
                routeRevision: 2,
                sampleRate: 16_000,
                ioBufferMilliseconds: 20,
                inputLatencyMilliseconds: 20,
                outputLatencyMilliseconds: 70,
                callbackIntervalMilliseconds: 30,
                spectrumCenterAgeMilliseconds: 85
            )
        ] + (2..<8).map { index in
            BluetoothJitterSample(
                capturedAtSeconds:
                    Double(index) * 0.25,
                fftTransformCount:
                    UInt64(index + 1),
                profile: .hfp,
                routeRevision: 2,
                sampleRate: 16_000,
                ioBufferMilliseconds: 20,
                inputLatencyMilliseconds: 20,
                outputLatencyMilliseconds: 70,
                callbackIntervalMilliseconds: 30,
                spectrumCenterAgeMilliseconds: 85
            )
        }

        let snapshot =
            BluetoothJitterMath.snapshot(
                samples: samples
            )

        XCTAssertEqual(
            snapshot?.stability,
            .unstable
        )
        XCTAssertEqual(
            snapshot?.routeRevisionChangeCount,
            1
        )
        XCTAssertEqual(
            snapshot?.profileChangeCount,
            1
        )
        XCTAssertEqual(
            snapshot?.ioBufferChangeCount,
            1
        )
        XCTAssertEqual(
            snapshot?.sampleRateChangeCount,
            1
        )
    }

    func testBluetoothJitterCalculatesOutputLatencyVariation() throws {
        let values = [
            118.0, 120.0, 122.0, 120.0,
            118.0, 120.0, 122.0, 120.0
        ]
        let samples = values.enumerated().map {
            index, latency in
            BluetoothJitterSample(
                capturedAtSeconds:
                    Double(index) * 0.25,
                fftTransformCount:
                    UInt64(index + 1),
                profile: .a2dp,
                routeRevision: 1,
                sampleRate: 48_000,
                ioBufferMilliseconds: 10,
                inputLatencyMilliseconds: 2,
                outputLatencyMilliseconds: latency,
                callbackIntervalMilliseconds: 21,
                spectrumCenterAgeMilliseconds: 60
            )
        }

        let snapshot = try XCTUnwrap(
            BluetoothJitterMath.snapshot(
                samples: samples
            )
        )

        XCTAssertEqual(
            snapshot.outputLatencyMeanMilliseconds,
            120,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.outputLatencyRangeMilliseconds,
            4,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(
            snapshot.outputLatencyJitterMilliseconds,
            1
        )
    }

    func testBluetoothJitterVariableAssessmentUsesTimingVariation() {
        XCTAssertEqual(
            BluetoothJitterMath.assessStability(
                sampleCount: 8,
                callbackJitterMilliseconds: 1.5,
                spectrumCenterAgeJitterMilliseconds: 4,
                routeRevisionChangeCount: 0,
                profileChangeCount: 0,
                ioBufferChangeCount: 0,
                sampleRateChangeCount: 0
            ),
            .variable
        )

        XCTAssertEqual(
            BluetoothJitterMath.assessStability(
                sampleCount: 8,
                callbackJitterMilliseconds: 4,
                spectrumCenterAgeJitterMilliseconds: 4,
                routeRevisionChangeCount: 0,
                profileChangeCount: 0,
                ioBufferChangeCount: 0,
                sampleRateChangeCount: 0
            ),
            .unstable
        )
    }

    func testAccelerometerMagnitudeUsesThreeAxes() {
        let sample = AccelerometerSample(
            timestampSeconds: 1,
            xG: 3,
            yG: 4,
            zG: 12
        )

        XCTAssertEqual(
            sample.magnitudeG,
            13,
            accuracy: 0.001
        )
    }

    func testAccelerometerObservedRateFromInterval() {
        XCTAssertEqual(
            AccelerometerMath.observedSampleRateHz(
                averageIntervalMilliseconds: 10
            ),
            100,
            accuracy: 0.001
        )

        XCTAssertEqual(
            AccelerometerMath.observedSampleRateHz(
                averageIntervalMilliseconds: 0
            ),
            0,
            accuracy: 0.001
        )
    }

    func testAccelerometerRingBufferKeepsNewestSamplesInOrder() {
        var buffer = AccelerometerRingBuffer(
            capacity: 3
        )

        for index in 1...4 {
            buffer.append(
                AccelerometerSample(
                    timestampSeconds:
                        Double(index),
                    xG: Double(index),
                    yG: 0,
                    zG: 0
                )
            )
        }

        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(
            buffer.orderedSamples().map(\.xG),
            [2, 3, 4]
        )
    }

    func testAccelerometerStoreTracksCadenceAndRollingCapacity() {
        let store = AccelerometerSampleStore(
            capacity: 3
        )

        store.record(
            timestampSeconds: 0.00,
            xG: 1,
            yG: 0,
            zG: 0
        )
        store.record(
            timestampSeconds: 0.01,
            xG: 2,
            yG: 0,
            zG: 0
        )
        store.record(
            timestampSeconds: 0.02,
            xG: 3,
            yG: 0,
            zG: 0
        )
        store.record(
            timestampSeconds: 0.03,
            xG: 4,
            yG: 0,
            zG: 0
        )

        let snapshot = store.snapshot()

        XCTAssertEqual(
            snapshot.totalSampleCount,
            4
        )
        XCTAssertEqual(
            snapshot.storedSampleCount,
            3
        )
        XCTAssertEqual(
            snapshot.elapsedSeconds,
            0.03,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            snapshot.averageIntervalMilliseconds,
            10,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.intervalJitterMilliseconds,
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.observedSampleRateHz,
            100,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.latestSample?.xG,
            4
        )
        XCTAssertEqual(
            store.recentSamples().map(\.xG),
            [2, 3, 4]
        )
    }

    func testAccelerometerStoreResetClearsSamplesAndTiming() {
        let store = AccelerometerSampleStore(
            capacity: 8
        )

        store.record(
            timestampSeconds: 1,
            xG: 0.1,
            yG: 0.2,
            zG: 0.3
        )
        store.record(
            timestampSeconds: 1.01,
            xG: 0.2,
            yG: 0.3,
            zG: 0.4
        )

        store.reset()

        XCTAssertEqual(
            store.snapshot(),
            .empty
        )
        XCTAssertTrue(
            store.recentSamples().isEmpty
        )
    }

    func testVibrationSpectrumDetectsTwentyHertzTone() throws {
        let sampleRate = 200.0
        let count = 512
        let samples = (0..<count).map { index in
            let time = Double(index) / sampleRate
            return AccelerometerSample(
                timestampSeconds: time,
                xG:
                    1.0 +
                    0.01 *
                    sin(
                        2 * .pi * 20 * time
                    ),
                yG: 0,
                zG: 0
            )
        }

        let spectrum =
            VibrationSpectrumAnalyzer.analyze(
                samples: samples
            )
        let peak = try XCTUnwrap(
            spectrum.dominantPeaks.first
        )

        XCTAssertEqual(
            peak.frequencyHz,
            20,
            accuracy: 0.6
        )
        XCTAssertGreaterThan(
            peak.amplitudeMilliG,
            5
        )
        XCTAssertEqual(
            spectrum.observedSampleRateHz,
            200,
            accuracy: 0.5
        )
    }

    func testVibrationSpectrumDetectsSeventyTwoHertzWhenSampleRateAllows() throws {
        let sampleRate = 200.0
        let count = 512
        let samples = (0..<count).map { index in
            let time = Double(index) / sampleRate
            return AccelerometerSample(
                timestampSeconds: time,
                xG: 0,
                yG:
                    1.0 +
                    0.008 *
                    sin(
                        2 * .pi * 72 * time
                    ),
                zG: 0
            )
        }

        let spectrum =
            VibrationSpectrumAnalyzer.analyze(
                samples: samples
            )

        XCTAssertTrue(
            spectrum.canResolveSeventyTwoHz
        )

        let nearest = try XCTUnwrap(
            spectrum.dominantPeaks.min {
                abs($0.frequencyHz - 72) <
                abs($1.frequencyHz - 72)
            }
        )

        XCTAssertEqual(
            nearest.frequencyHz,
            72,
            accuracy: 0.6
        )
    }

    func testVibrationSpectrumRefusesSeventyTwoHertzWhenNyquistIsTooLow() {
        let sampleRate = 100.0
        let count = 512
        let samples = (0..<count).map { index in
            let time = Double(index) / sampleRate
            return AccelerometerSample(
                timestampSeconds: time,
                xG:
                    1.0 +
                    0.01 *
                    sin(
                        2 * .pi * 20 * time
                    ),
                yG: 0,
                zG: 0
            )
        }

        let spectrum =
            VibrationSpectrumAnalyzer.analyze(
                samples: samples
            )

        XCTAssertFalse(
            spectrum.canResolveSeventyTwoHz
        )
        XCTAssertEqual(
            spectrum.nyquistFrequencyHz,
            50,
            accuracy: 0.3
        )
        XCTAssertLessThanOrEqual(
            spectrum.maximumAnalyzedFrequencyHz,
            45.1
        )
        XCTAssertTrue(
            spectrum.bins.allSatisfy {
                $0.frequencyHz <= 45.1
            }
        )
    }

    func testVibrationHighPassRemovesConstantGravity() {
        let samples =
            Array(
                repeating: 1.0,
                count: 512
            )

        let filtered =
            VibrationSpectrumAnalyzer.highPass(
                samples,
                cutoffHz: 1.5,
                dt: 0.005
            )

        let tail =
            filtered.suffix(100)
        let maximum =
            tail.map(abs).max() ?? 1

        XCTAssertLessThan(
            maximum,
            0.001
        )
    }

    func testVibrationResamplingProducesUniformTimestamps() {
        let samples = [
            AccelerometerSample(
                timestampSeconds: 0,
                xG: 0,
                yG: 0,
                zG: 0
            ),
            AccelerometerSample(
                timestampSeconds: 0.012,
                xG: 1,
                yG: 0,
                zG: 0
            ),
            AccelerometerSample(
                timestampSeconds: 0.020,
                xG: 2,
                yG: 0,
                zG: 0
            )
        ]

        let result =
            VibrationSpectrumAnalyzer
                .resampleUniformly(
                    samples: samples,
                    sampleCount: 5
                )

        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(
            result[1].timestampSeconds,
            0.005,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            result[4].timestampSeconds,
            0.020,
            accuracy: 0.0001
        )
    }

    func testSoundVibrationMatchingToleranceUsesBothResolutions() {
        XCTAssertEqual(
            SoundVibrationCorrelationMath
                .matchingToleranceHz(
                    audioResolutionHz: 11.71875,
                    vibrationResolutionHz: 0.390625
                ),
            6.640625,
            accuracy: 0.0001
        )
    }

    func testSoundVibrationMatchesNearbyPeaks() throws {
        let input = SoundVibrationCorrelationInput(
            audioFFTTransformCount: 10,
            motionSampleCount: 500,
            audioResolutionHz: 11.71875,
            vibrationResolutionHz: 0.390625,
            vibrationMaximumFrequencyHz: 90,
            dominantSoundFrequencies: [
                DominantFrequency(
                    frequencyHz: 40,
                    magnitudeDBFS: -30,
                    temporalExcessDB: 8,
                    localProminenceDB: 7,
                    scoreDB: 11
                )
            ],
            persistentTones: [],
            vibrationPeaks: [
                VibrationPeak(
                    frequencyHz: 41,
                    amplitudeG: 0.005
                )
            ]
        )

        let match = try XCTUnwrap(
            SoundVibrationCorrelationMath
                .matches(input: input)
                .first
        )

        XCTAssertEqual(
            match.soundFrequencyHz,
            40,
            accuracy: 0.001
        )
        XCTAssertEqual(
            match.vibrationFrequencyHz,
            41,
            accuracy: 0.001
        )
        XCTAssertEqual(
            match.frequencyDeltaHz,
            1,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(
            match.frequencyAgreement,
            0.8
        )
    }

    func testSoundVibrationDoesNotMatchAboveVibrationSafeBand() {
        let input = SoundVibrationCorrelationInput(
            audioFFTTransformCount: 10,
            motionSampleCount: 500,
            audioResolutionHz: 11.71875,
            vibrationResolutionHz: 0.1953125,
            vibrationMaximumFrequencyHz: 45,
            dominantSoundFrequencies: [
                DominantFrequency(
                    frequencyHz: 72,
                    magnitudeDBFS: -25,
                    temporalExcessDB: 10,
                    localProminenceDB: 9,
                    scoreDB: 14
                )
            ],
            persistentTones: [],
            vibrationPeaks: [
                VibrationPeak(
                    frequencyHz: 44,
                    amplitudeG: 0.01
                )
            ]
        )

        XCTAssertTrue(
            SoundVibrationCorrelationMath
                .matches(input: input)
                .isEmpty
        )
    }

    func testSoundVibrationPearsonCorrelationDetectsCoMovement() throws {
        let positive = try XCTUnwrap(
            SoundVibrationCorrelationMath
                .pearsonCorrelation(
                    x: [1, 2, 3, 4, 5],
                    y: [2, 4, 6, 8, 10]
                )
        )
        let negative = try XCTUnwrap(
            SoundVibrationCorrelationMath
                .pearsonCorrelation(
                    x: [1, 2, 3, 4, 5],
                    y: [10, 8, 6, 4, 2]
                )
        )

        XCTAssertEqual(
            positive,
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            negative,
            -1,
            accuracy: 0.0001
        )
    }

    func testSoundVibrationSummaryDetectsPersistentCoMovement() {
        let observations = (0..<8).map { index in
            let amplitude =
                Double(index + 1)

            return SoundVibrationObservation(
                capturedAtSeconds:
                    Double(index) * 0.5,
                matches: [
                    makeSoundVibrationMatch(
                        soundFrequencyHz:
                            40.0 +
                            Double(index % 2) * 0.2,
                        vibrationFrequencyHz:
                            40.5 +
                            Double(index % 2) * 0.2,
                        soundAmplitudeLinear:
                            amplitude,
                        vibrationAmplitudeG:
                            amplitude * 0.002,
                        persistent: true
                    )
                ]
            )
        }

        let summary =
            SoundVibrationCorrelationMath
                .summarize(
                    observations:
                        observations
                )

        XCTAssertEqual(
            summary.level,
            .coMoving
        )
        XCTAssertEqual(
            summary.primaryTrackObservationCount,
            8
        )
        XCTAssertEqual(
            summary.matchPresenceRatio,
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            summary.amplitudeCorrelation ?? 0,
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            summary.persistentSoundRatio,
            1,
            accuracy: 0.001
        )
    }

    func testSoundVibrationSummaryDoesNotMixDifferentFrequencyTracks() {
        var observations:
            [SoundVibrationObservation] = []

        for index in 0..<6 {
            observations.append(
                SoundVibrationObservation(
                    capturedAtSeconds:
                        Double(index) * 0.5,
                    matches: [
                        makeSoundVibrationMatch(
                            soundFrequencyHz: 40,
                            vibrationFrequencyHz: 40.5,
                            soundAmplitudeLinear:
                                Double(index + 1),
                            vibrationAmplitudeG:
                                Double(index + 1) *
                                0.002,
                            persistent: true
                        )
                    ]
                )
            )
        }

        for index in 0..<4 {
            observations.append(
                SoundVibrationObservation(
                    capturedAtSeconds:
                        Double(index + 6) * 0.5,
                    matches: [
                        makeSoundVibrationMatch(
                            soundFrequencyHz: 72,
                            vibrationFrequencyHz: 72.4,
                            soundAmplitudeLinear:
                                Double(index + 1),
                            vibrationAmplitudeG:
                                Double(index + 1) *
                                0.003,
                            persistent: false
                        )
                    ]
                )
            )
        }

        let summary =
            SoundVibrationCorrelationMath
                .summarize(
                    observations:
                        observations
                )

        XCTAssertEqual(
            summary.primaryTrackObservationCount,
            6
        )
        XCTAssertEqual(
            summary.primarySharedFrequencyHz ?? 0,
            40.25,
            accuracy: 0.5
        )
        XCTAssertEqual(
            summary.matchPresenceRatio,
            0.6,
            accuracy: 0.001
        )
    }

    func testSoundVibrationSummaryReportsNoConsistentSharedFrequency() {
        var observations: [SoundVibrationObservation] = []

        for index in 0..<4 {
            let match = makeSoundVibrationMatch(
                soundFrequencyHz: 35,
                vibrationFrequencyHz: 35.5,
                soundAmplitudeLinear:
                    Double(index + 1),
                vibrationAmplitudeG:
                    Double(index + 1) *
                    0.001,
                persistent: false
            )

            observations.append(
                SoundVibrationObservation(
                    capturedAtSeconds:
                        Double(index) * 0.5,
                    matches: [match]
                )
            )
        }

        for index in 4..<10 {
            observations.append(
                SoundVibrationObservation(
                    capturedAtSeconds:
                        Double(index) * 0.5,
                    matches: []
                )
            )
        }

        let summary: SoundVibrationCorrelationSummary =
            SoundVibrationCorrelationMath
                .summarize(
                    observations:
                        observations
                )

        XCTAssertEqual(
            summary.level,
            SoundVibrationCorrelationLevel
                .noConsistentMatch
        )
        XCTAssertEqual(
            summary.matchPresenceRatio,
            0.4,
            accuracy: 0.001
        )
    }

    private func makeSoundVibrationMatch(
        soundFrequencyHz: Double,
        vibrationFrequencyHz: Double,
        soundAmplitudeLinear: Double,
        vibrationAmplitudeG: Double,
        persistent: Bool
    ) -> SoundVibrationMatch {
        let tolerance = 6.0
        let delta = abs(
            soundFrequencyHz -
            vibrationFrequencyHz
        )

        return SoundVibrationMatch(
            soundFrequencyHz:
                soundFrequencyHz,
            vibrationFrequencyHz:
                vibrationFrequencyHz,
            frequencyDeltaHz: delta,
            toleranceHz: tolerance,
            frequencyAgreement:
                max(
                    0,
                    1.0 -
                    delta / tolerance
                ),
            soundMagnitudeDBFS:
                20.0 *
                log10(
                    max(
                        soundAmplitudeLinear,
                        1e-12
                    )
                ),
            soundAmplitudeLinear:
                soundAmplitudeLinear,
            vibrationAmplitudeG:
                vibrationAmplitudeG,
            soundIsPersistent:
                persistent,
            soundPersistenceConfidence:
                persistent ? 0.9 : 0
        )
    }

    func testMusicInterferenceNarrowToneIsCappedClear() {
        let score =
            MusicInterferenceMath.score(
                programLevelDBFS: -35,
                lowLevelDBFS: -60,
                occupiedBinRatio: 0.01,
                spectralFlatness: 0.001,
                spectralFlux: 0.9
            )

        XCTAssertLessThanOrEqual(
            score,
            0.25
        )
        XCTAssertEqual(
            MusicInterferenceMath.level(
                for: score
            ),
            .clear
        )
    }

    func testMusicInterferenceStaticBroadbandCannotBecomeLikely() {
        let score =
            MusicInterferenceMath.score(
                programLevelDBFS: -40,
                lowLevelDBFS: -50,
                occupiedBinRatio: 0.70,
                spectralFlatness: 0.45,
                spectralFlux: 0
            )

        XCTAssertLessThanOrEqual(
            score,
            0.58
        )
        XCTAssertNotEqual(
            MusicInterferenceMath.level(
                for: score
            ),
            .likely
        )
    }

    func testMusicInterferenceDynamicBroadbandCanBecomeLikely() {
        let score =
            MusicInterferenceMath.score(
                programLevelDBFS: -42,
                lowLevelDBFS: -60,
                occupiedBinRatio: 0.65,
                spectralFlatness: 0.40,
                spectralFlux: 0.70
            )

        XCTAssertGreaterThanOrEqual(
            score,
            MusicInterferenceMath
                .likelyThreshold
        )
        XCTAssertEqual(
            MusicInterferenceMath.level(
                for: score
            ),
            .likely
        )
    }

    func testMusicInterferenceDetectorKeepsRoadNoiseClear() {
        let detector =
            MusicInterferenceDetector(
                smoothingAlpha: 0.5
            )

        let bins = stride(
            from: 0.0,
            through: 5_000.0,
            by: 20.0
        ).map { frequency in
            let level: Double

            if
                frequency >= 30,
                frequency <= 200
            {
                level =
                    abs(frequency - 80) < 10
                    ? -28
                    : -55
            } else {
                level = -105
            }

            return SpectrumBin(
                frequencyHz: frequency,
                magnitudeDBFS: level
            )
        }

        let snapshot =
            detector.process(bins)

        XCTAssertEqual(
            snapshot.level,
            .clear
        )
        XCTAssertLessThan(
            snapshot.smoothedScore,
            MusicInterferenceMath
                .possibleThreshold
        )
        XCTAssertLessThan(
            snapshot.programBandLevelDBFS,
            -90
        )
    }

    func testMusicInterferenceDetectorKeepsSingleProgramToneClear() {
        let detector =
            MusicInterferenceDetector(
                smoothingAlpha: 0.5
            )

        func frame(
            toneLevel: Double
        ) -> [SpectrumBin] {
            stride(
                from: 0.0,
                through: 5_000.0,
                by: 20.0
            ).map { frequency in
                SpectrumBin(
                    frequencyHz: frequency,
                    magnitudeDBFS:
                        abs(
                            frequency -
                            1_000
                        ) < 1
                        ? toneLevel
                        : -105
                )
            }
        }

        _ = detector.process(
            frame(toneLevel: -35)
        )
        let snapshot =
            detector.process(
                frame(toneLevel: -15)
            )

        XCTAssertEqual(
            snapshot.level,
            .clear
        )
        XCTAssertLessThanOrEqual(
            snapshot.instantaneousScore,
            0.25
        )
        XCTAssertLessThan(
            snapshot.occupiedBinRatio,
            0.05
        )
    }

    func testMusicInterferenceDetectorFindsChangingBroadbandProgramAudio() {
        let detector =
            MusicInterferenceDetector(
                smoothingAlpha: 0.5
            )

        func frame(
            phase: Int
        ) -> [SpectrumBin] {
            stride(
                from: 0.0,
                through: 5_000.0,
                by: 20.0
            ).enumerated().map {
                index,
                frequency in
                let level: Double

                if
                    frequency >= 200,
                    frequency <= 4_000
                {
                    let alternating =
                        (
                            index + phase
                        ).isMultiple(of: 2)
                    level =
                        alternating
                        ? -42
                        : -58
                } else if
                    frequency >= 30,
                    frequency < 200
                {
                    level = -65
                } else {
                    level = -100
                }

                return SpectrumBin(
                    frequencyHz: frequency,
                    magnitudeDBFS: level
                )
            }
        }

        let first =
            detector.process(
                frame(phase: 0)
            )
        let second =
            detector.process(
                frame(phase: 1)
            )

        XCTAssertNotEqual(
            first.level,
            .likely
        )
        XCTAssertEqual(
            second.level,
            .likely
        )
        XCTAssertGreaterThan(
            second.occupiedBinRatio,
            0.5
        )
        XCTAssertGreaterThan(
            second.spectralFlux,
            0.5
        )
        XCTAssertGreaterThanOrEqual(
            second.smoothedScore,
            MusicInterferenceMath
                .likelyThreshold
        )
    }

    func testMusicInterferenceSpectralFluxIsZeroForIdenticalFrames() {
        let bins = [
            SpectrumBin(
                frequencyHz: 200,
                magnitudeDBFS: -50
            ),
            SpectrumBin(
                frequencyHz: 400,
                magnitudeDBFS: -45
            ),
            SpectrumBin(
                frequencyHz: 800,
                magnitudeDBFS: -55
            )
        ]

        XCTAssertEqual(
            MusicInterferenceMath
                .spectralFlux(
                    current: bins,
                    previous: bins,
                    range: 200...4_000
                ),
            0,
            accuracy: 0.0001
        )
    }

    func testOverallConfidenceWeightsSumToHundred() {
        let total =
            OverallConfidenceMath.toneWeight +
            OverallConfidenceMath.measurementQualityWeight +
            OverallConfidenceMath.measuredReductionWeight +
            OverallConfidenceMath.adaptiveStabilityWeight +
            OverallConfidenceMath.routeTimingWeight +
            OverallConfidenceMath.soundVibrationWeight +
            OverallConfidenceMath.interferenceSafetyWeight

        XCTAssertEqual(
            total,
            100,
            accuracy: 0.001
        )
    }

    func testOverallConfidenceIsInsufficientWithSparseEvidence() {
        let snapshot =
            OverallConfidenceMath.score(
                input:
                    makeOverallConfidenceInput()
            )

        XCTAssertEqual(
            snapshot.level,
            .insufficientEvidence
        )
        XCTAssertLessThan(
            snapshot.evidenceCoveragePercent,
            60
        )
    }

    func testOverallConfidenceStrongEvidenceProducesHighConfidence() {
        let snapshot =
            OverallConfidenceMath.score(
                input:
                    makeOverallConfidenceInput(
                        persistentToneUpdateCount: 20,
                        persistentTones: [
                            makeConfidenceTone(
                                confidence: 0.95,
                                persistent: true
                            )
                        ],
                        comparison:
                            makeConfidenceComparison(
                                reductionDB: 6,
                                standardDeviationDB: 0.35
                            ),
                        adaptiveEvidencePresent: true,
                        adaptiveIterations: 12,
                        adaptiveRollbacks: 1,
                        adaptiveTreatmentStandardDeviationDB: 0.4,
                        processingCallbackJitterMilliseconds: 0.4,
                        soundVibration:
                            makeConfidenceCorrelation(
                                level: .coMoving,
                                presence: 0.9,
                                correlation: 0.9
                            ),
                        musicInterference:
                            makeConfidenceMusic(
                                level: .clear,
                                score: 0.1
                            )
                    )
            )

        XCTAssertEqual(
            snapshot.level,
            .high
        )
        XCTAssertGreaterThanOrEqual(
            snapshot.scorePercent,
            80
        )
        XCTAssertEqual(
            snapshot.evidenceCoveragePercent,
            100,
            accuracy: 0.001
        )
    }

    func testOverallConfidenceMissingCorrelationReducesCoverageNotAvailableScores() {
        let snapshot =
            OverallConfidenceMath.score(
                input:
                    makeOverallConfidenceInput(
                        persistentToneUpdateCount: 20,
                        persistentTones: [
                            makeConfidenceTone(
                                confidence: 0.95,
                                persistent: true
                            )
                        ],
                        comparison:
                            makeConfidenceComparison(
                                reductionDB: 6,
                                standardDeviationDB: 0.35
                            ),
                        adaptiveEvidencePresent: true,
                        adaptiveIterations: 12,
                        adaptiveRollbacks: 1,
                        adaptiveTreatmentStandardDeviationDB: 0.4,
                        processingCallbackJitterMilliseconds: 0.4,
                        musicInterference:
                            makeConfidenceMusic(
                                level: .clear,
                                score: 0.1
                            )
                    )
            )

        XCTAssertEqual(
            snapshot.evidenceCoveragePercent,
            88,
            accuracy: 0.001
        )
        XCTAssertTrue(
            snapshot.components
                .contains {
                    $0.id == .soundVibration &&
                    $0.score == nil
                }
        )
    }

    func testOverallConfidenceClippingCapsScoreAtTwenty() {
        let snapshot =
            OverallConfidenceMath.score(
                input:
                    makeStrongConfidenceInput(
                        microphoneIsClipping: true
                    )
            )

        XCTAssertLessThanOrEqual(
            snapshot.scorePercent,
            20
        )
        XCTAssertEqual(
            snapshot.level,
            .low
        )
        XCTAssertTrue(
            snapshot.limitingFactors
                .contains(
                    "Microphone clipping is active."
                )
        )
    }

    func testOverallConfidenceAmplificationCapsScoreAtTwenty() {
        let snapshot =
            OverallConfidenceMath.score(
                input:
                    makeStrongConfidenceInput(
                        comparison:
                            makeConfidenceComparison(
                                reductionDB: -3,
                                standardDeviationDB: 0.35
                            )
                    )
            )

        XCTAssertLessThanOrEqual(
            snapshot.scorePercent,
            20
        )
        XCTAssertTrue(
            snapshot.limitingFactors
                .contains(
                    "Treatment amplified the target by 3 dB or more."
                )
        )
    }

    func testOverallConfidenceAdaptiveFailSafeCapsScoreAtThirtyFive() {
        let snapshot =
            OverallConfidenceMath.score(
                input:
                    makeStrongConfidenceInput(
                        adaptiveFailed: true
                    )
            )

        XCTAssertLessThanOrEqual(
            snapshot.scorePercent,
            35
        )
        XCTAssertTrue(
            snapshot.limitingFactors
                .contains(
                    "Adaptive controller entered a fail-safe state."
                )
        )
    }

    func testOverallConfidenceUnstableBluetoothCapsScoreAtFiftyFive() {
        let snapshot =
            OverallConfidenceMath.score(
                input:
                    makeStrongConfidenceInput(
                        bluetoothActive: true,
                        bluetoothJitter:
                            makeConfidenceBluetoothJitter(
                                stability: .unstable
                            )
                    )
            )

        XCTAssertLessThanOrEqual(
            snapshot.scorePercent,
            55
        )
        XCTAssertTrue(
            snapshot.limitingFactors
                .contains(
                    "Bluetooth timing was unstable during the live jitter run."
                )
        )
    }

    func testOverallConfidenceLikelyMusicCapsScoreAtSixty() {
        let snapshot =
            OverallConfidenceMath.score(
                input:
                    makeStrongConfidenceInput(
                        musicInterference:
                            makeConfidenceMusic(
                                level: .likely,
                                score: 0.85
                            )
                    )
            )

        XCTAssertLessThanOrEqual(
            snapshot.scorePercent,
            60
        )
        XCTAssertTrue(
            snapshot.limitingFactors
                .contains(
                    "Likely program-audio interference is contaminating the microphone spectrum."
                )
        )
    }

    private func makeStrongConfidenceInput(
        comparison: BeforeAfterComparison? = nil,
        adaptiveFailed: Bool = false,
        bluetoothActive: Bool = false,
        bluetoothJitter: BluetoothJitterSnapshot? = nil,
        musicInterference: MusicInterferenceSnapshot? = nil,
        microphoneIsClipping: Bool = false
    ) -> OverallConfidenceInput {
        makeOverallConfidenceInput(
            persistentToneUpdateCount: 20,
            persistentTones: [
                makeConfidenceTone(
                    confidence: 0.95,
                    persistent: true
                )
            ],
            comparison:
                comparison ??
                makeConfidenceComparison(
                    reductionDB: 6,
                    standardDeviationDB: 0.35
                ),
            adaptiveEvidencePresent: true,
            adaptiveFailed: adaptiveFailed,
            adaptiveIterations: 12,
            adaptiveRollbacks: 1,
            adaptiveTreatmentStandardDeviationDB: 0.4,
            processingCallbackJitterMilliseconds: 0.4,
            bluetoothActive: bluetoothActive,
            bluetoothJitter: bluetoothJitter,
            soundVibration:
                makeConfidenceCorrelation(
                    level: .coMoving,
                    presence: 0.9,
                    correlation: 0.9
                ),
            musicInterference:
                musicInterference ??
                makeConfidenceMusic(
                    level: .clear,
                    score: 0.1
                ),
            microphoneIsClipping:
                microphoneIsClipping
        )
    }

    private func makeOverallConfidenceInput(
        persistentToneUpdateCount: UInt64 = 0,
        persistentTones: [PersistentTone] = [],
        comparison: BeforeAfterComparison? = nil,
        adaptiveEvidencePresent: Bool = false,
        adaptiveFailed: Bool = false,
        adaptiveIterations: Int = 0,
        adaptiveRollbacks: Int = 0,
        adaptiveStabilityHoldCount: Int = 0,
        adaptivePhaseReversalStreak: Int = 0,
        adaptiveAmplitudeReversalStreak: Int = 0,
        adaptiveTreatmentStandardDeviationDB: Double? = nil,
        processingCallbackJitterMilliseconds: Double? = nil,
        bluetoothActive: Bool = false,
        bluetoothJitter: BluetoothJitterSnapshot? = nil,
        soundVibration: SoundVibrationCorrelationSummary = .empty,
        musicInterference: MusicInterferenceSnapshot = .empty,
        microphoneIsClipping: Bool = false
    ) -> OverallConfidenceInput {
        OverallConfidenceInput(
            persistentToneUpdateCount:
                persistentToneUpdateCount,
            persistentTones:
                persistentTones,
            comparison:
                comparison,
            adaptiveEvidencePresent:
                adaptiveEvidencePresent,
            adaptiveFailed:
                adaptiveFailed,
            adaptiveIterations:
                adaptiveIterations,
            adaptiveRollbacks:
                adaptiveRollbacks,
            adaptiveStabilityHoldCount:
                adaptiveStabilityHoldCount,
            adaptivePhaseReversalStreak:
                adaptivePhaseReversalStreak,
            adaptiveAmplitudeReversalStreak:
                adaptiveAmplitudeReversalStreak,
            adaptiveTreatmentStandardDeviationDB:
                adaptiveTreatmentStandardDeviationDB,
            processingCallbackJitterMilliseconds:
                processingCallbackJitterMilliseconds,
            bluetoothActive:
                bluetoothActive,
            bluetoothJitter:
                bluetoothJitter,
            soundVibration:
                soundVibration,
            musicInterference:
                musicInterference,
            microphoneIsClipping:
                microphoneIsClipping
        )
    }

    private func makeConfidenceTone(
        confidence: Double,
        persistent: Bool
    ) -> PersistentTone {
        PersistentTone(
            trackID: 1,
            frequencyHz: 80,
            durationSeconds: 5,
            observationCount: 20,
            presenceRatio: 0.9,
            frequencyStdDevHz: 0.8,
            averageLocalProminenceDB: 8,
            averageTemporalExcessDB: 7,
            confidence: confidence,
            confidenceLevel:
                confidence >= 0.75
                ? .high
                : .medium,
            isPersistent: persistent
        )
    }

    private func makeConfidenceComparison(
        reductionDB: Double,
        standardDeviationDB: Double
    ) -> BeforeAfterComparison {
        let baseline =
            TargetEnergyWindowSummary(
                condition:
                    MeasurementCondition(
                        targetFrequencyHz: 80,
                        phaseDegrees: 0,
                        outputPercent: 30,
                        toneAudible: false
                    ),
                sampleCount: 20,
                durationSeconds: 1.9,
                averageBandEnergyDBFS: -30,
                minimumBandEnergyDBFS: -31,
                maximumBandEnergyDBFS: -29,
                averageCenterLevelDBFS: -33,
                standardDeviationDB:
                    standardDeviationDB
            )
        let treatmentEnergy =
            baseline.averageBandEnergyDBFS -
            reductionDB
        let treatment =
            TargetEnergyWindowSummary(
                condition:
                    MeasurementCondition(
                        targetFrequencyHz: 80,
                        phaseDegrees: 140,
                        outputPercent: 30,
                        toneAudible: true
                    ),
                sampleCount: 20,
                durationSeconds: 1.9,
                averageBandEnergyDBFS:
                    treatmentEnergy,
                minimumBandEnergyDBFS:
                    treatmentEnergy - 1,
                maximumBandEnergyDBFS:
                    treatmentEnergy + 1,
                averageCenterLevelDBFS:
                    treatmentEnergy - 3,
                standardDeviationDB:
                    standardDeviationDB
            )

        return BeforeAfterComparison(
            baseline: baseline,
            treatment: treatment,
            treatmentMinusBaselineDB:
                -reductionDB,
            measuredReductionDB:
                reductionDB
        )
    }

    private func makeConfidenceCorrelation(
        level: SoundVibrationCorrelationLevel,
        presence: Double,
        correlation: Double?
    ) -> SoundVibrationCorrelationSummary {
        SoundVibrationCorrelationSummary(
            opportunityCount: 20,
            matchedObservationCount: 18,
            primaryTrackObservationCount:
                Int(
                    (
                        presence *
                        20
                    ).rounded()
                ),
            primarySharedFrequencyHz: 80,
            matchPresenceRatio: presence,
            averageFrequencyDeltaHz: 0.7,
            averageFrequencyAgreement: 0.9,
            amplitudeCorrelation:
                correlation,
            persistentSoundRatio: 0.9,
            averageSoundPersistenceConfidence:
                0.9,
            level: level
        )
    }

    private func makeConfidenceMusic(
        level: MusicInterferenceLevel,
        score: Double
    ) -> MusicInterferenceSnapshot {
        MusicInterferenceSnapshot(
            level: level,
            instantaneousScore: score,
            smoothedScore: score,
            programBandLevelDBFS: -50,
            lowBandLevelDBFS: -45,
            programToLowRatioDB: -5,
            occupiedBinRatio: 0.2,
            spectralFlatness: 0.1,
            spectralFlux: 0.2,
            analyzedBinCount: 300,
            updateCount: 20
        )
    }

    private func makeConfidenceBluetoothJitter(
        stability: BluetoothTimingStability
    ) -> BluetoothJitterSnapshot {
        BluetoothJitterSnapshot(
            sampleCount: 120,
            elapsedSeconds: 30,
            profile: .a2dp,
            stability: stability,
            callbackMeanMilliseconds: 21,
            callbackJitterMilliseconds:
                stability == .unstable
                ? 4
                : 0.5,
            callbackRangeMilliseconds: 2,
            spectrumCenterAgeMeanMilliseconds: 60,
            spectrumCenterAgeJitterMilliseconds:
                stability == .unstable
                ? 18
                : 2,
            spectrumCenterAgeRangeMilliseconds: 8,
            outputLatencyMeanMilliseconds: 120,
            outputLatencyJitterMilliseconds: 2,
            outputLatencyRangeMilliseconds: 6,
            ioBufferChangeCount:
                stability == .unstable
                ? 1
                : 0,
            sampleRateChangeCount: 0,
            routeRevisionChangeCount: 0,
            profileChangeCount: 0
        )
    }

    func testCalibrationAverageDBUsesLinearPower() throws {
        let average = try XCTUnwrap(
            CalibrationMath.averageDBFromPower(
                [-30, -30]
            )
        )

        XCTAssertEqual(
            average,
            -30,
            accuracy: 0.001
        )

        let mixed = try XCTUnwrap(
            CalibrationMath.averageDBFromPower(
                [-20, -40]
            )
        )

        XCTAssertGreaterThan(
            mixed,
            -24
        )
        XCTAssertLessThan(
            mixed,
            -22
        )
    }

    func testCalibrationExternalSPLOffsetAndRouteGuard() {
        let profile =
            makeCalibrationProfile(
                routeSignature: "route-A",
                sampleRate: 48_000,
                externalReferenceSPLDB: 72,
                approximateSPLOffsetDB: 112
            )

        XCTAssertEqual(
            try XCTUnwrap(
                CalibrationMath.approximateSPLDB(
                    rmsDBFS: -38,
                    profile: profile,
                    currentRouteSignature: "route-A"
                )
            ),
            74,
            accuracy: 0.001
        )

        XCTAssertNil(
            CalibrationMath.approximateSPLDB(
                rmsDBFS: -38,
                profile: profile,
                currentRouteSignature: "route-B"
            )
        )
    }

    func testCalibrationRouteMatchRequiresSignatureAndSampleRate() {
        let profile =
            makeCalibrationProfile(
                routeSignature: "route-A",
                sampleRate: 48_000
            )

        XCTAssertTrue(
            CalibrationMath.routeMatches(
                profile: profile,
                routeSignature: "route-A",
                sampleRate: 48_000.5
            )
        )

        XCTAssertFalse(
            CalibrationMath.routeMatches(
                profile: profile,
                routeSignature: "route-B",
                sampleRate: 48_000
            )
        )

        XCTAssertFalse(
            CalibrationMath.routeMatches(
                profile: profile,
                routeSignature: "route-A",
                sampleRate: 44_100
            )
        )
    }

    func testCalibrationRejectsInvalidExternalSPL() {
        XCTAssertFalse(
            CalibrationMath
                .isValidExternalReferenceSPLDB(
                    10
                )
        )
        XCTAssertTrue(
            CalibrationMath
                .isValidExternalReferenceSPLDB(
                    72
                )
        )
        XCTAssertFalse(
            CalibrationMath
                .isValidExternalReferenceSPLDB(
                    150
                )
        )
    }

    @MainActor
    func testCalibrationModelPersistsProfiles() throws {
        let url =
            FileManager.default
                .temporaryDirectory
                .appendingPathComponent(
                    "quietdrive-calibration-\(UUID().uuidString).json"
                )
        defer {
            try? FileManager.default
                .removeItem(at: url)
        }

        let model =
            CalibrationModel(
                storageURL: url
            )
        let profile =
            makeCalibrationProfile(
                routeSignature: "route-A",
                sampleRate: 48_000,
                externalReferenceSPLDB: 70,
                approximateSPLOffsetDB: 110
            )

        model.save(profile)

        XCTAssertEqual(
            model.profiles,
            [profile]
        )

        let reloaded =
            CalibrationModel(
                storageURL: url
            )

        XCTAssertEqual(
            reloaded.profiles,
            [profile]
        )
        XCTAssertEqual(
            reloaded.latestMatchingProfile(
                routeSignature: "route-A",
                sampleRate: 48_000
            ),
            profile
        )

        reloaded.delete(
            id: profile.id
        )

        let afterDelete =
            CalibrationModel(
                storageURL: url
            )
        XCTAssertTrue(
            afterDelete.profiles.isEmpty
        )
    }

    private func makeCalibrationProfile(
        routeSignature: String,
        sampleRate: Double,
        externalReferenceSPLDB: Double? = nil,
        approximateSPLOffsetDB: Double? = nil
    ) -> CalibrationProfile {
        CalibrationProfile(
            id: UUID(),
            capturedAt: Date(
                timeIntervalSince1970: 1
            ),
            routeSignature:
                routeSignature,
            routeFamily: .builtIn,
            routeRevision: 1,
            inputRoute: "Mic",
            outputRoute: "Speaker",
            sampleRate: sampleRate,
            ioBufferMilliseconds: 5,
            inputLatencyMilliseconds: 2,
            outputLatencyMilliseconds: 3,
            sampleCount: 50,
            durationSeconds: 4.9,
            microphoneRMSDBFS: -40,
            microphoneRMSStandardDeviationDB: 0.5,
            lowFrequencyFloorDBFS: -65,
            widebandFloorDBFS: -70,
            targetFrequencyHz: 80,
            targetBandEnergyDBFS: -48,
            targetBandStandardDeviationDB: 0.7,
            accelerationBiasXG: 0.01,
            accelerationBiasYG: 0.02,
            accelerationBiasZG: 0.99,
            dynamicVibrationRMSG: 0.002,
            accelerometerObservedRateHz: 198,
            accelerometerIntervalJitterMilliseconds: 0.2,
            callbackJitterMilliseconds: 0.4,
            spectrumCenterAgeMilliseconds: 55,
            maximumMusicInterferenceScore: 0.1,
            externalReferenceSPLDB:
                externalReferenceSPLDB,
            approximateSPLOffsetDB:
                approximateSPLOffsetDB
        )
    }

    @MainActor
    func testStructuredLogSessionStartIsIdempotentAndSequenced() {
        let sessionID =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000034"
            )!
        let model =
            StructuredLogModel(
                storageURL: nil,
                sessionID: sessionID
            )

        model.startSession(
            text: [
                "app_build": "3.3"
            ]
        )
        model.startSession()

        _ = model.record(
            kind: .captureStarted
        )

        XCTAssertEqual(
            model.events.count,
            2
        )
        XCTAssertEqual(
            model.events[0].kind,
            .sessionStarted
        )
        XCTAssertEqual(
            model.events[0].sequence,
            1
        )
        XCTAssertEqual(
            model.events[1].sequence,
            2
        )
        XCTAssertEqual(
            model.events[0].sessionID,
            sessionID
        )
        XCTAssertEqual(
            model.currentSessionEvents.count,
            2
        )
    }

    @MainActor
    func testStructuredLogPersistsMetricsFlagsReferencesAndContext() throws {
        let url =
            FileManager.default
                .temporaryDirectory
                .appendingPathComponent(
                    "quietdrive-structured-log-\(UUID().uuidString).json"
                )
        defer {
            try? FileManager.default
                .removeItem(at: url)
        }

        let sessionID =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000035"
            )!
        let calibrationID =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000036"
            )!
        let model =
            StructuredLogModel(
                storageURL: url,
                sessionID: sessionID
            )
        let context =
            StructuredLogContext(
                routeSignature: "route-A",
                routeRevision: 4,
                calibrationProfileID:
                    calibrationID,
                targetFrequencyHz: 80,
                phaseDegrees: 140,
                outputPercent: 30,
                confidenceScorePercent: 82,
                evidenceCoveragePercent: 90,
                confidenceLevel:
                    "High confidence"
            )

        let event =
            model.record(
                kind: .comparisonSaved,
                context: context,
                metrics: [
                    "measured_reduction_db":
                        4.5
                ],
                text: [
                    "input_route":
                        "Built-in microphone"
                ],
                flags: [
                    "success": true
                ],
                references: [
                    "experiment_record_id":
                        "record-1"
                ],
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            34
                    )
            )

        XCTAssertEqual(
            event.schemaVersion,
            StructuredLogEvent
                .currentSchemaVersion
        )

        let reloaded =
            StructuredLogModel(
                storageURL: url,
                sessionID: UUID()
            )

        XCTAssertEqual(
            reloaded.events,
            [event]
        )
        XCTAssertEqual(
            reloaded.events.first?
                .context
                .calibrationProfileID,
            calibrationID
        )
        XCTAssertEqual(
            reloaded.events.first?
                .metrics[
                    "measured_reduction_db"
                ],
            4.5
        )
        XCTAssertEqual(
            reloaded.events.first?
                .flags["success"],
            true
        )
        XCTAssertEqual(
            reloaded.events.first?
                .references[
                    "experiment_record_id"
                ],
            "record-1"
        )
    }

    @MainActor
    func testStructuredLogSeparatesSessionsAcrossLaunches() throws {
        let url =
            FileManager.default
                .temporaryDirectory
                .appendingPathComponent(
                    "quietdrive-structured-sessions-\(UUID().uuidString).json"
                )
        defer {
            try? FileManager.default
                .removeItem(at: url)
        }

        let first =
            StructuredLogModel(
                storageURL: url,
                sessionID:
                    UUID(
                        uuidString:
                            "00000000-0000-0000-0000-000000000037"
                    )!
            )
        first.startSession()
        _ = first.record(
            kind: .captureStarted
        )

        let second =
            StructuredLogModel(
                storageURL: url,
                sessionID:
                    UUID(
                        uuidString:
                            "00000000-0000-0000-0000-000000000038"
                    )!
            )
        second.startSession()

        XCTAssertEqual(
            second.events.count,
            3
        )
        XCTAssertEqual(
            second.distinctSessionCount,
            2
        )
        XCTAssertEqual(
            second.currentSessionEvents.count,
            1
        )
        XCTAssertEqual(
            second.currentSessionEvents
                .first?
                .sequence,
            1
        )
    }

    @MainActor
    func testStructuredLogRetentionPrunesOldestEvents() {
        let model =
            StructuredLogModel(
                storageURL: nil,
                sessionID:
                    UUID(
                        uuidString:
                            "00000000-0000-0000-0000-000000000039"
                    )!
            )

        for index in 0..<(StructuredLogModel.maximumEventCount + 5) {
            _ = model.record(
                kind: .confidenceSnapshot,
                metrics: [
                    "index":
                        Double(index)
                ],
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            Double(index)
                    )
            )
        }

        XCTAssertEqual(
            model.events.count,
            StructuredLogModel
                .maximumEventCount
        )
        XCTAssertEqual(
            model.events.first?
                .metrics["index"],
            5
        )
        XCTAssertEqual(
            model.events.last?
                .metrics["index"],
            Double(
                StructuredLogModel
                    .maximumEventCount +
                4
            )
        )
    }

    @MainActor
    func testStructuredLogClearAllowsFreshSessionStartSequence() {
        let model =
            StructuredLogModel(
                storageURL: nil
            )

        model.startSession()
        _ = model.record(
            kind: .toneStarted
        )
        model.clearAll()
        model.startSession()

        XCTAssertEqual(
            model.events.count,
            1
        )
        XCTAssertEqual(
            model.events.first?.kind,
            .sessionStarted
        )
        XCTAssertEqual(
            model.events.first?.sequence,
            1
        )
    }

    func testStructuredLogJSONExportRoundTripsTypedSchema() throws {
        let eventID =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000040"
            )!
        let sessionID =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000041"
            )!
        let calibrationID =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000042"
            )!

        let event =
            StructuredLogEvent(
                id: eventID,
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            100
                    ),
                sessionID: sessionID,
                sequence: 7,
                kind: .comparisonSaved,
                context:
                    StructuredLogContext(
                        routeSignature:
                            "route-export",
                        routeRevision: 9,
                        calibrationProfileID:
                            calibrationID,
                        targetFrequencyHz: 82,
                        phaseDegrees: 145,
                        outputPercent: 24,
                        confidenceScorePercent:
                            88,
                        evidenceCoveragePercent:
                            91,
                        confidenceLevel:
                            "High confidence"
                    ),
                metrics: [
                    "measured_reduction_db":
                        4.25
                ],
                text: [
                    "input_route":
                        "Built-in microphone"
                ],
                flags: [
                    "success": true
                ],
                references: [
                    "experiment_record_id":
                        "record-export"
                ]
            )

        let data = try
            StructuredLogExporter
                .data(
                    for: .json,
                    events: [event]
                )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy =
            .iso8601

        let decoded = try
            decoder.decode(
                [StructuredLogEvent].self,
                from: data
            )

        XCTAssertEqual(
            decoded,
            [event]
        )
    }

    func testStructuredLogCSVExportFlattensDynamicFieldsDeterministically() {
        let sessionID =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000043"
            )!

        let first =
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            200
                    ),
                sessionID: sessionID,
                sequence: 1,
                kind: .confidenceSnapshot,
                metrics: [
                    "zeta": 2,
                    "alpha": 1
                ],
                text: [
                    "note": "first"
                ],
                flags: [
                    "ok": true
                ],
                references: [
                    "record": "one"
                ]
            )

        let second =
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            201
                    ),
                sessionID: sessionID,
                sequence: 2,
                kind: .toneStopped,
                metrics: [
                    "alpha": 3
                ],
                text: [
                    "note": "second"
                ],
                flags: [
                    "ok": false
                ],
                references: [
                    "record": "two"
                ]
            )

        let csv =
            StructuredLogExporter
                .csvString(
                    events: [
                        first,
                        second
                    ]
                )
        let header =
            csv.components(
                separatedBy: "\r\n"
            )[0]

        XCTAssertTrue(
            header.hasSuffix(
                "metrics.alpha,metrics.zeta,text.note,flags.ok,references.record"
            )
        )
        XCTAssertTrue(
            csv.contains(
                ",1,2,first,true,one\r\n"
            )
        )
        XCTAssertTrue(
            csv.contains(
                ",3,,second,false,two\r\n"
            )
        )
    }

    func testStructuredLogCSVExportQuotesCommasQuotesAndNewlines() {
        let event =
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            300
                    ),
                sessionID:
                    UUID(
                        uuidString:
                            "00000000-0000-0000-0000-000000000044"
                    )!,
                sequence: 1,
                kind: .workflowFailed,
                text: [
                    "message":
                        "route, \"A\"\nnext"
                ]
            )

        let csv =
            StructuredLogExporter
                .csvString(
                    events: [event]
                )

        XCTAssertTrue(
            csv.contains(
                "\"route, \"\"A\"\"\nnext\""
            )
        )
    }

    func testStructuredLogExportScopeAndFilename() {
        let firstSession =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000045"
            )!
        let secondSession =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000046"
            )!
        let events = [
            StructuredLogEvent(
                sessionID: firstSession,
                sequence: 1,
                kind: .sessionStarted
            ),
            StructuredLogEvent(
                sessionID: secondSession,
                sequence: 1,
                kind: .sessionStarted
            )
        ]

        let current =
            StructuredLogExporter
                .selectedEvents(
                    from: events,
                    scope:
                        .currentSession,
                    currentSessionID:
                        secondSession
                )

        XCTAssertEqual(
            current.count,
            1
        )
        XCTAssertEqual(
            current.first?
                .sessionID,
            secondSession
        )
        XCTAssertEqual(
            StructuredLogExporter
                .selectedEvents(
                    from: events,
                    scope:
                        .allEvents,
                    currentSessionID:
                        secondSession
                )
                .count,
            2
        )
        XCTAssertEqual(
            StructuredLogExporter
                .suggestedFilename(
                    format: .csv,
                    scope:
                        .currentSession,
                    exportedAt:
                        Date(
                            timeIntervalSince1970:
                                0
                        )
                ),
            "quietdrive-structured-events-session-19700101T000000Z.csv"
        )
    }

    func testTestDashboardAggregatesSavedEvidenceAndWorkflows() {
        let firstSession =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000047"
            )!
        let secondSession =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000048"
            )!

        func context(
            route: String,
            frequency: Double,
            confidence: Double,
            coverage: Double,
            level: String
        ) -> StructuredLogContext {
            StructuredLogContext(
                routeSignature: route,
                routeRevision: 1,
                calibrationProfileID: nil,
                targetFrequencyHz:
                    frequency,
                phaseDegrees: 120,
                outputPercent: 20,
                confidenceScorePercent:
                    confidence,
                evidenceCoveragePercent:
                    coverage,
                confidenceLevel:
                    level
            )
        }

        let events = [
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            1
                    ),
                sessionID: firstSession,
                sequence: 1,
                kind: .sessionStarted,
                context:
                    context(
                        route: "route-A",
                        frequency: 80,
                        confidence: 70,
                        coverage: 80,
                        level:
                            "Moderate confidence"
                    ),
                text: [
                    "app_build": "3.5"
                ]
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            2
                    ),
                sessionID: firstSession,
                sequence: 2,
                kind: .calibrationCompleted,
                context:
                    context(
                        route: "route-A",
                        frequency: 80,
                        confidence: 70,
                        coverage: 80,
                        level:
                            "Moderate confidence"
                    )
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            3
                    ),
                sessionID: firstSession,
                sequence: 3,
                kind: .comparisonSaved,
                context:
                    context(
                        route: "route-A",
                        frequency: 80,
                        confidence: 75,
                        coverage: 85,
                        level:
                            "Moderate confidence"
                    ),
                metrics: [
                    "measured_reduction_db":
                        3
                ]
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            4
                    ),
                sessionID: firstSession,
                sequence: 4,
                kind: .workflowFailed,
                context:
                    context(
                        route: "route-A",
                        frequency: 80,
                        confidence: 75,
                        coverage: 85,
                        level:
                            "Moderate confidence"
                    ),
                text: [
                    "workflow":
                        "phase_sweep"
                ]
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            5
                    ),
                sessionID: firstSession,
                sequence: 5,
                kind: .safetyMute,
                context:
                    context(
                        route: "route-A",
                        frequency: 80,
                        confidence: 75,
                        coverage: 85,
                        level:
                            "Moderate confidence"
                    )
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            6
                    ),
                sessionID: firstSession,
                sequence: 6,
                kind: .confidenceSnapshot,
                context:
                    context(
                        route: "route-A",
                        frequency: 80,
                        confidence: 75,
                        coverage: 85,
                        level:
                            "Moderate confidence"
                    ),
                metrics: [
                    "score_percent": 75
                ]
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            10
                    ),
                sessionID: secondSession,
                sequence: 1,
                kind: .sessionStarted,
                context:
                    context(
                        route: "route-B",
                        frequency: 100,
                        confidence: 55,
                        coverage: 65,
                        level:
                            "Low confidence"
                    ),
                text: [
                    "app_build": "3.6"
                ]
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            11
                    ),
                sessionID: secondSession,
                sequence: 2,
                kind: .routeTestCaptured,
                context:
                    context(
                        route: "route-B",
                        frequency: 100,
                        confidence: 55,
                        coverage: 65,
                        level:
                            "Low confidence"
                    )
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            12
                    ),
                sessionID: secondSession,
                sequence: 3,
                kind: .comparisonSaved,
                context:
                    context(
                        route: "route-B",
                        frequency: 100,
                        confidence: 60,
                        coverage: 70,
                        level:
                            "Low confidence"
                    ),
                metrics: [
                    "measured_reduction_db":
                        -1
                ]
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            13
                    ),
                sessionID: secondSession,
                sequence: 4,
                kind: .phaseSweepCompleted,
                context:
                    context(
                        route: "route-B",
                        frequency: 100,
                        confidence: 60,
                        coverage: 70,
                        level:
                            "Low confidence"
                    )
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            14
                    ),
                sessionID: secondSession,
                sequence: 5,
                kind: .adaptiveFailed,
                context:
                    context(
                        route: "route-B",
                        frequency: 100,
                        confidence: 60,
                        coverage: 70,
                        level:
                            "Low confidence"
                    )
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            15
                    ),
                sessionID: secondSession,
                sequence: 6,
                kind: .confidenceSnapshot,
                context:
                    context(
                        route: "route-B",
                        frequency: 100,
                        confidence: 60,
                        coverage: 70,
                        level:
                            "Low confidence"
                    ),
                metrics: [
                    "score_percent": 60
                ]
            )
        ]

        let dashboard =
            TestDashboardAnalytics
                .snapshot(
                    events: events,
                    scope: .allSaved,
                    currentSessionID:
                        secondSession
                )

        XCTAssertEqual(
            dashboard.eventCount,
            12
        )
        XCTAssertEqual(
            dashboard.sessionCount,
            2
        )
        XCTAssertEqual(
            dashboard.distinctRouteCount,
            2
        )
        XCTAssertEqual(
            dashboard.distinctFrequencyCount,
            2
        )
        XCTAssertEqual(
            dashboard.comparisonCount,
            2
        )
        XCTAssertEqual(
            dashboard.positiveReductionCount,
            1
        )
        XCTAssertEqual(
            dashboard.averageReductionDB ??
                .nan,
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            dashboard.bestReductionDB ??
                .nan,
            3,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            dashboard.confidenceSnapshotCount,
            2
        )
        XCTAssertEqual(
            dashboard.averageConfidenceSnapshotScorePercent ??
                .nan,
            67.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            dashboard.latestConfidenceScorePercent,
            60
        )
        XCTAssertEqual(
            dashboard.latestEvidenceCoveragePercent,
            70
        )
        XCTAssertEqual(
            dashboard.failureCount,
            2
        )
        XCTAssertEqual(
            dashboard.safetyMuteCount,
            1
        )

        let phase =
            dashboard
                .workflowSummaries
                .first {
                    $0.id ==
                        "phase_sweep"
                }

        XCTAssertEqual(
            phase?.completedCount,
            1
        )
        XCTAssertEqual(
            phase?.failedCount,
            1
        )

        let adaptive =
            dashboard
                .workflowSummaries
                .first {
                    $0.id ==
                        "adaptive"
                }

        XCTAssertEqual(
            adaptive?.failedCount,
            1
        )
    }

    func testTestDashboardCurrentSessionScopeFiltersEvidence() {
        let firstSession =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000049"
            )!
        let currentSession =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000050"
            )!

        let events = [
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            1
                    ),
                sessionID: firstSession,
                sequence: 1,
                kind: .comparisonSaved,
                metrics: [
                    "measured_reduction_db":
                        5
                ]
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            2
                    ),
                sessionID: currentSession,
                sequence: 1,
                kind: .sessionStarted
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            3
                    ),
                sessionID: currentSession,
                sequence: 2,
                kind: .comparisonSaved,
                metrics: [
                    "measured_reduction_db":
                        2
                ]
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            4
                    ),
                sessionID: currentSession,
                sequence: 3,
                kind: .workflowFailed,
                text: [
                    "workflow":
                        "amplitude_search"
                ]
            )
        ]

        let dashboard =
            TestDashboardAnalytics
                .snapshot(
                    events: events,
                    scope:
                        .currentSession,
                    currentSessionID:
                        currentSession
                )

        XCTAssertEqual(
            dashboard.eventCount,
            3
        )
        XCTAssertEqual(
            dashboard.sessionCount,
            1
        )
        XCTAssertEqual(
            dashboard.comparisonCount,
            1
        )
        XCTAssertEqual(
            dashboard.bestReductionDB,
            2
        )
        XCTAssertEqual(
            dashboard.failureCount,
            1
        )
        XCTAssertEqual(
            dashboard.recentSessions.count,
            1
        )
        XCTAssertTrue(
            dashboard
                .recentSessions[0]
                .isCurrentSession
        )
    }

    func testTestDashboardBuildsRecentSessionSummariesNewestFirst() {
        let olderSession =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000051"
            )!
        let currentSession =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000052"
            )!

        let events = [
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            10
                    ),
                sessionID: olderSession,
                sequence: 1,
                kind: .sessionStarted,
                text: [
                    "app_build": "3.5"
                ]
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            12
                    ),
                sessionID: olderSession,
                sequence: 2,
                kind: .toneStopped
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            20
                    ),
                sessionID: currentSession,
                sequence: 1,
                kind: .sessionStarted,
                text: [
                    "app_build": "3.6"
                ]
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            25
                    ),
                sessionID: currentSession,
                sequence: 2,
                kind: .comparisonSaved,
                metrics: [
                    "measured_reduction_db":
                        4
                ]
            )
        ]

        let dashboard =
            TestDashboardAnalytics
                .snapshot(
                    events: events,
                    scope: .allSaved,
                    currentSessionID:
                        currentSession
                )

        XCTAssertEqual(
            dashboard.recentSessions.count,
            2
        )
        XCTAssertEqual(
            dashboard.recentSessions[0].id,
            currentSession
        )
        XCTAssertEqual(
            dashboard.recentSessions[0].appBuild,
            "3.6"
        )
        XCTAssertEqual(
            dashboard.recentSessions[0].durationSeconds,
            5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            dashboard.recentSessions[0].bestReductionDB,
            4
        )
        XCTAssertEqual(
            dashboard.recentSessions[1].id,
            olderSession
        )
        XCTAssertEqual(
            dashboard.recentSessions[1].appBuild,
            "3.5"
        )
    }

    func testRepeatabilityGroupsNormalizedConditionsAcrossSessions() {
        let sessions = [
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000053"
            )!,
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000054"
            )!,
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000055"
            )!
        ]

        func context(
            frequency: Double,
            phase: Double,
            output: Double
        ) -> StructuredLogContext {
            StructuredLogContext(
                routeSignature:
                    "route-repeat",
                routeRevision: 1,
                calibrationProfileID: nil,
                targetFrequencyHz:
                    frequency,
                phaseDegrees:
                    phase,
                outputPercent:
                    output,
                confidenceScorePercent: nil,
                evidenceCoveragePercent: nil,
                confidenceLevel: nil
            )
        }

        let events = [
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            1
                    ),
                sessionID: sessions[0],
                sequence: 1,
                kind: .comparisonSaved,
                context:
                    context(
                        frequency: 80.04,
                        phase: 120.4,
                        output: 20.4
                    ),
                metrics: [
                    "measured_reduction_db":
                        3.8
                ]
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            2
                    ),
                sessionID: sessions[0],
                sequence: 2,
                kind: .comparisonSaved,
                context:
                    context(
                        frequency: 80.04,
                        phase: 120.4,
                        output: 20.4
                    ),
                metrics: [
                    "measured_reduction_db":
                        4.2
                ]
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            3
                    ),
                sessionID: sessions[1],
                sequence: 1,
                kind: .comparisonSaved,
                context:
                    context(
                        frequency: 79.96,
                        phase: 119.6,
                        output: 19.6
                    ),
                metrics: [
                    "measured_reduction_db":
                        3.8
                ]
            ),
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            4
                    ),
                sessionID: sessions[2],
                sequence: 1,
                kind: .comparisonSaved,
                context:
                    context(
                        frequency: 80,
                        phase: 120,
                        output: 20
                    ),
                metrics: [
                    "measured_reduction_db":
                        4.2
                ]
            )
        ]

        let snapshot =
            RepeatabilityAnalytics
                .snapshot(
                    events: events
                )

        XCTAssertEqual(
            snapshot.comparisonEventCount,
            4
        )
        XCTAssertEqual(
            snapshot.analyzableComparisonCount,
            4
        )
        XCTAssertEqual(
            snapshot.matchedConditionCount,
            1
        )
        XCTAssertEqual(
            snapshot.crossSessionConditionCount,
            1
        )
        XCTAssertEqual(
            snapshot.matureConditionCount,
            1
        )
        XCTAssertEqual(
            snapshot.consistentReductionCount,
            1
        )

        let group =
            snapshot.groups[0]

        XCTAssertEqual(
            group.sessionCount,
            3
        )
        XCTAssertEqual(
            group.comparisonCount,
            4
        )
        XCTAssertEqual(
            group.meanReductionDB,
            4,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            group.assessment,
            .consistentReduction
        )
        XCTAssertEqual(
            group.condition
                .targetFrequencyHz,
            80,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            group.condition
                .phaseDegrees,
            120
        )
        XCTAssertEqual(
            group.condition
                .outputPercent,
            20
        )
    }

    func testRepeatabilityUsesSessionMeansInsteadOfTrialCount() {
        let firstSession =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000056"
            )!
        let secondSession =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000057"
            )!
        let context =
            StructuredLogContext(
                routeSignature:
                    "route-weighting",
                routeRevision: 1,
                calibrationProfileID: nil,
                targetFrequencyHz: 90,
                phaseDegrees: 180,
                outputPercent: 30,
                confidenceScorePercent: nil,
                evidenceCoveragePercent: nil,
                confidenceLevel: nil
            )

        var events:
            [StructuredLogEvent] = []

        for index in 0..<10 {
            events.append(
                StructuredLogEvent(
                    recordedAt:
                        Date(
                            timeIntervalSince1970:
                                Double(index)
                        ),
                    sessionID:
                        firstSession,
                    sequence:
                        UInt64(
                            index + 1
                        ),
                    kind:
                        .comparisonSaved,
                    context: context,
                    metrics: [
                        "measured_reduction_db":
                            6
                    ]
                )
            )
        }

        events.append(
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            20
                    ),
                sessionID:
                    secondSession,
                sequence: 1,
                kind:
                    .comparisonSaved,
                context: context,
                metrics: [
                    "measured_reduction_db":
                        2
                ]
            )
        )

        let group =
            RepeatabilityAnalytics
                .snapshot(
                    events: events
                )
                .groups[0]

        XCTAssertEqual(
            group.sessionCount,
            2
        )
        XCTAssertEqual(
            group.comparisonCount,
            11
        )
        XCTAssertEqual(
            group.meanReductionDB,
            4,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            group.assessment,
            .earlyEvidence
        )
    }

    func testRepeatabilityDetectsMixedDirectionAcrossMatureSessions() {
        XCTAssertEqual(
            RepeatabilityAnalytics
                .assessment(
                    sessionMeanReductionsDB: [
                        2.2,
                        1.8,
                        -1.1
                    ]
                ),
            .mixedDirection
        )

        XCTAssertEqual(
            RepeatabilityAnalytics
                .assessment(
                    sessionMeanReductionsDB: [
                        -2.0,
                        -2.3,
                        -1.8
                    ]
                ),
            .consistentWorsening
        )

        XCTAssertEqual(
            RepeatabilityAnalytics
                .assessment(
                    sessionMeanReductionsDB: [
                        0.1,
                        -0.2,
                        0.3
                    ]
                ),
            .consistentNeutral
        )
    }

    func testRepeatabilityExcludesComparisonsWithoutCompleteMatchContext() {
        let sessionID =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000058"
            )!

        let complete =
            StructuredLogEvent(
                sessionID: sessionID,
                sequence: 1,
                kind: .comparisonSaved,
                context:
                    StructuredLogContext(
                        routeSignature:
                            "route-complete",
                        routeRevision: 1,
                        calibrationProfileID: nil,
                        targetFrequencyHz: 70,
                        phaseDegrees: 90,
                        outputPercent: 25,
                        confidenceScorePercent: nil,
                        evidenceCoveragePercent: nil,
                        confidenceLevel: nil
                    ),
                metrics: [
                    "measured_reduction_db":
                        2
                ]
            )
        let missingPhase =
            StructuredLogEvent(
                sessionID: sessionID,
                sequence: 2,
                kind: .comparisonSaved,
                context:
                    StructuredLogContext(
                        routeSignature:
                            "route-complete",
                        routeRevision: 1,
                        calibrationProfileID: nil,
                        targetFrequencyHz: 70,
                        phaseDegrees: nil,
                        outputPercent: 25,
                        confidenceScorePercent: nil,
                        evidenceCoveragePercent: nil,
                        confidenceLevel: nil
                    ),
                metrics: [
                    "measured_reduction_db":
                        3
                ]
            )
        let missingReduction =
            StructuredLogEvent(
                sessionID: sessionID,
                sequence: 3,
                kind: .comparisonSaved,
                context:
                    complete.context
            )

        let snapshot =
            RepeatabilityAnalytics
                .snapshot(
                    events: [
                        complete,
                        missingPhase,
                        missingReduction
                    ]
                )

        XCTAssertEqual(
            snapshot.comparisonEventCount,
            3
        )
        XCTAssertEqual(
            snapshot.analyzableComparisonCount,
            1
        )
        XCTAssertEqual(
            snapshot.excludedComparisonCount,
            2
        )
        XCTAssertEqual(
            snapshot.matchedConditionCount,
            1
        )
    }

    func testHeadPositionSensitivityGroupsMatchedSettingsAcrossPositions() {
        let referenceSession =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000059"
            )!
        let leftSessionA =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000060"
            )!
        let leftSessionB =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000061"
            )!

        func event(
            sessionID: UUID,
            sequence: UInt64,
            position:
                HeadPositionPreset,
            reduction: Double
        ) -> StructuredLogEvent {
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            Double(sequence)
                    ),
                sessionID: sessionID,
                sequence: sequence,
                kind: .comparisonSaved,
                context:
                    StructuredLogContext(
                        routeSignature:
                            "route-position",
                        routeRevision: 1,
                        calibrationProfileID: nil,
                        targetFrequencyHz: 80,
                        phaseDegrees: 180,
                        outputPercent: 25,
                        confidenceScorePercent: nil,
                        evidenceCoveragePercent: nil,
                        confidenceLevel: nil
                    ),
                metrics: [
                    "measured_reduction_db":
                        reduction
                ],
                text: [
                    "head_position":
                        position.rawValue
                ]
            )
        }

        var events:
            [StructuredLogEvent] = []

        for index in 0..<10 {
            events.append(
                event(
                    sessionID:
                        referenceSession,
                    sequence:
                        UInt64(index + 1),
                    position:
                        .reference,
                    reduction: 4
                )
            )
        }

        events.append(
            event(
                sessionID:
                    leftSessionA,
                sequence: 1,
                position: .left,
                reduction: 1
            )
        )
        events.append(
            event(
                sessionID:
                    leftSessionB,
                sequence: 1,
                position: .left,
                reduction: 3
            )
        )

        let snapshot =
            HeadPositionSensitivityAnalytics
                .snapshot(
                    events: events
                )

        XCTAssertEqual(
            snapshot.taggedComparisonCount,
            12
        )
        XCTAssertEqual(
            snapshot.conditionCount,
            1
        )
        XCTAssertEqual(
            snapshot.multiPositionConditionCount,
            1
        )

        let group =
            snapshot.groups[0]

        XCTAssertEqual(
            group.positionCount,
            2
        )
        XCTAssertEqual(
            group.comparisonCount,
            12
        )
        XCTAssertEqual(
            group.spreadDB ??
                .nan,
            2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            group.assessment,
            .moderate
        )

        let reference =
            group.positionResults
                .first {
                    $0.position ==
                        .reference
                }
        let left =
            group.positionResults
                .first {
                    $0.position ==
                        .left
                }

        XCTAssertEqual(
            reference?
                .meanReductionDB,
            4
        )
        XCTAssertEqual(
            reference?
                .sessionCount,
            1
        )
        XCTAssertEqual(
            reference?
                .comparisonCount,
            10
        )
        XCTAssertEqual(
            left?
                .meanReductionDB,
            2
        )
        XCTAssertEqual(
            left?
                .sessionCount,
            2
        )
        XCTAssertEqual(
            left?
                .comparisonCount,
            2
        )
    }

    func testHeadPositionSensitivityDetectsDirectionReversal() {
        XCTAssertEqual(
            HeadPositionSensitivityAnalytics
                .assessment(
                    positionMeanReductionsDB: [
                        2.0,
                        -1.0
                    ]
                ),
            .directionReversal
        )

        XCTAssertEqual(
            HeadPositionSensitivityAnalytics
                .assessment(
                    positionMeanReductionsDB: [
                        2.0,
                        2.8
                    ]
                ),
            .low
        )

        XCTAssertEqual(
            HeadPositionSensitivityAnalytics
                .assessment(
                    positionMeanReductionsDB: [
                        1.0,
                        3.5
                    ]
                ),
            .moderate
        )

        XCTAssertEqual(
            HeadPositionSensitivityAnalytics
                .assessment(
                    positionMeanReductionsDB: [
                        1.0,
                        4.5
                    ]
                ),
            .high
        )

        XCTAssertEqual(
            HeadPositionSensitivityAnalytics
                .assessment(
                    positionMeanReductionsDB: [
                        2.0
                    ]
                ),
            .insufficientCoverage
        )
    }

    func testHeadPositionSensitivityExcludesUnlabeledOrIncompleteComparisons() {
        let sessionID =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000062"
            )!
        let completeContext =
            StructuredLogContext(
                routeSignature:
                    "route-position-exclusion",
                routeRevision: 1,
                calibrationProfileID: nil,
                targetFrequencyHz: 100,
                phaseDegrees: 90,
                outputPercent: 30,
                confidenceScorePercent: nil,
                evidenceCoveragePercent: nil,
                confidenceLevel: nil
            )

        let tagged =
            StructuredLogEvent(
                sessionID: sessionID,
                sequence: 1,
                kind: .comparisonSaved,
                context:
                    completeContext,
                metrics: [
                    "measured_reduction_db":
                        2
                ],
                text: [
                    "head_position":
                        HeadPositionPreset
                            .reference
                            .rawValue
                ]
            )
        let unlabeled =
            StructuredLogEvent(
                sessionID: sessionID,
                sequence: 2,
                kind: .comparisonSaved,
                context:
                    completeContext,
                metrics: [
                    "measured_reduction_db":
                        2
                ]
            )
        let missingPhase =
            StructuredLogEvent(
                sessionID: sessionID,
                sequence: 3,
                kind: .comparisonSaved,
                context:
                    StructuredLogContext(
                        routeSignature:
                            "route-position-exclusion",
                        routeRevision: 1,
                        calibrationProfileID: nil,
                        targetFrequencyHz: 100,
                        phaseDegrees: nil,
                        outputPercent: 30,
                        confidenceScorePercent: nil,
                        evidenceCoveragePercent: nil,
                        confidenceLevel: nil
                    ),
                metrics: [
                    "measured_reduction_db":
                        2
                ],
                text: [
                    "head_position":
                        HeadPositionPreset
                            .left
                            .rawValue
                ]
            )
        let unknownLabel =
            StructuredLogEvent(
                sessionID: sessionID,
                sequence: 4,
                kind: .comparisonSaved,
                context:
                    completeContext,
                metrics: [
                    "measured_reduction_db":
                        2
                ],
                text: [
                    "head_position":
                        "diagonal"
                ]
            )

        let snapshot =
            HeadPositionSensitivityAnalytics
                .snapshot(
                    events: [
                        tagged,
                        unlabeled,
                        missingPhase,
                        unknownLabel
                    ]
                )

        XCTAssertEqual(
            snapshot.comparisonEventCount,
            4
        )
        XCTAssertEqual(
            snapshot.taggedComparisonCount,
            1
        )
        XCTAssertEqual(
            snapshot.excludedComparisonCount,
            3
        )
        XCTAssertEqual(
            snapshot.conditionCount,
            1
        )
    }

    func testRepeatabilitySeparatesTaggedHeadPositions() {
        let firstSession =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000063"
            )!
        let secondSession =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000064"
            )!
        let context =
            StructuredLogContext(
                routeSignature:
                    "route-repeat-position",
                routeRevision: 1,
                calibrationProfileID: nil,
                targetFrequencyHz: 85,
                phaseDegrees: 135,
                outputPercent: 22,
                confidenceScorePercent: nil,
                evidenceCoveragePercent: nil,
                confidenceLevel: nil
            )

        let events = [
            StructuredLogEvent(
                sessionID:
                    firstSession,
                sequence: 1,
                kind: .comparisonSaved,
                context: context,
                metrics: [
                    "measured_reduction_db":
                        3
                ],
                text: [
                    "head_position":
                        HeadPositionPreset
                            .reference
                            .rawValue
                ]
            ),
            StructuredLogEvent(
                sessionID:
                    secondSession,
                sequence: 1,
                kind: .comparisonSaved,
                context: context,
                metrics: [
                    "measured_reduction_db":
                        1
                ],
                text: [
                    "head_position":
                        HeadPositionPreset
                            .left
                            .rawValue
                ]
            )
        ]

        let snapshot =
            RepeatabilityAnalytics
                .snapshot(
                    events: events
                )

        XCTAssertEqual(
            snapshot.matchedConditionCount,
            2
        )
        XCTAssertEqual(
            snapshot.crossSessionConditionCount,
            0
        )

        let positions =
            Set(
                snapshot.groups
                    .compactMap {
                        $0.condition
                            .headPosition
                    }
            )

        XCTAssertEqual(
            positions,
            Set([
                .reference,
                .left
            ])
        )
    }

    func testFrequencyCoverageBuildsBroadSeriesAcrossBands() {
        let sessionA =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000065"
            )!
        let sessionB =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000066"
            )!

        func event(
            sessionID: UUID,
            sequence: UInt64,
            frequency: Double,
            phase: Double,
            output: Double,
            reduction: Double
        ) -> StructuredLogEvent {
            StructuredLogEvent(
                recordedAt:
                    Date(
                        timeIntervalSince1970:
                            Double(sequence)
                    ),
                sessionID: sessionID,
                sequence: sequence,
                kind: .comparisonSaved,
                context:
                    StructuredLogContext(
                        routeSignature:
                            "route-frequency",
                        routeRevision: 1,
                        calibrationProfileID: nil,
                        targetFrequencyHz:
                            frequency,
                        phaseDegrees:
                            phase,
                        outputPercent:
                            output,
                        confidenceScorePercent: nil,
                        evidenceCoveragePercent: nil,
                        confidenceLevel: nil
                    ),
                metrics: [
                    "measured_reduction_db":
                        reduction
                ],
                text: [
                    "head_position":
                        HeadPositionPreset
                            .reference
                            .rawValue
                ]
            )
        }

        var events:
            [StructuredLogEvent] = []

        for index in 0..<10 {
            events.append(
                event(
                    sessionID: sessionA,
                    sequence:
                        UInt64(index + 1),
                    frequency: 40.2,
                    phase:
                        Double(index * 30),
                    output: 20,
                    reduction:
                        index == 9
                        ? 4
                        : 0
                )
            )
        }

        events.append(
            event(
                sessionID: sessionB,
                sequence: 1,
                frequency: 39.8,
                phase: 120,
                output: 25,
                reduction: 2
            )
        )
        events.append(
            event(
                sessionID: sessionA,
                sequence: 20,
                frequency: 90,
                phase: 210,
                output: 30,
                reduction: 1.5
            )
        )
        events.append(
            event(
                sessionID: sessionA,
                sequence: 21,
                frequency: 160,
                phase: 300,
                output: 35,
                reduction: 0.8
            )
        )

        let snapshot =
            FrequencyCoverageAnalytics
                .snapshot(
                    events: events
                )

        XCTAssertEqual(
            snapshot.analyzableComparisonCount,
            13
        )
        XCTAssertEqual(
            snapshot.distinctFrequencyCount,
            3
        )
        XCTAssertEqual(
            snapshot.multiFrequencySeriesCount,
            1
        )
        XCTAssertEqual(
            snapshot.broadCoverageSeriesCount,
            1
        )
        XCTAssertEqual(
            snapshot.maximumFrequencySpanHz ??
                .nan,
            120,
            accuracy: 0.0001
        )

        let series =
            snapshot.series[0]

        XCTAssertEqual(
            series.frequencyCount,
            3
        )
        XCTAssertEqual(
            series.bandsCovered,
            Set([
                .low,
                .mid,
                .high
            ])
        )
        XCTAssertEqual(
            series.assessment,
            .broad
        )
        XCTAssertEqual(
            series.minimumFrequencyHz,
            40,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            series.maximumFrequencyHz,
            160,
            accuracy: 0.0001
        )

        let forty =
            series.frequencyResults
                .first {
                    $0.frequencyHz ==
                        40
                }

        XCTAssertEqual(
            forty?
                .sessionCount,
            2
        )
        XCTAssertEqual(
            forty?
                .comparisonCount,
            11
        )
        XCTAssertEqual(
            forty?
                .sessionBalancedBestReductionDB ??
                .nan,
            3,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            forty?
                .bestObservedReductionDB ??
                .nan,
            4,
            accuracy: 0.0001
        )
    }

    func testFrequencyCoverageSeparatesRouteAndHeadPositionSeries() {
        let sessionID =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000067"
            )!

        func event(
            route: String,
            position:
                HeadPositionPreset,
            frequency: Double,
            sequence: UInt64
        ) -> StructuredLogEvent {
            StructuredLogEvent(
                sessionID:
                    sessionID,
                sequence: sequence,
                kind: .comparisonSaved,
                context:
                    StructuredLogContext(
                        routeSignature: route,
                        routeRevision: 1,
                        calibrationProfileID: nil,
                        targetFrequencyHz:
                            frequency,
                        phaseDegrees: 180,
                        outputPercent: 25,
                        confidenceScorePercent: nil,
                        evidenceCoveragePercent: nil,
                        confidenceLevel: nil
                    ),
                metrics: [
                    "measured_reduction_db":
                        2
                ],
                text: [
                    "head_position":
                        position.rawValue
                ]
            )
        }

        let snapshot =
            FrequencyCoverageAnalytics
                .snapshot(
                    events: [
                        event(
                            route: "route-a",
                            position:
                                .reference,
                            frequency: 40,
                            sequence: 1
                        ),
                        event(
                            route: "route-a",
                            position:
                                .reference,
                            frequency: 120,
                            sequence: 2
                        ),
                        event(
                            route: "route-a",
                            position: .left,
                            frequency: 40,
                            sequence: 3
                        ),
                        event(
                            route: "route-b",
                            position:
                                .reference,
                            frequency: 40,
                            sequence: 4
                        )
                    ]
                )

        XCTAssertEqual(
            snapshot.seriesCount,
            3
        )
        XCTAssertEqual(
            snapshot.multiFrequencySeriesCount,
            1
        )

        let referenceRouteA =
            snapshot.series
                .first {
                    $0.context
                        .routeSignature ==
                        "route-a" &&
                    $0.context
                        .headPosition ==
                        .reference
                }

        XCTAssertEqual(
            referenceRouteA?
                .frequencyCount,
            2
        )
        XCTAssertEqual(
            referenceRouteA?
                .assessment,
            .partial
        )
    }

    func testFrequencyCoverageAssessmentUsesBandCoverage() {
        XCTAssertEqual(
            FrequencyCoverageAnalytics
                .assessment(
                    frequencyCount: 1,
                    bandsCovered:
                        Set([
                            .low
                        ])
                ),
            .singleTarget
        )

        XCTAssertEqual(
            FrequencyCoverageAnalytics
                .assessment(
                    frequencyCount: 3,
                    bandsCovered:
                        Set([
                            .low
                        ])
                ),
            .narrow
        )

        XCTAssertEqual(
            FrequencyCoverageAnalytics
                .assessment(
                    frequencyCount: 3,
                    bandsCovered:
                        Set([
                            .low,
                            .mid
                        ])
                ),
            .partial
        )

        XCTAssertEqual(
            FrequencyCoverageAnalytics
                .assessment(
                    frequencyCount: 3,
                    bandsCovered:
                        Set([
                            .low,
                            .mid,
                            .high
                        ])
                ),
            .broad
        )
    }

    func testFrequencyCoverageExcludesIncompleteAndOutOfBandComparisons() {
        let sessionID =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000068"
            )!
        let completeContext =
            StructuredLogContext(
                routeSignature:
                    "route-frequency-exclusion",
                routeRevision: 1,
                calibrationProfileID: nil,
                targetFrequencyHz: 80,
                phaseDegrees: 90,
                outputPercent: 20,
                confidenceScorePercent: nil,
                evidenceCoveragePercent: nil,
                confidenceLevel: nil
            )

        let complete =
            StructuredLogEvent(
                sessionID: sessionID,
                sequence: 1,
                kind: .comparisonSaved,
                context:
                    completeContext,
                metrics: [
                    "measured_reduction_db":
                        2
                ]
            )
        let missingRoute =
            StructuredLogEvent(
                sessionID: sessionID,
                sequence: 2,
                kind: .comparisonSaved,
                context:
                    StructuredLogContext(
                        routeSignature: nil,
                        routeRevision: 1,
                        calibrationProfileID: nil,
                        targetFrequencyHz: 80,
                        phaseDegrees: 90,
                        outputPercent: 20,
                        confidenceScorePercent: nil,
                        evidenceCoveragePercent: nil,
                        confidenceLevel: nil
                    ),
                metrics: [
                    "measured_reduction_db":
                        2
                ]
            )
        let outOfBand =
            StructuredLogEvent(
                sessionID: sessionID,
                sequence: 3,
                kind: .comparisonSaved,
                context:
                    StructuredLogContext(
                        routeSignature:
                            "route-frequency-exclusion",
                        routeRevision: 1,
                        calibrationProfileID: nil,
                        targetFrequencyHz: 250,
                        phaseDegrees: 90,
                        outputPercent: 20,
                        confidenceScorePercent: nil,
                        evidenceCoveragePercent: nil,
                        confidenceLevel: nil
                    ),
                metrics: [
                    "measured_reduction_db":
                        2
                ]
            )
        let missingReduction =
            StructuredLogEvent(
                sessionID: sessionID,
                sequence: 4,
                kind: .comparisonSaved,
                context:
                    completeContext
            )

        let snapshot =
            FrequencyCoverageAnalytics
                .snapshot(
                    events: [
                        complete,
                        missingRoute,
                        outOfBand,
                        missingReduction
                    ]
                )

        XCTAssertEqual(
            snapshot.comparisonEventCount,
            4
        )
        XCTAssertEqual(
            snapshot.analyzableComparisonCount,
            1
        )
        XCTAssertEqual(
            snapshot.excludedComparisonCount,
            3
        )
        XCTAssertEqual(
            snapshot.distinctFrequencyCount,
            1
        )
        XCTAssertEqual(
            snapshot.seriesCount,
            1
        )
    }

    private func makeLabDecisionEvents(
        referenceReductionDB:
            Double = 2.0,
        leftReductionDB:
            Double = 1.5,
        confidenceScorePercent:
            Double = 65,
        evidenceCoveragePercent:
            Double = 80
    ) -> [StructuredLogEvent] {
        let sessions = [
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000069"
            )!,
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000070"
            )!,
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000071"
            )!
        ]

        var events:
            [StructuredLogEvent] = []
        var timestamp = 1.0

        func append(
            sessionID: UUID,
            sequence: UInt64,
            frequency: Double,
            position:
                HeadPositionPreset,
            reduction: Double
        ) {
            events.append(
                StructuredLogEvent(
                    recordedAt:
                        Date(
                            timeIntervalSince1970:
                                timestamp
                        ),
                    sessionID:
                        sessionID,
                    sequence:
                        sequence,
                    kind:
                        .comparisonSaved,
                    context:
                        StructuredLogContext(
                            routeSignature:
                                "route-decision",
                            routeRevision: 1,
                            calibrationProfileID: nil,
                            targetFrequencyHz:
                                frequency,
                            phaseDegrees: 180,
                            outputPercent: 25,
                            confidenceScorePercent:
                                confidenceScorePercent,
                            evidenceCoveragePercent:
                                evidenceCoveragePercent,
                            confidenceLevel:
                                OverallConfidenceLevel
                                    .moderate
                                    .rawValue
                        ),
                    metrics: [
                        "measured_reduction_db":
                            reduction
                    ],
                    text: [
                        "head_position":
                            position.rawValue
                    ]
                )
            )
            timestamp += 1
        }

        for
            (
                sessionIndex,
                session
            )
            in sessions.enumerated()
        {
            append(
                sessionID: session,
                sequence: 1,
                frequency: 40,
                position:
                    .reference,
                reduction:
                    referenceReductionDB
            )
            append(
                sessionID: session,
                sequence: 2,
                frequency: 90,
                position:
                    .reference,
                reduction:
                    referenceReductionDB
            )
            append(
                sessionID: session,
                sequence: 3,
                frequency: 160,
                position:
                    .reference,
                reduction:
                    referenceReductionDB
            )

            if sessionIndex == 0 {
                append(
                    sessionID:
                        session,
                    sequence: 4,
                    frequency: 40,
                    position: .left,
                    reduction:
                        leftReductionDB
                )
            }
        }

        return events
    }

    func testLabGoNoGoReturnsGoWhenAllFiveGatesPass() {
        let events =
            makeLabDecisionEvents()
        let currentSessionID =
            events[0].sessionID

        let snapshot =
            LabGoNoGoAnalytics
                .snapshot(
                    events: events,
                    currentSessionID:
                        currentSessionID
                )

        XCTAssertEqual(
            snapshot.verdict,
            .go
        )
        XCTAssertEqual(
            snapshot.passedGateCount,
            5
        )
        XCTAssertEqual(
            snapshot.needsEvidenceGateCount,
            0
        )
        XCTAssertEqual(
            snapshot.warningGateCount,
            0
        )
        XCTAssertEqual(
            snapshot.blockerGateCount,
            0
        )
        XCTAssertEqual(
            snapshot.comparisonCount,
            10
        )
        XCTAssertEqual(
            snapshot.sessionCount,
            3
        )
        XCTAssertGreaterThanOrEqual(
            snapshot.consistentReductionCount,
            1
        )
        XCTAssertEqual(
            snapshot.directionReversalCount,
            0
        )
        XCTAssertEqual(
            snapshot.qualifyingBroadFrequencySeriesCount,
            1
        )
        XCTAssertTrue(
            snapshot.reportText
                .contains(
                    "Verdict: GO"
                )
        )
    }

    func testLabGoNoGoHoldsWhenEvidenceIsIncomplete() {
        let sessionID =
            UUID(
                uuidString:
                    "00000000-0000-0000-0000-000000000072"
            )!

        let snapshot =
            LabGoNoGoAnalytics
                .snapshot(
                    events: [],
                    currentSessionID:
                        sessionID
                )

        XCTAssertEqual(
            snapshot.verdict,
            .hold
        )
        XCTAssertGreaterThan(
            snapshot.needsEvidenceGateCount,
            0
        )
        XCTAssertEqual(
            snapshot.blockerGateCount,
            0
        )
    }

    func testLabGoNoGoBlocksOnHeadPositionDirectionReversal() {
        let events =
            makeLabDecisionEvents(
                leftReductionDB: -1.0
            )

        let snapshot =
            LabGoNoGoAnalytics
                .snapshot(
                    events: events,
                    currentSessionID:
                        events[0]
                            .sessionID
                )

        XCTAssertEqual(
            snapshot.verdict,
            .noGo
        )
        XCTAssertEqual(
            snapshot.directionReversalCount,
            1
        )

        let headGate =
            snapshot.gates
                .first {
                    $0.id ==
                        "head_position"
                }

        XCTAssertEqual(
            headGate?.status,
            .blocker
        )
    }

    func testLabGoNoGoBlocksOnLowConfidenceWithAdequateCoverage() {
        let events =
            makeLabDecisionEvents(
                confidenceScorePercent:
                    40,
                evidenceCoveragePercent:
                    80
            )

        let snapshot =
            LabGoNoGoAnalytics
                .snapshot(
                    events: events,
                    currentSessionID:
                        events[0]
                            .sessionID
                )

        XCTAssertEqual(
            snapshot.verdict,
            .noGo
        )

        let confidenceGate =
            snapshot.gates
                .first {
                    $0.id ==
                        "overall_confidence"
                }

        XCTAssertEqual(
            confidenceGate?.status,
            .blocker
        )
    }

    func testLabGoNoGoHoldsOnHighHeadPositionSensitivityWithoutReversal() {
        let events =
            makeLabDecisionEvents(
                referenceReductionDB:
                    4.0,
                leftReductionDB:
                    0.6
            )

        let snapshot =
            LabGoNoGoAnalytics
                .snapshot(
                    events: events,
                    currentSessionID:
                        events[0]
                            .sessionID
                )

        XCTAssertEqual(
            snapshot.verdict,
            .hold
        )

        let headGate =
            snapshot.gates
                .first {
                    $0.id ==
                        "head_position"
                }

        XCTAssertEqual(
            headGate?.status,
            .warning
        )
        XCTAssertEqual(
            snapshot.blockerGateCount,
            0
        )
        XCTAssertEqual(
            snapshot.warningGateCount,
            1
        )
    }

    func testANCFocusFiltersToThirtyThroughTwoHundredHertz() {
        let bins = [
            SpectrumBin(frequencyHz: 20, magnitudeDBFS: -40),
            SpectrumBin(frequencyHz: 30, magnitudeDBFS: -35),
            SpectrumBin(frequencyHz: 100, magnitudeDBFS: -25),
            SpectrumBin(frequencyHz: 200, magnitudeDBFS: -30),
            SpectrumBin(frequencyHz: 250, magnitudeDBFS: -20)
        ]

        let filtered = AnalysisMode.ancFocus.filter(bins)

        XCTAssertEqual(
            filtered.map(\.frequencyHz),
            [30, 100, 200]
        )
    }

    func testWideLabFiltersToTwentyThroughTwoKilohertz() {
        let bins = [
            SpectrumBin(frequencyHz: 10, magnitudeDBFS: -50),
            SpectrumBin(frequencyHz: 20, magnitudeDBFS: -45),
            SpectrumBin(frequencyHz: 500, magnitudeDBFS: -30),
            SpectrumBin(frequencyHz: 2_000, magnitudeDBFS: -35),
            SpectrumBin(frequencyHz: 2_100, magnitudeDBFS: -20)
        ]

        let filtered = AnalysisMode.wideLab.filter(bins)

        XCTAssertEqual(
            filtered.map(\.frequencyHz),
            [20, 500, 2_000]
        )
    }

    func testSpectrumSmoothingANCFocusDropsOutOfBandBins() {
        let bank = SpectrumSmoothingBank()
        let bins = [
            SpectrumBin(frequencyHz: 20, magnitudeDBFS: -50),
            SpectrumBin(frequencyHz: 30, magnitudeDBFS: -45),
            SpectrumBin(frequencyHz: 80, magnitudeDBFS: -25),
            SpectrumBin(frequencyHz: 200, magnitudeDBFS: -40),
            SpectrumBin(frequencyHz: 300, magnitudeDBFS: -30)
        ]

        let snapshot = bank.process(
            bins,
            analysisMode: .ancFocus
        )

        XCTAssertEqual(
            snapshot.balanced.map(\.frequencyHz),
            [30, 80, 200]
        )
    }

    func testDominantDetectorHonorsANCFocusLowerBound() {
        let detector = DominantFrequencyDetector(
            maximumResults: 5,
            minimumSeparationHz: 10,
            minimumLocalProminenceDB: 2,
            minimumScoreDB: 2
        )
        let spectrum = [
            SpectrumBin(frequencyHz: 20, magnitudeDBFS: -60),
            SpectrumBin(frequencyHz: 25, magnitudeDBFS: -20),
            SpectrumBin(frequencyHz: 30, magnitudeDBFS: -60),
            SpectrumBin(frequencyHz: 40, magnitudeDBFS: -55),
            SpectrumBin(frequencyHz: 50, magnitudeDBFS: -25),
            SpectrumBin(frequencyHz: 60, magnitudeDBFS: -55),
            SpectrumBin(frequencyHz: 70, magnitudeDBFS: -60)
        ]
        let floor = spectrum.map {
            SpectrumBin(
                frequencyHz: $0.frequencyHz,
                magnitudeDBFS: -65
            )
        }

        let result = detector.detect(
            spectrum: spectrum,
            noiseFloor: floor,
            frequencyRange: AnalysisMode.ancFocus.dominantFrequencyRange
        )

        XCTAssertTrue(
            result.frequencies.allSatisfy {
                $0.frequencyHz >= 30 &&
                $0.frequencyHz <= 200
            }
        )
        XCTAssertTrue(
            result.frequencies.contains {
                abs($0.frequencyHz - 50) < 2
            }
        )
        XCTAssertFalse(
            result.frequencies.contains {
                $0.frequencyHz < 30
            }
        )
    }

    func testANCFocusGraphRangeIsThirtyToTwoHundredHertz() {
        XCTAssertEqual(
            SpectrumDisplayRange.ancFocus.frequencyRange,
            30...200
        )
        XCTAssertEqual(
            SpectrumDisplayRange.ancFocus.frequencyTicks,
            [30, 50, 100, 150, 200]
        )
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
