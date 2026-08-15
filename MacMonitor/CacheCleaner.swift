import Foundation
import AppKit

// Cache discovery and removal.
//
// The app makes caches easy to find and easy to remove; deciding what to remove is
// the user's call. What the app owes them in exchange is that every number it shows
// is true, that mistakes are recoverable, and that it volunteers the one thing they
// cannot see for themselves - whether the owning application is running right now.

// MARK: - Path validation

/// Whether a path may be handed to the trash.
///
/// Pure and filesystem-free: the caller resolves symlinks and passes the result in,
/// so the rules can be tested without creating files. The check is on the RESOLVED
/// path, because a symlink sitting inside the cache directory can point anywhere.
enum CachePathValidator {

    enum Rejection: String, Error, Equatable {
        case outsideAllowedRoots = "path is not inside a known cache directory"
        case isRootItself = "path is a cache root, not an item inside one"
        case containsParentTraversal = "path contains a parent-directory traversal"
        case empty = "path is empty"
    }

    /// - Parameters:
    ///   - candidate: the path as displayed to the user.
    ///   - resolved: `candidate` with symlinks resolved. Pass `candidate` when it is
    ///     not a symlink.
    ///   - allowedRoots: cache directories items may live in, already resolved.
    static func validate(candidate: String,
                         resolved: String,
                         allowedRoots: [String]) -> Result<String, Rejection> {

        guard !candidate.isEmpty, !resolved.isEmpty else { return .failure(.empty) }
        guard !candidate.contains("/../"), !candidate.hasSuffix("/..") else {
            return .failure(.containsParentTraversal)
        }

        let normalisedResolved = normalise(resolved)

        for root in allowedRoots {
            let normalisedRoot = normalise(root)
            if normalisedResolved == normalisedRoot { return .failure(.isRootItself) }
            if normalisedResolved.hasPrefix(normalisedRoot + "/") { return .success(resolved) }
        }

        return .failure(.outsideAllowedRoots)
    }

    private static func normalise(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}

// MARK: - Naming

/// Turns a cache directory name into something a human recognises.
///
/// Most cache directories are named after a bundle identifier. A short table covers
/// the ones worth naming; everything else shows its bundle identifier rather than
/// being hidden, because a cache the app does not recognise is still the user's to
/// inspect.
enum CacheNaming {

    private static let known: [String: (name: String, icon: String)] = [
        "com.apple.Safari": ("Safari", "safari"),
        "com.apple.Music": ("Music", "music.note"),
        "com.apple.amp.mediasharingd": ("Media Sharing", "music.note"),
        "com.google.Chrome": ("Google Chrome", "globe"),
        "Google": ("Google", "globe"),
        "com.microsoft.VSCode": ("Visual Studio Code", "chevron.left.forwardslash.chevron.right"),
        "com.spotify.client": ("Spotify", "music.note"),
        "com.tinyspeck.slackmacgap": ("Slack", "number"),
        "com.hnc.Discord": ("Discord", "bubble.left"),
        "ru.keepcoder.Telegram": ("Telegram", "paperplane"),
        "com.figma.Desktop": ("Figma", "pencil.and.outline"),
        "Homebrew": ("Homebrew", "shippingbox"),
        "pip": ("pip", "chevron.left.forwardslash.chevron.right"),
        "Adobe": ("Adobe", "paintbrush"),
        "Yarn": ("Yarn", "chevron.left.forwardslash.chevron.right"),
        "go-build": ("Go build cache", "chevron.left.forwardslash.chevron.right"),
        "typescript": ("TypeScript", "chevron.left.forwardslash.chevron.right"),
    ]

    static func describe(directoryName: String) -> (name: String, icon: String, bundleID: String?) {
        if let hit = known[directoryName] {
            return (hit.name, hit.icon, directoryName.contains(".") ? directoryName : nil)
        }
        // Looks like a bundle identifier: show it as-is, it is the most honest label.
        if directoryName.contains("."), directoryName.split(separator: ".").count >= 3 {
            return (directoryName, "shippingbox", directoryName)
        }
        return (directoryName, "folder", nil)
    }

    /// Cache directories that are excluded from the list.
    ///
    /// An exclusion list rather than an inclusion list: the app should not decide
    /// which of the user's caches are worth showing. These specific ones are held
    /// back because removing them logs accounts out, drops queued mail, or makes
    /// system services re-download data over a metered connection - consequences a
    /// user cannot reasonably infer from a directory name.
    static let excluded: Set<String> = [
        "com.apple.akd",                    // Apple ID authentication
        "com.apple.ap.adprivacyd",
        "com.apple.appstore",
        "com.apple.appstoreagent",
        "com.apple.commerce",
        "com.apple.containermanagerd",
        "com.apple.iCloudHelper",
        "com.apple.icloud.searchpartyd",
        "com.apple.imfoundation",           // Messages
        "com.apple.keychainaccess",
        "com.apple.Messages",
        "com.apple.nsurlsessiond",          // in-flight background downloads
        "com.apple.passd",
        "CloudKit",
        "icloudmailagent",                  // queued mail not yet on the server
        "FamilyCircle",
        "SiriTTS",
    ]
}

// MARK: - Removal

struct CacheRemovalOutcome: Identifiable, Equatable {
    enum Result: Equatable {
        case movedToTrash
        case wouldBeMovedToTrash      // dry run
        case rejected(String)         // path validation refused it
        case failed(String)           // the filesystem refused it
    }

    var id: String { path }
    let path: String
    let name: String
    let sizeBytes: Int64
    let result: Result

    /// Only a real, successful move counts towards the reported figure.
    var reclaimedBytes: Int64 { result == .movedToTrash ? sizeBytes : 0 }
}

struct CacheRemovalReport: Equatable {
    var outcomes: [CacheRemovalOutcome] = []
    var wasDryRun: Bool = false

    /// Bytes actually moved to the trash.
    ///
    /// Note this is bytes MOVED, not bytes freed on the volume: the trash sits on
    /// the same filesystem, so nothing is reclaimed until it is emptied. The UI says
    /// so rather than claiming free space it has not created.
    var movedBytes: Int64 { outcomes.reduce(0) { $0 + $1.reclaimedBytes } }
    var failures: [CacheRemovalOutcome] { outcomes.filter { if case .movedToTrash = $0.result { return false }; if case .wouldBeMovedToTrash = $0.result { return false }; return true } }
}
