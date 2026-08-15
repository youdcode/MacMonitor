import XCTest
@testable import MacMonitor

/// Tests for the shell-output parsers.
///
/// TRANSITIONAL, like the code it covers. The vm_stat, swapusage and system_profiler
/// tests have already gone, each in the same commit as the parser it covered. Only
/// ps remains, and only because a non-privileged process cannot read another user's
/// CPU time on macOS.
///
/// Fixtures are real output captured on the machine, trimmed where noted.
final class LegacyShellParsersTests: XCTestCase {

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
}
