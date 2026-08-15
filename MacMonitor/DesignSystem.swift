import SwiftUI

// The shared vocabulary of the interface: thresholds, scales, number formatting.
//
// Every one of these existed before as a literal repeated across views, which is how
// the same idea ended up with four different values. "Storage almost full" was 80%,
// 85%, 90% and "under 10 GB" depending on which file you read.

// MARK: - Thresholds

enum Threshold {

    /// Occupancy at which a resource stops being comfortable and starts being worth
    /// looking at. One value, used by the gauges, the row colours and the verdict.
    static let warning = 0.75
    static let critical = 0.90

    /// Storage has a second, absolute condition: a nearly-full percentage on a small
    /// disk is less urgent than a handful of gigabytes left on a large one.
    static let lowStorageBytes: Int64 = 10_000_000_000

    /// Swap in use beyond this is worth surfacing, in gigabytes.
    static let swapWarningGB = 1.0

    /// Battery cycles. Apple rates most recent portables for 1000.
    static let batteryCycleWarning = 800
    static let batteryCycleRating = 1000

    /// Below this, a process is not worth a row.
    static let processCPUFloor = 0.1
}

// MARK: - Status

/// Where a value sits relative to its thresholds.
///
/// Carries a shape as well as a colour: colour alone is not readable by everyone, and
/// the audit flagged it in several places. The symbol travels with the colour so the
/// two can never disagree.
enum Status {
    case normal, warning, critical

    static func forOccupancy(_ value: Double) -> Status {
        if value >= Threshold.critical { return .critical }
        if value >= Threshold.warning { return .warning }
        return .normal
    }

    var colour: Color {
        switch self {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    /// Redundant encoding for the colour, so the state survives greyscale, a
    /// colour-blind reader, or a screenshot printed in black and white.
    var symbol: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Battery colour

/// Single definition. This function existed twice, identically, in two files.
func batteryStatusColour(percentage: Int, isCharging: Bool) -> Color {
    if isCharging { return .green }
    if percentage > 50 { return .green }
    if percentage > 20 { return .orange }
    return .red
}

// MARK: - Number formatting

// One decimal rule per family of unit, applied everywhere. Live numbers all carry
// .monospacedDigit() at the point of display: without it every digit change shifts
// the layout and the whole window twitches twice a second.

enum Format {

    /// Percentages, 0-100. No decimals: a monitor refreshing twice a second cannot
    /// meaningfully show tenths, and they are what makes the eye chase the number.
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// A 0-1 ratio as a percentage.
    static func percent(ratio: Double) -> String {
        percent(ratio * 100)
    }

    /// Memory, in binary gigabytes, which is how the hardware and the kernel count.
    static func memory(_ gigabytes: Double) -> String {
        if gigabytes < 0.1 { return "\(Int(gigabytes * 1024)) MB" }
        return String(format: "%.1f GB", gigabytes)
    }

    /// Storage, in decimal gigabytes, which is how Finder and System Settings count.
    static func storage(_ gigabytes: Double) -> String {
        if gigabytes < 0.1 { return "\(Int(gigabytes * 1000)) MB" }
        return String(format: "%.1f GB", gigabytes)
    }

    /// A raw byte count, decimal, the way Finder shows file sizes.
    static func bytes(_ count: Int64) -> String {
        let gb = Double(count) / 1_000_000_000
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return "\(count / 1_000_000) MB"
    }

    /// Throughput. Whole units: the third decimal of a transfer rate is noise.
    static func rate(_ bytesPerSecond: Double) -> String {
        let b = max(bytesPerSecond, 0)
        if b >= 1_000_000 { return String(format: "%.1f MB/s", b / 1_000_000) }
        if b >= 1_000 { return "\(Int(b / 1_000)) KB/s" }
        return "0 KB/s"
    }

    /// Load averages and other bare numbers, two decimals as `uptime` prints them.
    static func decimal(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

// MARK: - Sparkline scale

/// The range a sparkline should plot against.
///
/// Sparkline used to normalise on whatever maximum happened to be in its own data,
/// which made a CPU idling at 3% look exactly like one pinned at 90%. It was also fed
/// percentages, 0-1 ratios and a 0-100 state code by three different callers, with no
/// way to tell them apart. The caller now says what the numbers mean.
enum SparklineScale: Equatable {
    /// Fixed 0-100. Use for anything that is already a percentage.
    case percent
    /// Fixed 0-1. Use for ratios.
    case ratio
    /// Normalise on the data's own maximum. Use only where there is no natural
    /// ceiling, such as a throughput curve.
    case relative

    func upperBound(for data: [Double]) -> Double {
        switch self {
        case .percent: return 100
        case .ratio: return 1
        case .relative:
            let maximum = data.max() ?? 1
            return maximum < 0.0001 ? 1 : maximum
        }
    }
}
