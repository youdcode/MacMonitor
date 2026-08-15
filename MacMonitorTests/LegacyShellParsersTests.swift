import XCTest
@testable import MacMonitor

/// Tests for the shell-output parsers.
///
/// TRANSITIONAL, like the code they cover: when the collectors move to native APIs
/// (host_statistics64, xsw_usage, a native process listing) both LegacyShellParsers
/// and this file are deleted in the same commit. Leaving green tests behind for code
/// nothing calls would be worse than having no tests at all.
///
/// Fixtures are real output captured on the machine, trimmed where noted.
final class LegacyShellParsersTests: XCTestCase {

    // MARK: - vm_stat

    /// Real `vm_stat` output. Note the two lines containing the word "compressor":
    /// only "Pages occupied by compressor" is physical RAM in use.
    private let vmStatFixture = """
    Mach Virtual Memory Statistics: (page size of 16384 bytes)
    Pages free:                                    31238.
    Pages active:                                 360529.
    Pages inactive:                               357818.
    Pages speculative:                              6171.
    Pages throttled:                                   0.
    Pages wired down:                             207477.
    Pages purgeable:                               22817.
    "Translation faults":                      230865869.
    Pages copy-on-write:                         5146221.
    File-backed pages:                            282521.
    Anonymous pages:                              575655.
    Pages stored in compressor:                  1163012.
    Pages occupied by compressor:                 500656.
    Decompressions:                              8598299.
    Compressions:                               15014891.
    """

    func testVMStatParsesThePageCounts() {
        let pages = VMStatParser.parse(vmStatFixture)

        XCTAssertEqual(pages?.free, 31_238)
        XCTAssertEqual(pages?.active, 360_529)
        XCTAssertEqual(pages?.inactive, 357_818)
        XCTAssertEqual(pages?.wired, 207_477)
    }

    /// The original code matched on the substring "compressor", which hits two lines.
    /// The loop overwrote, so the last one won - correct only by accident, and only
    /// as long as vm_stat keeps printing them in that order.
    func testCompressorFigureIsPagesOccupiedNotPagesStored() {
        let pages = VMStatParser.parse(vmStatFixture)

        XCTAssertEqual(pages?.occupiedByCompressor, 500_656)
        XCTAssertNotEqual(pages?.occupiedByCompressor, 1_163_012)
    }

    /// Same fixture, with the two compressor lines swapped. A substring match would
    /// now pick the wrong one; an exact key match is unaffected.
    func testCompressorFigureIsCorrectWhateverTheLineOrder() {
        let swapped = vmStatFixture
            .replacingOccurrences(of: "Pages stored in compressor:                  1163012.",
                                  of2: "Pages occupied by compressor:                 500656.")

        XCTAssertEqual(VMStatParser.parse(swapped)?.occupiedByCompressor, 500_656)
    }

    /// "Pages reactivated" contains the substring "active", and vm_stat prints it
    /// after "Pages active". A substring matcher would report 33.5M reactivated
    /// pages as active memory - 511 GB on a 24 GB machine. The same trap exists for
    /// "Pages purgeable" versus "Pages purged". Exact key matching is what prevents
    /// the compressor bug from having siblings.
    func testKeysThatContainOtherKeysAreNotConfused() {
        let fixture = vmStatFixture + "\nPages reactivated:                          33503395.\nPages purged:                                6004632."
        let pages = VMStatParser.parse(fixture)

        XCTAssertEqual(pages?.active, 360_529)
        XCTAssertNotEqual(pages?.active, 33_503_395)
    }

    func testVMStatFailsOnEmptyOrTruncatedOutput() {
        XCTAssertNil(VMStatParser.parse(""))
        XCTAssertNil(VMStatParser.parse("Mach Virtual Memory Statistics: (page size of 16384 bytes)"))
        // Header plus one line: still missing the fields we need.
        XCTAssertNil(VMStatParser.parse("Pages free:  31238."))
    }

    func testVMStatFailsOnGarbage() {
        XCTAssertNil(VMStatParser.parse("command not found"))
        XCTAssertNil(VMStatParser.parse("Pages free: not-a-number."))
    }

    // MARK: - sysctl vm.swapusage

    func testSwapUsageParsesUsedAndTotalInGigabytes() {
        let fixture = "vm.swapusage: total = 10240.00M  used = 8571.12M  free = 1668.88M  (encrypted)"
        let swap = SwapUsageParser.parse(fixture)

        XCTAssertEqual(swap?.total ?? 0, 10.0, accuracy: 0.001)   // 10240 / 1024
        XCTAssertEqual(swap?.used ?? 0, 8.3702, accuracy: 0.001)  // 8571.12 / 1024
    }

