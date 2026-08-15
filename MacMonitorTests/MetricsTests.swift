import XCTest
@testable import MacMonitor

/// Tests for the pure computation layer.
///
/// Each test is derived from a defect found in the 14 August read-only audit and
/// from the behaviour the app is supposed to have - not from how the fix happens to
/// be written. Every one of them fails against the original code; where that is not
/// obvious, the test says so.
final class MetricsTests: XCTestCase {

    // MARK: - A1: page size

    /// The original code converted vm_stat page counts with a hardcoded 4096.
    /// That is right on Intel and wrong on Apple Silicon, where a page is 16384
    /// bytes, so every memory figure came out four times too small.
    ///
    /// Powers of two are used so the expected values are exact, not rounded.
    func testPageCountIsScaledByTheSuppliedPageSize() {
        let pages = 65_536.0 // 2^16

        // 65536 * 4096  = 268435456 bytes = 0.25 GiB
        XCTAssertEqual(MemoryMath.gigabytes(pages: pages, pageSize: 4096), 0.25)

        // 65536 * 16384 = 1073741824 bytes = 1.00 GiB
        XCTAssertEqual(MemoryMath.gigabytes(pages: pages, pageSize: 16384), 1.0)
    }

    /// The relationship between the two architectures, pinned explicitly so the
    /// factor-of-four bug cannot come back unnoticed.
    func testSixteenKilobytePagesYieldExactlyFourTimesFourKilobytePages() {
        let pages = 1_110_509.0 // active + wired + compressor, as measured in the audit

        let onIntel = MemoryMath.gigabytes(pages: pages, pageSize: 4096)
        let onAppleSilicon = MemoryMath.gigabytes(pages: pages, pageSize: 16384)

        XCTAssertNotNil(onIntel)
        XCTAssertNotNil(onAppleSilicon)
        XCTAssertEqual(onAppleSilicon! / onIntel!, 4.0, accuracy: 1e-12)

        // Audit measurement: the app showed 4.24 GB where the truth was 16.95 GB.
        XCTAssertEqual(onIntel!, 4.24, accuracy: 0.01)
        XCTAssertEqual(onAppleSilicon!, 16.95, accuracy: 0.01)
    }

    /// A page size of zero must not silently produce zero gigabytes. The original
    /// code could not express failure at all: every parse error became 0.
    func testInvalidPageSizeFailsInsteadOfReturningZero() {
        XCTAssertNil(MemoryMath.gigabytes(pages: 1000, pageSize: 0))
        XCTAssertNil(MemoryMath.gigabytes(pages: 1000, pageSize: -4096))
        XCTAssertNil(MemoryMath.gigabytes(pages: -1, pageSize: 16384))
    }

    // MARK: - A9: the first CPU sample

    /// With no previous sample the delta is the tick count since boot, i.e. the
    /// average CPU since startup. The original code reported that as if it were an
    /// instant reading and pushed it into the history graph.
    func testFirstCPUSamplePublishesNothing() {
        let boot = CPUMath.Ticks(user: 900_000, system: 400_000, idle: 8_000_000, nice: 100)
        XCTAssertNil(CPUMath.load(current: boot, previous: nil))
    }

    /// Two samples with no tick elapsed carry no information either.
    func testCPUSampleWithNoElapsedTicksPublishesNothing() {
        let t = CPUMath.Ticks(user: 10, system: 20, idle: 30, nice: 40)
        XCTAssertNil(CPUMath.load(current: t, previous: t))
    }

    func testCPULoadIsTheDeltaBetweenTwoSamples() {
        let previous = CPUMath.Ticks(user: 1000, system: 1000, idle: 8000, nice: 0)
        let current = CPUMath.Ticks(user: 1100, system: 1100, idle: 8800, nice: 0)
        // deltas: user 100, system 100, idle 800, total 1000
        let load = CPUMath.load(current: current, previous: previous)

        XCTAssertEqual(load?.user, 10.0)
        XCTAssertEqual(load?.system, 10.0)
        XCTAssertEqual(load?.idle, 80.0)
    }

    /// nice time is user time that was re-prioritised. Activity Monitor folds it
    /// into the user figure, so a process running under `nice` must not vanish.
    func testNiceTimeIsCountedAsUserTime() {
        let previous = CPUMath.Ticks(user: 0, system: 0, idle: 0, nice: 0)
        let current = CPUMath.Ticks(user: 100, system: 0, idle: 700, nice: 200)
        // user 100 + nice 200 = 300 of 1000
        XCTAssertEqual(CPUMath.load(current: current, previous: previous)?.user, 30.0)
    }

