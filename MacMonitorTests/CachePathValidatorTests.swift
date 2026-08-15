import XCTest
@testable import MacMonitor

/// The cleaner is the only code in the app that destroys anything, so the rule that
/// decides what it may touch is tested on its own, with no filesystem involved.
///
/// The validator works on the RESOLVED path. That matters: a symlink sitting inside
/// the cache directory looks entirely legitimate in a listing and can point anywhere.
final class CachePathValidatorTests: XCTestCase {

    private let cacheRoot = "/Users/tester/Library/Caches"
    private let derivedData = "/Users/tester/Library/Developer/Xcode/DerivedData"
    private var roots: [String] { [cacheRoot, derivedData] }

    private func validate(_ candidate: String, resolvedTo resolved: String? = nil)
        -> Result<String, CachePathValidator.Rejection> {
        CachePathValidator.validate(candidate: candidate,
                                    resolved: resolved ?? candidate,
                                    allowedRoots: roots)
    }

    // MARK: - Accepted

    func testItemDirectlyInsideACacheRootIsAccepted() {
        XCTAssertNoThrow(try validate("\(cacheRoot)/com.spotify.client").get())
        XCTAssertNoThrow(try validate("\(derivedData)/MacMonitor-abcdef").get())
    }

    func testDeeplyNestedItemInsideACacheRootIsAccepted() {
        XCTAssertNoThrow(try validate("\(cacheRoot)/com.foo.bar/Data/blobs").get())
    }

    // MARK: - Outside the allowed roots

    func testPathOutsideEveryCacheRootIsRejected() {
        XCTAssertEqual(rejection(for: "/Users/tester/Documents"), .outsideAllowedRoots)
        XCTAssertEqual(rejection(for: "/Users/tester/Library/Preferences"), .outsideAllowedRoots)
        XCTAssertEqual(rejection(for: "/System/Library/Caches"), .outsideAllowedRoots)
        XCTAssertEqual(rejection(for: "/"), .outsideAllowedRoots)
    }

    /// A sibling whose name merely starts with the root's is not inside it.
    func testSiblingDirectoryWithASharedPrefixIsRejected() {
        XCTAssertEqual(rejection(for: "/Users/tester/Library/CachesBackup/stuff"),
                       .outsideAllowedRoots)
    }

    // MARK: - Symlinks

    /// The path the user sees is inside the cache directory; what it points at is not.
    /// Validating the displayed path instead of the resolved one would trash the
    /// target.
    func testSymlinkInsideTheCacheRootThatEscapesItIsRejected() {
        let result = validate("\(cacheRoot)/looks-innocent",
                              resolvedTo: "/Users/tester/Documents/thesis")
        XCTAssertEqual(rejection(result), .outsideAllowedRoots)
    }

    func testSymlinkPointingToTheHomeDirectoryIsRejected() {
        let result = validate("\(cacheRoot)/com.evil.app", resolvedTo: "/Users/tester")
        XCTAssertEqual(rejection(result), .outsideAllowedRoots)
    }

    /// A symlink that stays inside the cache directory is fine.
    func testSymlinkResolvingBackInsideTheCacheRootIsAccepted() {
        let result = validate("\(cacheRoot)/alias", resolvedTo: "\(cacheRoot)/com.real.app")
        XCTAssertNoThrow(try result.get())
    }

    // MARK: - The roots themselves

    /// Selecting the cache directory itself would trash every cache at once,
    /// including the ones deliberately held back by the exclusion list.
    func testCacheRootItselfIsRejected() {
        XCTAssertEqual(rejection(for: cacheRoot), .isRootItself)
        XCTAssertEqual(rejection(for: derivedData), .isRootItself)
    }

    func testTrailingSlashDoesNotSmuggleTheRootThrough() {
        XCTAssertEqual(rejection(for: cacheRoot + "/"), .isRootItself)
    }

    // MARK: - Traversal and malformed input

