import XCTest
@testable import MacMonitor

/// The two pure functions behind the Network screen.
///
/// The tier boundaries are a design choice rather than a measurement, so these tests
/// pin the choice: if someone moves a boundary, they do it deliberately and the test
/// says so.
final class NetworkMetricsTests: XCTestCase {

    // MARK: - Tiers

    func testTierBoundariesAreInclusiveOnTheLowerEdge() {
        XCTAssertEqual(SpeedTier.forMegabitsPerSecond(0), .verySlow)
        XCTAssertEqual(SpeedTier.forMegabitsPerSecond(4.99), .verySlow)
        XCTAssertEqual(SpeedTier.forMegabitsPerSecond(5), .slow)
        XCTAssertEqual(SpeedTier.forMegabitsPerSecond(24.99), .slow)
        XCTAssertEqual(SpeedTier.forMegabitsPerSecond(25), .normal)
        XCTAssertEqual(SpeedTier.forMegabitsPerSecond(99.99), .normal)
        XCTAssertEqual(SpeedTier.forMegabitsPerSecond(100), .fast)
        XCTAssertEqual(SpeedTier.forMegabitsPerSecond(499.99), .fast)
        XCTAssertEqual(SpeedTier.forMegabitsPerSecond(500), .veryFast)
    }

    /// The measurement taken while building this screen: an ndt7 download test on this
    /// machine reported 673 Mbit/s.
    func testTheMeasuredCapacityOfThisMachineLandsInTheTopTier() {
        XCTAssertEqual(SpeedTier.forMegabitsPerSecond(673), .veryFast)
    }

    func testEveryTierHasADistinctSymbolSoColourIsNeverTheOnlySignal() {
        let symbols = SpeedTier.allCases.map(\.symbol)
        XCTAssertEqual(Set(symbols).count, SpeedTier.allCases.count)
    }

    func testEveryTierHasALabelForVoiceOver() {
        for tier in SpeedTier.allCases {
            XCTAssertFalse(tier.label.isEmpty)
        }
    }

    // MARK: - Transfer time

    func testDownloadDurationIsBytesTimesEightOverBitRate() {
        // 15 GB at 100 Mbit/s = 15e9 * 8 / 1e8 = 1200 s
        let seconds = TransferEstimate.seconds(forBytes: TransferEstimate.fourKFilmBytes,
                                               atMegabitsPerSecond: 100)
        XCTAssertEqual(seconds ?? 0, 1200, accuracy: 0.001)
    }

    /// The capacity measured on this machine, applied to the film figure.
    func testFilmDurationAtTheMeasuredCapacity() {
        let seconds = TransferEstimate.seconds(forBytes: TransferEstimate.fourKFilmBytes,
                                               atMegabitsPerSecond: 673)
        // 15e9 * 8 / 6.73e8 = 178.3 s
        XCTAssertEqual(seconds ?? 0, 178.3, accuracy: 0.1)
        XCTAssertEqual(TransferEstimate.humanDuration(seconds: seconds ?? 0), "2 min 58 s")
    }

    /// A rate of zero must not produce an infinite or absurd duration. The whole point
    /// of the screen is that it never shows a number it cannot stand behind.
    func testNonPositiveRateFailsRatherThanDividingByZero() {
        XCTAssertNil(TransferEstimate.seconds(forBytes: 15_000_000_000, atMegabitsPerSecond: 0))
        XCTAssertNil(TransferEstimate.seconds(forBytes: 15_000_000_000, atMegabitsPerSecond: -1))
        XCTAssertNil(TransferEstimate.seconds(forBytes: 0, atMegabitsPerSecond: 100))
    }

    func testHumanDurationSwitchesUnitsAtTheRightPoints() {
        XCTAssertEqual(TransferEstimate.humanDuration(seconds: 43), "43 s")
        XCTAssertEqual(TransferEstimate.humanDuration(seconds: 59), "59 s")
        XCTAssertEqual(TransferEstimate.humanDuration(seconds: 60), "1 min 00 s")
        XCTAssertEqual(TransferEstimate.humanDuration(seconds: 134), "2 min 14 s")
        XCTAssertEqual(TransferEstimate.humanDuration(seconds: 3599), "59 min 59 s")
        XCTAssertEqual(TransferEstimate.humanDuration(seconds: 3600), "1 h 00 min")
        XCTAssertEqual(TransferEstimate.humanDuration(seconds: 3780), "1 h 03 min")
    }

    /// On a very slow link the answer should be hours, and it should still read.
    func testSlowLinkProducesAReadableDurationRatherThanAHugeNumberOfSeconds() {
        let seconds = TransferEstimate.seconds(forBytes: TransferEstimate.fourKFilmBytes,
                                               atMegabitsPerSecond: 4)
        // 15e9 * 8 / 4e6 = 30000 s = 8 h 20 min
        XCTAssertEqual(TransferEstimate.humanDuration(seconds: seconds ?? 0), "8 h 20 min")
    }
}
