import Foundation

// Pure, dependency-free computation used by the collectors.
//
// Everything here takes plain values in and returns plain values out, with no I/O
// and no shared state, so it can be tested against fixed inputs. This is the layer
// where the measurement bugs lived: the collectors mostly move bytes around, the
// arithmetic is what got them wrong.

// MARK: - Memory

enum MemoryMath {

    /// Converts a page count to binary gigabytes.
    ///
    /// The page size MUST be supplied by the caller and read from the kernel at
    /// runtime. It is 4096 bytes on Intel and 16384 on Apple Silicon; assuming
    /// either one under- or over-reports memory by a factor of four on the other
    /// architecture.
    ///
    /// Returns nil for a non-positive page size or a negative page count, rather
    /// than silently yielding zero.
    static func gigabytes(pages: Double, pageSize: Int) -> Double? {
        guard pageSize > 0, pages >= 0 else { return nil }
        return pages * Double(pageSize) / 1_073_741_824
    }
}

// MARK: - CPU

enum CPUMath {

    /// Aggregate CPU tick counters, in the order host_cpu_load_info reports them.
    struct Ticks: Equatable {
        var user: UInt32
        var system: UInt32
        var idle: UInt32
        var nice: UInt32
    }

    struct Load: Equatable {
        var user: Double
        var system: Double
        var idle: Double
    }

    /// Percentages for the interval between two tick samples.
    ///
    /// Returns nil when there is nothing meaningful to report: no previous sample,
    /// or two samples taken so close together that no tick elapsed. Callers must
    /// publish nothing in that case - reporting the delta against a zero baseline
    /// would surface the average since boot as if it were an instant reading.
    ///
    /// Subtraction wraps deliberately: the counters are UInt32 and roll over roughly
    /// every 41 days at 1200 ticks/second.
    static func load(current: Ticks, previous: Ticks?) -> Load? {
        guard let previous else { return nil }

        let dUser = Double(current.user &- previous.user)
        let dSystem = Double(current.system &- previous.system)
        let dIdle = Double(current.idle &- previous.idle)
        let dNice = Double(current.nice &- previous.nice)

        let total = dUser + dSystem + dIdle + dNice
        guard total > 0 else { return nil }

        // nice time is user time that was re-prioritised; Activity Monitor folds it
        // into the user figure and so do we.
        return Load(user: (dUser + dNice) / total * 100,
                    system: dSystem / total * 100,
                    idle: dIdle / total * 100)
    }
}

// MARK: - Uptime

enum UptimeFormatter {

    /// Formats an elapsed number of seconds as a short uptime string.
    ///
    /// Days are kept separate from hours. Collapsing them, as splitting the output
    /// of `uptime` on its comma does, loses the hours entirely past the first day.
    ///
    /// Returns nil for a non-positive duration.
    static func string(seconds: Int) -> String? {
        guard seconds > 0 else { return nil }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

// MARK: - Overall verdict

enum HealthVerdict: Equatable {
    case allGood
    case oneIssue
    case severalIssues

    /// The headline the Overview tab shows.
    ///
    /// This is the altitude at which a measurement bug is actually felt: while the
    /// page size was wrong the memory figure came out four times too small, this
    /// counted zero problems, and the app told a machine at ~73% memory, 91% disk
    /// and 84% swap that everything was fine.
    static func evaluate(cpuBusyPercent: Double,
                         memoryOccupancy: Double,
                         diskOccupancy: Double,
                         swapUsedGB: Double) -> HealthVerdict {
        let issues = [
            cpuBusyPercent > 80,
            memoryOccupancy > 0.85,
            diskOccupancy > 0.90,
            swapUsedGB > 1.0
        ].filter { $0 }.count

        switch issues {
        case 0: return .allGood
        case 1: return .oneIssue
        default: return .severalIssues
        }
    }
}
