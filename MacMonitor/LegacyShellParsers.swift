import Foundation

// Transitional: what is left of the shell-output parsing.
//
// The vm_stat and vm.swapusage parsers that lived here are gone, replaced by
// host_statistics64 and xsw_usage. Their tests went with them, in the same commit,
// rather than staying green over code nothing calls.
//
// The two below cannot go yet:
//
// - ps. A non-privileged process cannot read another user's CPU time on macOS.
//   proc_pid_rusage and proc_pidinfo both return -1 for a process it does not own
//   (measured against launchd and WindowServer), and kinfo_proc.kp_proc.p_pctcpu is
//   not populated at all: zero for all 609 processes on this machine. /bin/ps only
//   manages it because it is setuid root. Going native here would silently drop
//   every system process from the list, which is worse than spawning one process
//   every two seconds.
//
// - system_profiler, for the battery cycle count and condition. Replaceable by
//   IORegistry, which is the next lot.
//
// Both return an optional and fail explicitly on unparseable input. The original
// code used ?? 0 throughout, so a format change produced a confident zero.

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
    /// and lands in the middle, so dropping line one discards a real process - the
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
