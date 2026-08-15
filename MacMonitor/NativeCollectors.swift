import Foundation
import IOKit
import os

// Native readers for the metrics that used to be scraped from shell output, plus the
// ones the app did not measure at all.
//
// Every collector here is a plain function over kernel state: no Process, no pipes,
// no parsing. The app used to spawn about five processes a second to watch a machine,
// which showed up in its own CPU figure.
//
// Logging policy: paths, process names and identifiers are .private, so they are
// redacted in the unified log. Counts, error codes and API names are .public. The
// happy path is .debug and stays quiet; only failures are .error. A collector running
// at 0.5 Hz must not write to the log in normal operation.
let collectorLog = Logger(subsystem: "io.github.youdcode.macmonitor", category: "collectors")

// MARK: - Memory

struct MemorySample: Equatable {
    var totalBytes: UInt64
    var activeBytes: UInt64
    var inactiveBytes: UInt64
    var wiredBytes: UInt64
    var compressedBytes: UInt64
    var speculativeBytes: UInt64
    var purgeableBytes: UInt64
    var externalBytes: UInt64
    var internalBytes: UInt64

    /// active + wired + compressed, the figure the app has always shown.
    var usedBytes: UInt64 { activeBytes + wiredBytes + compressedBytes }

    /// What Activity Monitor calls Memory Used. Kept alongside the simpler figure so
    /// the ~8% gap between the two is visible rather than argued about.
    var activityMonitorUsedBytes: UInt64 {
        let sum = activeBytes + inactiveBytes + speculativeBytes + wiredBytes + compressedBytes
        let subtract = purgeableBytes + externalBytes
        return sum > subtract ? sum - subtract : sum
    }

    var occupancy: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
}

enum MemoryPressure: Int32, Equatable {
    case normal = 1
    case warning = 2
    case critical = 4

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

enum NativeMemory {

    /// Replaces parsing `vm_stat`.
    ///
    /// host_statistics64 returns typed fields, which removes a whole class of bug:
    /// vm_stat prints two lines containing the word "compressor" and only one of them
    /// is physical RAM. Here it is simply `compressor_page_count`.
    static func sample() -> MemorySample? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            collectorLog.error("host_statistics64 failed, kern_return \(result, privacy: .public)")
            return nil
        }

        guard let total = physicalMemoryBytes() else { return nil }

        // The page size is read at runtime. It is 4 KB on Intel and 16 KB on Apple
        // Silicon; a constant is wrong on one of the two. The conversion goes through
        // MemoryMath so the arithmetic stays covered by the tests that caught the
        // original factor-of-four bug, rather than being reimplemented here.
        let pageSize = Int(vm_page_size)
        func bytes(_ pages: UInt32) -> UInt64 {
            let gib = MemoryMath.gigabytes(pages: Double(pages), pageSize: pageSize) ?? 0
            return UInt64(gib * 1_073_741_824)
        }

        return MemorySample(totalBytes: total,
                            activeBytes: bytes(stats.active_count),
                            inactiveBytes: bytes(stats.inactive_count),
                            wiredBytes: bytes(stats.wire_count),
                            compressedBytes: bytes(stats.compressor_page_count),
                            speculativeBytes: bytes(stats.speculative_count),
                            purgeableBytes: bytes(stats.purgeable_count),
                            externalBytes: bytes(stats.external_page_count),
                            internalBytes: bytes(stats.internal_page_count))
    }

    static func physicalMemoryBytes() -> UInt64? {
        var bytes: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &bytes, &size, nil, 0) == 0, bytes > 0 else {
            collectorLog.error("sysctl hw.memsize failed")
            return nil
        }
        return bytes
    }

    /// Replaces parsing `sysctl vm.swapusage`. Values are bytes, not a "1234.56M" string.
    static func swap() -> (usedBytes: UInt64, totalBytes: UInt64)? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else {
            collectorLog.error("sysctl vm.swapusage failed")
            return nil
        }
        return (usage.xsu_used, usage.xsu_total)
    }

    /// The real memory pressure level, as opposed to an occupancy ratio named
    /// "pressure". This is what macOS itself acts on.
    static func pressure() -> MemoryPressure? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return nil
        }
        return MemoryPressure(rawValue: level) ?? .normal
    }
}