    func testParentDirectoryTraversalIsRejected() {
        XCTAssertEqual(rejection(for: "\(cacheRoot)/../Preferences"), .containsParentTraversal)
        XCTAssertEqual(rejection(for: "\(cacheRoot)/com.foo/.."), .containsParentTraversal)
        XCTAssertEqual(rejection(for: "\(cacheRoot)/a/../../.."), .containsParentTraversal)
    }

    func testEmptyPathIsRejected() {
        XCTAssertEqual(rejection(for: ""), .empty)
        XCTAssertEqual(rejection(validate("\(cacheRoot)/x", resolvedTo: "")), .empty)
    }

    func testNoRootsMeansNothingIsAllowed() {
        let result = CachePathValidator.validate(candidate: "\(cacheRoot)/com.foo",
                                                 resolved: "\(cacheRoot)/com.foo",
                                                 allowedRoots: [])
        XCTAssertEqual(rejection(result), .outsideAllowedRoots)
    }

    // MARK: - The exclusion list

    /// Sensitive caches are held back by name. This is an exclusion list, not an
    /// inclusion list: an unrecognised cache is shown to the user, not hidden.
    func testSensitiveSystemCachesAreExcludedFromDiscovery() {
        XCTAssertTrue(CacheNaming.excluded.contains("icloudmailagent"))
        XCTAssertTrue(CacheNaming.excluded.contains("com.apple.nsurlsessiond"))
        XCTAssertTrue(CacheNaming.excluded.contains("com.apple.akd"))
    }

    func testOrdinaryApplicationCachesAreNotExcluded() {
        XCTAssertFalse(CacheNaming.excluded.contains("com.spotify.client"))
        XCTAssertFalse(CacheNaming.excluded.contains("Homebrew"))
        XCTAssertFalse(CacheNaming.excluded.contains("some.unknown.vendor.app"))
    }

    // MARK: - Naming

    func testUnrecognisedBundleIdentifierIsShownRatherThanHidden() {
        let described = CacheNaming.describe(directoryName: "com.unknown.vendor.tool")
        XCTAssertEqual(described.name, "com.unknown.vendor.tool")
        XCTAssertEqual(described.bundleID, "com.unknown.vendor.tool")
    }

    func testRecognisedCacheGetsAReadableName() {
        XCTAssertEqual(CacheNaming.describe(directoryName: "com.spotify.client").name, "Spotify")
    }

    // MARK: - The reported figure

    /// The original code added an item's size to the running total BEFORE deleting
    /// it, and swallowed the error with `try?`. The app could report gigabytes freed
    /// having removed nothing. Only a successful move may count.
    func testOnlySuccessfulRemovalsCountTowardsTheReportedTotal() {
        let report = CacheRemovalReport(outcomes: [
            .init(path: "/a", name: "A", sizeBytes: 1_000_000_000, result: .movedToTrash),
            .init(path: "/b", name: "B", sizeBytes: 5_000_000_000, result: .failed("permission denied")),
            .init(path: "/c", name: "C", sizeBytes: 3_000_000_000, result: .rejected("outside")),
        ])

        XCTAssertEqual(report.movedBytes, 1_000_000_000)
        XCTAssertEqual(report.failures.count, 2)
    }

    /// A dry run must never be reported as space moved.
    func testDryRunReportsNothingAsMoved() {
        let report = CacheRemovalReport(outcomes: [
            .init(path: "/a", name: "A", sizeBytes: 9_000_000_000, result: .wouldBeMovedToTrash),
        ], wasDryRun: true)

        XCTAssertEqual(report.movedBytes, 0)
        XCTAssertTrue(report.failures.isEmpty)
    }

    // MARK: - Helpers

    private func rejection(for path: String) -> CachePathValidator.Rejection? {
        rejection(validate(path))
    }

    private func rejection(_ result: Result<String, CachePathValidator.Rejection>)
        -> CachePathValidator.Rejection? {
        if case .failure(let r) = result { return r }
        return nil
    }
}
