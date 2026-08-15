import Foundation

// Transitional: these parse the textual output of shell commands.
//
// They are scheduled to be replaced by native APIs — host_statistics64 for memory,
// sysctlbyname("vm.swapusage") with xsw_usage for swap, a native process listing
// for ps. When that lands, delete this file and its tests in the same commit
// rather than leaving tested code that nothing calls.
//
// Every function returns an optional and fails explicitly on unparseable input.
// The original code used `?? 0` throughout, so a format change produced a
// confident zero instead of an error.

// MARK: - vm_stat

struct VMStatPages: Equatable {
    var free: Double
    var active: Double
    var inactive: Double
    var wired: Double
    /// Pages of physical RAM held by the compressor.
    ///
    /// vm_stat prints two lines containing the word "compressor":
    ///   "Pages stored in compressor"    — uncompressed size of what it holds
    ///   "Pages occupied by compressor"  — physical RAM it actually uses
    /// Only the second is memory in use. Matching on the substring "compressor"
    /// picks whichever comes last, which is right only by accident.
    var occupiedByCompressor: Double
}

enum VMStatParser {

    static func parse(_ output: String) -> VMStatPages? {
        var values: [String: Double] = [:]

        for line in output.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: ":")
            guard parts.count >= 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let raw = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " ."))
            guard let value = Double(raw) else { continue }
            values[key] = value
        }

        guard let free = values["Pages free"],
              let active = values["Pages active"],
              let inactive = values["Pages inactive"],
              let wired = values["Pages wired down"],
              let occupied = values["Pages occupied by compressor"] else { return nil }

        return VMStatPages(free: free,
                           active: active,
                           inactive: inactive,
                           wired: wired,
                           occupiedByCompressor: occupied)
    }
}

// MARK: - sysctl vm.swapusage

enum SwapUsageParser {

    /// Parses `sysctl vm.swapusage`, whose output looks like:
    /// `vm.swapusage: total = 4096.00M  used = 2772.75M  free = 1323.25M  (encrypted)`
    /// Returns gigabytes.
    static func parse(_ output: String) -> (used: Double, total: Double)? {
        func megabytes(_ field: String) -> Double? {
            guard let range = output.range(of: "\(field) = [0-9]+\\.?[0-9]*M", options: .regularExpression) else { return nil }
            let digits = output[range]
                .replacingOccurrences(of: "\(field) = ", with: "")
                .replacingOccurrences(of: "M", with: "")
            return Double(digits)
        }

        guard let used = megabytes("used"), let total = megabytes("total") else { return nil }
        return (used / 1024, total / 1024)
    }
}

// MARK: - ps

struct PSRow: Equatable {
    var pid: Int32
    var cpuPercent: Double
    var memoryPercent: Double
    var command: String
}

enum PSParser {

    /// Parses one row of `ps aux`.
    ///
    /// Returns nil for the header row and for anything else that does not carry a
    /// numeric pid. Callers must NOT drop the first line to skip the header: once
    /// the output has been through `sort`, the header is sorted along with the rows
    /// and lands in the middle, so dropping line one discards a real process — the
    /// busiest one, given the sort order.
    static func parseRow(_ line: String) -> PSRow? {
        let parts = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: true)
        guard parts.count >= 11,
              let pid = Int32(parts[1]),
              let cpu = Double(parts[2]),
              let mem = Double(parts[3]) else { return nil }

        let path = String(parts[10])
        let command = path.components(separatedBy: "/").last ?? path

        return PSRow(pid: pid, cpuPercent: cpu, memoryPercent: mem, command: command)
    }

    /// Parses full `ps aux` output, keeping every genuine process row in order.
    static func parse(_ output: String) -> [PSRow] {
        output.components(separatedBy: "\n").compactMap(parseRow)
    }
}

// MARK: - system_profiler SPPowerDataType

enum BatteryStaticParser {

    /// Extracts cycle count and condition.
    ///
    /// The keys are matched in English. system_profiler localises its output, so on
    /// a fully localised system this returns nil rather than a confident zero.
    static func parse(_ output: String) -> (cycleCount: Int, condition: String)? {
        var cycles: Int?
        var condition: String?

        for line in output.components(separatedBy: "\n") {
            guard let value = line.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespaces),
                  !value.isEmpty else { continue }
            if line.contains("Cycle Count") { cycles = Int(value) }
            if line.contains("Condition") { condition = value }
        }

        guard let cycles, let condition else { return nil }
        return (cycles, condition)
    }
}
