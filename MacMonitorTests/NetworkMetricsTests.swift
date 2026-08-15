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

    // MARK: - What a run costs

    /// The rule stated before the button: ten seconds at one Mbit/s is 1.25 MB, and it
    /// scales. Checked against every complete run measured while building this, rate
    /// against bytes for the same run.
    ///
    /// Five per cent of slack, and it is spent almost entirely on one run: the 674
    /// Mbit/s one lasted 10.5 seconds rather than 10, so it moved five per cent more
    /// than the rule predicts. The other three land within one per cent.
    ///
    /// This bites if the ten seconds ever changes. Halve the duration and 1.25 becomes
    /// 0.625, and every line here fails.
    func testTheStatedRuleReproducesEveryRunThatWasMeasured() {
        let runs: [(mbps: Double, megabytes: Double)] = [
            (226, 285),   // upload, ten seconds
            (263, 335),   // upload, through this application
            (312, 390),   // download, ten seconds
            (316, 395),   // download, through this application
            (674, 885),   // download, ten and a half seconds
            (688, 860),   // download, ten seconds
        ]
        for run in runs {
            let predicted = run.mbps * SpeedTestFacts.megabytesPerMegabitPerSecond
            XCTAssertEqual(predicted, run.megabytes, accuracy: run.megabytes * 0.05,
                           "the rule missed the \(Int(run.mbps)) Mbit/s run")
        }
    }

    /// The rating describes the download and nothing else. A fast download does not
    /// become "slow" because the upstream is narrow, and a wide upstream does not
    /// rescue a bad download. The boundaries were chosen for a download, and applying
    /// them to an upload would call an ordinary 25 Mbit/s upstream slow.
    func testTheRatingFollowsTheDownloadAndIgnoresTheUpload() {
        let fastDownSlowUp = SpeedTestResult(downloadMegabitsPerSecond: 688, downloadBytes: 0,
                                             uploadMegabitsPerSecond: 3, uploadBytes: 0,
                                             uploadFailure: nil, server: "", finishedAt: Date())
        XCTAssertEqual(fastDownSlowUp.tier, .veryFast)

        let slowDownFastUp = SpeedTestResult(downloadMegabitsPerSecond: 3, downloadBytes: 0,
                                             uploadMegabitsPerSecond: 688, uploadBytes: 0,
                                             uploadFailure: nil, server: "", finishedAt: Date())
        XCTAssertEqual(slowDownFastUp.tier, .verySlow)
    }

    /// An upload that did not complete leaves nothing behind rather than a zero. The
    /// download is still a measurement and is still rated.
    func testAnUnfinishedUploadIsAbsentRatherThanZero() {
        let result = SpeedTestResult(downloadMegabitsPerSecond: 312, downloadBytes: 390_000_000,
                                     uploadMegabitsPerSecond: nil, uploadBytes: 0,
                                     uploadFailure: "the socket closed", server: "", finishedAt: Date())
        XCTAssertNil(result.uploadMegabitsPerSecond)
        XCTAssertEqual(result.tier, .fast)
        XCTAssertEqual(result.totalBytes, 390_000_000)
    }

    // MARK: - Gauge scale

    func testTheStopsAreOneAndOneThousand() {
        XCTAssertEqual(GaugeScale.fraction(forMegabitsPerSecond: 1), 0, accuracy: 1e-12)
        XCTAssertEqual(GaugeScale.fraction(forMegabitsPerSecond: 1000), 1, accuracy: 1e-12)
    }

    /// Three decades, one third of the sweep each. This is the whole scale in one test.
    func testEachDecadeTakesAThirdOfTheSweep() {
        XCTAssertEqual(GaugeScale.fraction(forMegabitsPerSecond: 10), 1.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(GaugeScale.fraction(forMegabitsPerSecond: 100), 2.0 / 3, accuracy: 1e-12)
    }

    /// The middle of a logarithmic dial is the geometric mean of its ends, not the
    /// arithmetic one. 31.6 Mbit/s sits halfway, 500 Mbit/s does not.
    func testTheMiddleOfTheDialIsTheGeometricMean() {
        XCTAssertEqual(GaugeScale.fraction(forMegabitsPerSecond: 31.6227766), 0.5, accuracy: 1e-6)
        XCTAssertNotEqual(GaugeScale.fraction(forMegabitsPerSecond: 500), 0.5, accuracy: 0.1)
    }

    /// The defining property: the same ratio always moves the needle the same distance,
    /// wherever it is on the dial. A doubling is a doubling.
    func testADoublingMovesTheNeedleByTheSameAmountAnywhere() {
        let step = log10(2.0) / 3
        for start in [1.5, 4.0, 12.0, 60.0, 300.0] {
            let moved = GaugeScale.fraction(forMegabitsPerSecond: start * 2)
                      - GaugeScale.fraction(forMegabitsPerSecond: start)
            XCTAssertEqual(moved, step, accuracy: 1e-12)
        }
    }

    /// What the choice buys, stated as a number so it can be argued with. On a linear
    /// 0-1000 dial a 20 Mbit/s connection sits at 2 % of the sweep, five degrees out of
    /// 270, which is not a reading. Here it sits at 43 %.
    func testTwentyMegabitsIsReadableHereAndInvisibleOnALinearDial() {
        let here = GaugeScale.fraction(forMegabitsPerSecond: 20)
        let linear = 20.0 / GaugeScale.maximum
        XCTAssertEqual(here, 0.4337, accuracy: 0.0001)
        XCTAssertEqual(linear, 0.02, accuracy: 0.0001)
        XCTAssertGreaterThan(here * 270 - linear * 270, 100)   // degrees apart
    }

    /// A link outside the scale pins the needle rather than running off the dial. The
    /// exact figure is printed in the middle either way, so nothing is lost but the
    /// position.
    func testValuesOutsideTheScalePinRatherThanEscape() {
        XCTAssertEqual(GaugeScale.fraction(forMegabitsPerSecond: 0.1), 0)
        XCTAssertEqual(GaugeScale.fraction(forMegabitsPerSecond: 0), 0)
        XCTAssertEqual(GaugeScale.fraction(forMegabitsPerSecond: -5), 0)
        XCTAssertEqual(GaugeScale.fraction(forMegabitsPerSecond: 10_000), 1)
    }

    func testTheScaleNeverGoesBackwards() {
        var previous = -1.0
        for mbps in stride(from: 0.5, through: 1200, by: 0.5) {
            let f = GaugeScale.fraction(forMegabitsPerSecond: mbps)
            XCTAssertGreaterThanOrEqual(f, previous)
            previous = f
        }
    }

    /// The top of the dial is a stop, not a reading, and the label has to say so.
    func testOnlyTheTopTickCarriesAPlus() {
        XCTAssertEqual(GaugeScale.label(forTick: 1), "1")
        XCTAssertEqual(GaugeScale.label(forTick: 10), "10")
        XCTAssertEqual(GaugeScale.label(forTick: 100), "100")
        XCTAssertEqual(GaugeScale.label(forTick: 1000), "1000+")
    }

    func testEveryTickLandsOnTheDial() {
        for tick in GaugeScale.majorTicks + GaugeScale.minorTicks {
            let f = GaugeScale.fraction(forMegabitsPerSecond: tick)
            XCTAssertGreaterThanOrEqual(f, 0)
            XCTAssertLessThanOrEqual(f, 1)
        }
        // and no minor tick sits on top of a major one
        let majors = Set(GaugeScale.majorTicks)
        XCTAssertTrue(GaugeScale.minorTicks.allSatisfy { !majors.contains($0) })
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