// MARK: - CPU

enum NativeCPU {

    /// One, three and fifteen minute load averages.
    ///
    /// They were already in the output of `uptime` and thrown away.
    static func loadAverages() -> (one: Double, five: Double, fifteen: Double)? {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else { return nil }
        return (loads[0], loads[1], loads[2])
    }

    struct ClusterLoad: Equatable {
        var performance: Double?
        var efficiency: Double?
    }

    /// Per-core ticks, split by cluster.
    ///
    /// The mapping is read from the IORegistry, not inferred from hw.perflevel*.
    /// Those sysctls give core COUNTS only, and their numbering is the reverse of the
    /// CPU index order: perflevel0 is Performance, yet on an M4 Pro cores 0-3 are the
    /// efficiency cores and 4-11 the performance ones. Assuming "the first N are P"
    /// labels every core backwards.
    static func clusterTypes() -> [Character] {
        var types: [Int: Character] = [:]

        // The CPU nodes are in the IODeviceTree plane, NOT the IOService plane:
        // IOServiceGetMatchingServices("AppleARMCPU") returns zero matches. Measured
        // on an M4 Pro, this yields EEEEPPPPPPPP - four efficiency cores first, then
        // eight performance ones, which is the opposite end from what hw.perflevel0
        // (Performance, 8) would suggest to anyone indexing from zero.
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(root, kIODeviceTreePlane,
                                            IOOptionBits(kIORegistryIterateRecursively),
                                            &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            guard let typeRef = IORegistryEntryCreateCFProperty(entry, "cluster-type" as CFString, kCFAllocatorDefault, 0),
                  let typeData = typeRef.takeRetainedValue() as? Data,
                  let letter = String(data: typeData, encoding: .utf8)?
                      .trimmingCharacters(in: CharacterSet(charactersIn: "\0")).first,
                  let idRef = IORegistryEntryCreateCFProperty(entry, "logical-cpu-id" as CFString, kCFAllocatorDefault, 0),
                  let id = (idRef.takeRetainedValue() as? NSNumber)?.intValue
            else { continue }
            types[id] = letter
        }

        guard let highest = types.keys.max() else { return [] }
        return (0...highest).map { types[$0] ?? "?" }
    }

    /// Per-core busy percentages for the interval between two samples.
    static func perCoreTicks() -> [CPUMath.Ticks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }

        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        return (0..<Int(cpuCount)).map { core in
            let base = core * Int(CPU_STATE_MAX)
            return CPUMath.Ticks(user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                                 system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                                 idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                                 nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
        }
    }

    /// Averages the busy percentage of the cores in each cluster.
    static func clusterLoad(current: [CPUMath.Ticks],
                            previous: [CPUMath.Ticks]?,
                            types: [Character]) -> ClusterLoad {
        guard let previous, previous.count == current.count, types.count == current.count else {
            return ClusterLoad(performance: nil, efficiency: nil)
        }

        var perf: [Double] = []
        var eff: [Double] = []

        for (index, ticks) in current.enumerated() {
            guard let load = CPUMath.load(current: ticks, previous: previous[index]) else { continue }
            let busy = load.user + load.system
            if types[index] == "P" { perf.append(busy) } else if types[index] == "E" { eff.append(busy) }
        }

        func mean(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        return ClusterLoad(performance: mean(perf), efficiency: mean(eff))
    }
}

// MARK: - GPU

struct GPUSample: Equatable {
    var deviceUtilization: Double?
    var rendererUtilization: Double?
    var tilerUtilization: Double?
    var inUseMemoryBytes: UInt64?
}

enum NativeGPU {