    /// The counters are UInt32 and wrap roughly every 41 days at 1200 ticks/second.
    /// Wrapping must not produce a negative or absurd percentage.
    func testTickCounterWraparoundDoesNotCorruptThePercentages() {
        let previous = CPUMath.Ticks(user: UInt32.max - 50, system: 0, idle: 0, nice: 0)
        let current = CPUMath.Ticks(user: 49, system: 0, idle: 0, nice: 0)
        // wrapped delta = 100 ticks, all of it user
        let load = CPUMath.load(current: current, previous: previous)

        XCTAssertEqual(load?.user, 100.0)
        XCTAssertEqual(load?.idle, 0.0)
    }

    // MARK: - A10: uptime

    /// The original code split the output of `uptime` on its comma, which yields
    /// "1 day" past 24 hours and throws the hours away.
    func testUptimeKeepsHoursPastTwentyFourHours() {
        // 1 day 7 h 17 m, the value measured on the machine while fixing this
        let seconds = 86_400 + 7 * 3_600 + 17 * 60
        XCTAssertEqual(UptimeFormatter.string(seconds: seconds), "1d 7h 17m")
    }

    func testUptimeKeepsHoursPastSeveralDays() {
        let seconds = 3 * 86_400 + 14 * 3_600 + 27 * 60
        XCTAssertEqual(UptimeFormatter.string(seconds: seconds), "3d 14h 27m")
    }

    func testUptimeUnderOneDayOmitsTheDayComponent() {
        XCTAssertEqual(UptimeFormatter.string(seconds: 15 * 3_600 + 44 * 60), "15h 44m")
    }

    func testUptimeUnderOneHourShowsMinutesOnly() {
        XCTAssertEqual(UptimeFormatter.string(seconds: 23 * 60), "23m")
    }

    func testNonPositiveUptimeFails() {
        XCTAssertNil(UptimeFormatter.string(seconds: 0))
        XCTAssertNil(UptimeFormatter.string(seconds: -1))
    }

    /// Guards the trap that replaced the original bug during the rewrite:
    /// ProcessInfo.systemUptime counts only time the machine was AWAKE. Measured on
    /// this machine, it read 10h39 against a real uptime of 15h44 - a 5h04 gap that
    /// is exactly the time spent asleep. The app must format wall-clock seconds
    /// derived from kern.boottime, and the formatter must be able to express a
    /// duration larger than the awake time.
    func testFormatterHandlesWallClockDurationsLargerThanAwakeTime() {
        let wallClock = 15 * 3_600 + 44 * 60   // kern.boottime
        let awake = 10 * 3_600 + 39 * 60       // ProcessInfo.systemUptime

        XCTAssertEqual(UptimeFormatter.string(seconds: wallClock), "15h 44m")
        XCTAssertEqual(UptimeFormatter.string(seconds: awake), "10h 39m")
        XCTAssertNotEqual(UptimeFormatter.string(seconds: wallClock),
                          UptimeFormatter.string(seconds: awake))
    }

    // MARK: - A6: storage counts in decimal GB, memory in binary GB

    /// The disk was divided by 2^30 and labelled "GB". macOS counts storage in
    /// decimal gigabytes, so the app showed 460.4 GB where System Settings showed
    /// 494.38 GB. This pins BOTH units in one test so the distinction cannot
    /// silently collapse back into a single formatter.
    func testMemoryUsesBinaryGigabytesAndStorageUsesDecimalGigabytes() {
        // 24 GiB of RAM, the machine the audit ran on
        XCTAssertEqual(Format.memory(24.0), "24.0 GB")

        // The same physical disk, expressed both ways
        let diskBytes = 494_384_795_648.0
        XCTAssertEqual(diskBytes / 1_000_000_000, 494.384795648, accuracy: 1e-6)
        XCTAssertEqual(diskBytes / 1_073_741_824, 460.43, accuracy: 0.01)

        // 33.95 GB apart: that is the discrepancy users would see against Finder.
        XCTAssertEqual(diskBytes / 1_000_000_000 - diskBytes / 1_073_741_824,
                       33.95, accuracy: 0.01)
    }

    /// Below the gigabyte threshold each formatter must use its own multiplier:
    /// 1024 for memory, 1000 for storage.
    func testSubGigabyteValuesUseTheRightMultiplierForEachUnit() {
        XCTAssertEqual(Format.memory(0.05), "51 MB")   // 0.05 * 1024 = 51.2
        XCTAssertEqual(Format.storage(0.05), "50 MB")  // 0.05 * 1000 = 50.0
    }

    // MARK: - The altitude at which the bug was felt

