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
}
