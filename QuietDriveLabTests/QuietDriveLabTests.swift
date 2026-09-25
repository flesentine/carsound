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
}