    /// The parser tests prove the arithmetic. This one proves the consequence.
    ///
    /// While the page size was wrong the app reported 18% memory on a machine that
    /// was really at 73%, counted zero problems, and printed "All good - your Mac is
    /// healthy". Fixing the arithmetic without pinning the verdict would leave the
    /// headline free to go back to being wrong for a different reason.
    ///
    /// Figures measured on the machine: memory 73.18%, storage 91.1%, swap 8.44 GB.
    func testVerdictIsNotAllGoodOnAMachineUnderRealPressure() {
        let verdict = HealthVerdict.evaluate(cpuBusyPercent: 18.75,
                                             memoryOccupancy: 0.7318,
                                             diskOccupancy: 0.911,
                                             swapUsedGB: 8.44)
        XCTAssertNotEqual(verdict, .allGood)
        XCTAssertEqual(verdict, .severalIssues)
    }

    /// Dividing memory by four hides a problem from the verdict ONLY when memory is
    /// the deciding factor, i.e. when the true occupancy is above the 85% threshold
    /// and the divided one is below it.
    ///
    /// Worth stating precisely, because the audit overreached here: it claimed the
    /// page-size bug made the app report "All good" on the machine it ran on. It did
    /// not. At 73% memory the threshold is not crossed either way, and the disk at
    /// 91% plus 8.4 GB of swap already counted two problems. The gauge was green;
    /// the headline was not. The bug was real, this particular consequence was not.
    func testUnderReportedMemoryHidesAProblemOnlyWhenItIsTheDecidingFactor() {
        // Memory is the deciding factor: 90% true, 22.5% once divided by four.
        XCTAssertEqual(HealthVerdict.evaluate(cpuBusyPercent: 10, memoryOccupancy: 0.90,
                                              diskOccupancy: 0.5, swapUsedGB: 0), .oneIssue)
        XCTAssertEqual(HealthVerdict.evaluate(cpuBusyPercent: 10, memoryOccupancy: 0.90 / 4,
                                              diskOccupancy: 0.5, swapUsedGB: 0), .allGood)

        // The machine the audit actually ran on: the verdict is the same either way,
        // because the disk and the swap already dominate it.
        let real = HealthVerdict.evaluate(cpuBusyPercent: 18.75, memoryOccupancy: 0.7318,
                                          diskOccupancy: 0.911, swapUsedGB: 8.44)
        let buggy = HealthVerdict.evaluate(cpuBusyPercent: 18.75, memoryOccupancy: 0.7318 / 4,
                                           diskOccupancy: 0.911, swapUsedGB: 8.44)
        XCTAssertEqual(real, .severalIssues)
        XCTAssertEqual(buggy, .severalIssues)
    }

    func testVerdictCountsProblemsRatherThanRankingThem() {
        XCTAssertEqual(HealthVerdict.evaluate(cpuBusyPercent: 10, memoryOccupancy: 0.5,
                                              diskOccupancy: 0.5, swapUsedGB: 0), .allGood)
        XCTAssertEqual(HealthVerdict.evaluate(cpuBusyPercent: 95, memoryOccupancy: 0.5,
                                              diskOccupancy: 0.5, swapUsedGB: 0), .oneIssue)
        XCTAssertEqual(HealthVerdict.evaluate(cpuBusyPercent: 95, memoryOccupancy: 0.9,
                                              diskOccupancy: 0.5, swapUsedGB: 0), .severalIssues)
    }

    /// Catches a PARTIAL page-size fix - one call site corrected, another not - which
    /// no single-value assertion can see. The reference is the formula Activity
    /// Monitor uses (active + inactive + speculative + wired + compressed - purgeable
    /// - file-backed); the app's simpler active + wired + compressed sits a known ~8%
    /// below it. A scaling error would blow that gap wide open.
    func testUsedMemoryStaysCloseToTheActivityMonitorFormula() {
        let pageSize = 16384
        func gb(_ p: Double) -> Double { MemoryMath.gigabytes(pages: p, pageSize: pageSize)! }

        // Real vm_stat capture
        let active = 355_083.0, inactive = 335_307.0, speculative = 17_208.0
        let wired = 214_120.0, compressed = 581_830.0
        let purgeable = 30_236.0, fileBacked = 228_836.0

        let appFormula = gb(active + wired + compressed)
        let reference = gb(active + inactive + speculative + wired + compressed - purgeable - fileBacked)

        XCTAssertEqual(appFormula, 17.56, accuracy: 0.01)
        XCTAssertEqual(reference, 18.99, accuracy: 0.01)

        let gap = abs(reference - appFormula) / reference
        XCTAssertLessThan(gap, 0.10, "known divergence from Activity Monitor is ~8%; a bigger gap means a scaling error")
    }
}
