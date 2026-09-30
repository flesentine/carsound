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
            snapshot.nonBluetoothOutputLatencyAverageMilliseconds,
            10,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.outputLatencyDeltaVersusNonBluetoothMilliseconds,
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