    /// "used" must not be confused with "total" or "free" - all three share the
    /// same shape, and the used figure is the one the pressure alert keys off.
    func testSwapUsageDoesNotConfuseUsedWithFree() {
        let fixture = "vm.swapusage: total = 4096.00M  used = 0.00M  free = 4096.00M  (encrypted)"
        let swap = SwapUsageParser.parse(fixture)

        XCTAssertEqual(swap?.used ?? -1, 0.0)
        XCTAssertEqual(swap?.total ?? 0, 4.0, accuracy: 0.001)
    }

    func testSwapUsageFailsOnEmptyOrMalformedOutput() {
        XCTAssertNil(SwapUsageParser.parse(""))
        XCTAssertNil(SwapUsageParser.parse("vm.swapusage: total = 4096.00M"))       // no used
        XCTAssertNil(SwapUsageParser.parse("vm.swapusage: total = ?  used = ?"))
    }

    // MARK: - ps

    /// Real output of `ps aux | sort -rk3 | head -4`, the exact pipeline the app runs.
    /// The header is on line FOUR, not line one, because `sort` sorted it along with
    /// the rows. The original code called dropFirst() to skip "the header" and so
    /// discarded WindowServer at 34.2%, the busiest process on the machine.
    private let psFixture = """
    _windowserver      402  34.2  0.5 438477600 127008   ??  Rs   Fri08AM 232:02.44 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
    younes           94734  28.0  0.9 436597056 234432   ??  R    12:47PM   0:17.84 /System/Library/Services/AppleSpell.service/Contents/MacOS/AppleSpell
    younes           36860  23.6  2.4 441161552 608816 s011  S+   10:53PM  15:31.13 claude
    USER               PID  %CPU %MEM      VSZ    RSS   TT  STAT STARTED      TIME COMMAND
    """

    func testTopProcessSurvivesWhenTheHeaderIsNotOnTheFirstLine() {
        let rows = PSParser.parse(psFixture)

        XCTAssertEqual(rows.first?.command, "WindowServer")
        XCTAssertEqual(rows.first?.cpuPercent, 34.2)
        XCTAssertEqual(rows.first?.pid, 402)
    }

    /// The header carries no numeric pid, so it must be rejected wherever it sits.
    func testHeaderRowIsRejected() {
        let header = "USER               PID  %CPU %MEM      VSZ    RSS   TT  STAT STARTED      TIME COMMAND"
        XCTAssertNil(PSParser.parseRow(header))

        // and it does not survive a full parse either
        XCTAssertEqual(PSParser.parse(psFixture).count, 3)
        XCTAssertFalse(PSParser.parse(psFixture).contains { $0.command == "COMMAND" })
    }

    func testProcessNameIsTheLastPathComponent() {
        let rows = PSParser.parse(psFixture)
        XCTAssertEqual(rows.map(\.command), ["WindowServer", "AppleSpell", "claude"])
    }

    func testProcessRowsKeepTheirCPUAndMemoryPercentages() {
        let rows = PSParser.parse(psFixture)
        XCTAssertEqual(rows.map(\.cpuPercent), [34.2, 28.0, 23.6])
        XCTAssertEqual(rows.map(\.memoryPercent), [0.5, 0.9, 2.4])
    }

    func testProcessParserFailsOnEmptyTruncatedOrGarbageRows() {
        XCTAssertNil(PSParser.parseRow(""))
        XCTAssertNil(PSParser.parseRow("younes 402 34.2"))            // too few columns
        XCTAssertNil(PSParser.parseRow("not a process line at all"))
        XCTAssertEqual(PSParser.parse("").count, 0)
    }

    // MARK: - system_profiler SPPowerDataType

    func testBatteryStaticParsesCycleCountAndCondition() {
        let fixture = """
                  Cycle Count: 513
                  Condition: Normal
        """
        let info = BatteryStaticParser.parse(fixture)

        XCTAssertEqual(info?.cycleCount, 513)
        XCTAssertEqual(info?.condition, "Normal")
    }

    /// system_profiler localises its output. When the English keys are absent the
    /// parser must say so, rather than reporting a battery with zero cycles in
    /// perfect condition - which is what the original `?? 0` produced.
    func testBatteryStaticFailsWhenTheEnglishKeysAreAbsent() {
        let localised = """
                  Nombre de cycles: 513
                  Etat: Normal
        """
        XCTAssertNil(BatteryStaticParser.parse(localised))
    }

    func testBatteryStaticFailsOnEmptyOrPartialOutput() {
        XCTAssertNil(BatteryStaticParser.parse(""))
        XCTAssertNil(BatteryStaticParser.parse("          Cycle Count: 513"))   // no condition
        XCTAssertNil(BatteryStaticParser.parse("          Condition: Normal"))  // no cycles
    }
}

private extension String {
    /// Swaps two substrings with each other.
    func replacingOccurrences(of a: String, of2 b: String) -> String {
        replacingOccurrences(of: a, with: "\u{0}TMP\u{0}")
            .replacingOccurrences(of: b, with: a)
            .replacingOccurrences(of: "\u{0}TMP\u{0}", with: b)
    }
}
