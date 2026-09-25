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
        XCTAssertEqual(snapshot.lowFrequencyFloorDBFS, -54.62, accuracy: 0.1)
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