    /// Reads PerformanceStatistics from the accelerator in the IORegistry.
    ///
    /// The GPU is the one large block of silicon the app never looked at, and on
    /// Apple Silicon it is often the actual bottleneck.
    static func sample() -> GPUSample? {
        let matching = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties = unmanaged?.takeRetainedValue() as? [String: Any],
                  let stats = properties["PerformanceStatistics"] as? [String: Any] else { continue }

            func percent(_ key: String) -> Double? { (stats[key] as? NSNumber)?.doubleValue }

            let sample = GPUSample(deviceUtilization: percent("Device Utilization %"),
                                   rendererUtilization: percent("Renderer Utilization %"),
                                   tilerUtilization: percent("Tiler Utilization %"),
                                   inUseMemoryBytes: (stats["In use system memory"] as? NSNumber)?.uint64Value)

            if sample.deviceUtilization != nil { return sample }
        }
        return nil
    }
}

// MARK: - Disk I/O

struct DiskIOCounters: Equatable {
    var bytesRead: UInt64
    var bytesWritten: UInt64
}

enum NativeDiskIO {

    /// Cumulative bytes read and written, from IOBlockStorageDriver.
    ///
    /// Several entries match. On this machine the FIRST one is the SD card reader and
    /// reports zeros forever, so taking `IOServiceGetMatchingService` would ship a
    /// metric permanently stuck at 0 B/s without ever failing. The entry with the
    /// largest counters is the boot volume's.
    static func counters() -> DiskIOCounters? {
        let matching = IOServiceMatching("IOBlockStorageDriver")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var best: DiskIOCounters?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let statsRef = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0),
                  let stats = statsRef.takeRetainedValue() as? [String: Any],
                  let read = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value,
                  let written = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value else { continue }

            let candidate = DiskIOCounters(bytesRead: read, bytesWritten: written)
            if best == nil || (read + written) > (best!.bytesRead + best!.bytesWritten) {
                best = candidate
            }
        }
        return best
    }
}

// MARK: - Network

struct NetworkCounters: Equatable {
    var bytesIn: UInt64
    var bytesWritten: UInt64
}

enum NativeNetwork {

    /// Cumulative interface counters, summed over every interface except loopback.
    ///
    /// Read from `net.link.generic.ifdata.<index>.general`, the interface MIB, and not
    /// from the routing table's NET_RT_IFLIST2. Both hand back a `if_data64` whose
    /// `ifi_ibytes` and `ifi_obytes` are declared 64-bit, but on macOS 26.5 the routing
    /// table's copy carries the value truncated to 32 bits. Measured on en0 at one
    /// instant, with `netstat -ib` as the reference:
    ///
    ///     NET_RT_IFLIST2   ifi_ibytes =  3,428,335,616
    ///     interface MIB    ifi_ibytes = 12,019,689,658
    ///     netstat -ib          Ibytes = 12,019,689,658
    ///
    /// 12,019,689,658 modulo 2^32 is 3,428,308,564. The packet counters in the same
    /// routing-table record are correct, so nothing about the record looks wrong: the
    /// totals were simply a quarter of the truth once the machine had moved 4 GB.
    /// `netstat` reads the interface MIB, which is how the difference was found.
    static func counters() -> NetworkCounters? {
        var interfaceCount: Int32 = 0
        var countSize = MemoryLayout<Int32>.size
        var countMIB: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_SYSTEM, IFMIB_IFCOUNT]
        guard sysctl(&countMIB, 5, &interfaceCount, &countSize, nil, 0) == 0, interfaceCount > 0 else {
            collectorLog.error("sysctl IFMIB_IFCOUNT failed")
            return nil
        }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var read = 0

        // Interface indices are 1-based and contiguous in this MIB.
        for index in 1...interfaceCount {
            var data = ifmibdata()
            var size = MemoryLayout<ifmibdata>.size
            var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, index, IFDATA_GENERAL]
            guard sysctl(&mib, 6, &data, &size, nil, 0) == 0 else { continue }
            read += 1
            // Skip loopback: it doubles every local byte and is not traffic.
            guard data.ifmd_data.ifi_type != UInt8(IFT_LOOP) else { continue }
            totalIn += data.ifmd_data.ifi_ibytes
            totalOut += data.ifmd_data.ifi_obytes
        }

        guard read > 0 else { return nil }
        return NetworkCounters(bytesIn: totalIn, bytesWritten: totalOut)
    }
}

// MARK: - Hardware identity

enum NativeHardware {

    /// The machine's commercial name, read synchronously from the device tree.
    ///
    /// Measured on an M4 Pro: IODeviceTree:/product carries
    /// "MacBook Pro (14-inch, Nov 2024)" and reads in 0.10 ms, against 186 ms for
    /// `system_profiler SPHardwareDataType`, which answers the vaguer "MacBook Pro".
    /// Faster, more precise, and no subprocess.
    ///
    /// Falls back to the model identifier from hw.model - "Mac16,8" - which is always
    /// available and is at least true. There is no hardcoded default: showing
    /// "MacBook Pro" on a Mac mini until something better arrives is the kind of
    /// plausible-and-wrong value this project has spent its time removing.
    static func modelName() -> String {
        if let name = productName(), !name.isEmpty { return name }
        return modelIdentifier() ?? ""
    }

    static func productName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }

        guard let ref = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0),
              let data = ref.takeRetainedValue() as? Data,
              let name = String(data: data, encoding: .utf8) else { return nil }

        return name.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                   .trimmingCharacters(in: .whitespaces)
    }

    /// The model identifier, such as "Mac16,8". Not a commercial name.
    static func modelIdentifier() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}

// MARK: - Battery

struct BatteryDetail: Equatable {
    /// Degrees Celsius, from AppleSmartBattery.
    ///
    /// On the machine this was built against - a Mac16,8 running macOS 26.3 - this
    /// was the only temperature reachable from a third-party process. powermetrics
    /// does not expose the others at all any more: its sampler list has no `smc`
    /// entry, and the `thermal` sampler it does have reports pressure notifications
    /// rather than degrees. That is not a privilege question - the sampler name is
    /// rejected before the superuser check, so `powermetrics --samplers smc` answers
    /// `unrecognized sampler: smc` without sudo.
    var temperature: Double?
    /// Watts. Negative while discharging.
    var power: Double?
    var designCapacity: Int?
    var rawMaxCapacity: Int?
    var cycleCount: Int?
    /// "Normal" or a fault description, from PermanentFailureStatus.
    var condition: String?

    /// Raw full-charge capacity over design capacity.
    ///
    /// Deliberately NOT called maximum capacity: it does not reproduce the figure in
    /// System Settings. Measured on one machine, System Settings said 89% where this
    /// ratio gives 85.4% and NominalChargeCapacity/DesignCapacity gives 87.8%.
    /// Apple derives its number elsewhere and the formula is not published.
    var fullChargeRatio: Double? {
        guard let raw = rawMaxCapacity, let design = designCapacity, design > 0 else { return nil }
        return Double(raw) / Double(design)
    }
}

enum NativeBattery {

    static func detail() -> BatteryDetail? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }

        func int(_ key: String) -> Int? { (properties[key] as? NSNumber)?.intValue }

        var detail = BatteryDetail()
        // Centidegrees.
        if let raw = int("Temperature") { detail.temperature = Double(raw) / 100 }
        // Milliamps times millivolts, signed: negative while discharging.
        if let amperage = int("Amperage"), let voltage = int("Voltage") {
            detail.power = Double(amperage) * Double(voltage) / 1_000_000
        }
        detail.designCapacity = int("DesignCapacity")
        detail.rawMaxCapacity = int("AppleRawMaxCapacity")
        detail.cycleCount = int("CycleCount")
        if let failure = int("PermanentFailureStatus") {
            detail.condition = failure == 0 ? "Normal" : "Service Recommended"
        }

        return detail
    }
}
