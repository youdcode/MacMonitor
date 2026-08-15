import Foundation
import IOKit.ps


import AppKit
import UserNotifications

// MARK: - Models

struct CPUUsage {
    var user: Double
    var system: Double
    var idle: Double
    var total: Double { user + system }
    var history: [Double] = []         // 60 pts - 2 min live
    var longHistory: [Double] = []     // 1800 pts - 1h
}

struct RAMUsage {
    var totalGB: Double
    var usedGB: Double
    var freeGB: Double
    var activeGB: Double
    var inactiveGB: Double
    var wiredGB: Double
    var compressedGB: Double
    var swapUsedGB: Double
    var swapTotalGB: Double
    var pressure: Double { totalGB > 0 ? usedGB / totalGB : 0 }
    var history: [Double] = []         // 60 pts - 2 min live
    var longHistory: [Double] = []     // 1800 pts - 1h
}

struct DiskUsage {
    var totalGB: Double
    var usedGB: Double
    var freeGB: Double
    var usedPercent: Double { totalGB > 0 ? usedGB / totalGB : 0 }
}

struct BatteryInfo {
    var isPresent: Bool
    var percentage: Int
    var isCharging: Bool
    var isPlugged: Bool
    var cycleCount: Int
    var health: String
    var timeRemaining: String
    var temperature: Double  // degrees Celsius
}

struct ThermalInfo {
    /// ProcessInfo.thermalState encoded on a 0-100 scale so the sparkline can plot it.
    /// This is NOT a temperature: macOS exposes no CPU or GPU temperature to
    /// third-party apps on Apple Silicon.
    var thermalLevelValue: Double
    var gpuTemp: Double
    var batteryTemp: Double
    var nandTemp: Double
    var thermalLevel: String       // Nominal / Fair / Serious / Critical
    var thermalDescription: String // Explanatory text
    var history: [Double] = []
}

struct Alert: Identifiable {
    let id = UUID()
    var message: String
    var level: AlertLevel
    var timestamp: Date
    var icon: String

    enum AlertLevel {
        case warning, critical
        var color: String { self == .warning ? "orange" : "red" }
    }
}

struct AppProcess: Identifiable {
    let id: Int32
    var name: String
    var cpuPercent: Double
    var memoryMB: Double
    var pid: Int32
}

struct CacheItem: Identifiable {
    var id: String { path }
    var name: String
    var path: String
    var sizeBytes: Int64
    var isSelected: Bool = false
    var icon: String
    /// Bundle identifier of the owning app, when the directory name looks like one.
    var bundleID: String?
    /// Set when the owning application is running right now. The user cannot see
    /// this from a directory listing; the app can, so it says so.
    var runningAppName: String?

    var sizeGB: Double { Double(sizeBytes) / 1_073_741_824 }
}

// MARK: - SystemMonitor

@MainActor
class SystemMonitor: ObservableObject {

    @Published var cpu     = CPUUsage(user: 0, system: 0, idle: 100, history: Array(repeating: 0, count: 60), longHistory: Array(repeating: 0, count: 1800))
    @Published var ram     = RAMUsage(totalGB: 0, usedGB: 0, freeGB: 0, activeGB: 0, inactiveGB: 0, wiredGB: 0, compressedGB: 0, swapUsedGB: 0, swapTotalGB: 0, history: Array(repeating: 0, count: 60), longHistory: Array(repeating: 0, count: 1800))
    @Published var disk    = DiskUsage(totalGB: 0, usedGB: 0, freeGB: 0)
    @Published var battery = BatteryInfo(isPresent: false, percentage: 0, isCharging: false, isPlugged: false, cycleCount: 0, health: "Normal", timeRemaining: "--", temperature: 0)
    @Published var thermal = ThermalInfo(thermalLevelValue: 0, gpuTemp: 0, batteryTemp: 0, nandTemp: 0, thermalLevel: "Nominal", thermalDescription: "Loading...", history: Array(repeating: 0, count: 60))
    @Published var processes: [AppProcess] = []
    @Published var caches: [CacheItem] = []
    @Published var alerts: [Alert] = []
    @Published var isCleaning = false
    @Published var lastReport: CacheRemovalReport?
    @Published var uptime: String = ""
    @Published var macModel: String = "MacBook Pro"
    @Published var macOS: String = ""
    @Published var powermetricsEnabled = false

    private var timer: Timer?
    private var thermalTimer: Timer?  // less frequent: heavier to collect
    private var batteryStaticFetched = false

    init() {
        macOS = ProcessInfo.processInfo.operatingSystemVersionString
        Task { await self.fetchStaticInfo() }
        Task { await self.fetchCaches() }
        requestNotificationPermission()
        startMonitoring()
    }

    func startMonitoring() {
        Task { await self.refreshAll() }
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.refreshAll() }
        }
        // Thermal state every 5 seconds (heavier)
        thermalTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.fetchThermal() }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        thermalTimer?.invalidate()
        timer = nil
        thermalTimer = nil
    }

    func refresh() {
        Task { await self.refreshAll() }
    }

    private func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchCPU() }
            group.addTask { await self.fetchRAM() }
            group.addTask { await self.fetchDisk() }
            group.addTask { await self.fetchBattery() }
            group.addTask { await self.fetchProcesses() }
            group.addTask { await self.fetchUptime() }
        }
        checkAlerts()
    }

    // MARK: - Static Info

    func fetchStaticInfo() async {
        let result = await runShell("system_profiler SPHardwareDataType | grep 'Model Name'")
        for line in result.components(separatedBy: "\n") {
            if line.contains("Model Name"), let val = line.components(separatedBy: ": ").last {
                let model = val.trimmingCharacters(in: .whitespaces)
                if !model.isEmpty { macModel = model }
            }
        }
    }

    // MARK: - CPU (host_cpu_load_info delta)

    private var lastCPUTicks: CPUMath.Ticks?

    func fetchCPU() async {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var cpuLoad = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return }

        let current = CPUMath.Ticks(user: cpuLoad.cpu_ticks.0,
                                    system: cpuLoad.cpu_ticks.1,
                                    idle: cpuLoad.cpu_ticks.2,
                                    nice: cpuLoad.cpu_ticks.3)

        // The first call has no previous sample. CPUMath returns nil for that, and
        // publishing nothing is the point: a delta against a zero baseline would be
        // the average since boot dressed up as an instant reading.
        let previous = lastCPUTicks
        lastCPUTicks = current

        guard let load = CPUMath.load(current: current, previous: previous) else { return }

        let userVal = load.user
        let sysVal  = load.system
        let idleVal = load.idle

        var history = cpu.history
        history.append(userVal + sysVal)
        if history.count > 60 { history.removeFirst() }

        var longHistory = cpu.longHistory
        longHistory.append(userVal + sysVal)
        if longHistory.count > 1800 { longHistory.removeFirst() }

        cpu = CPUUsage(user: userVal, system: sysVal, idle: idleVal, history: history, longHistory: longHistory)
    }

    // MARK: - Memory

    func fetchRAM() async {
        var totalRAM: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalRAM, &size, nil, 0)
        let totalGB = Double(totalRAM) / 1_073_741_824

        let vmResult = await runShell("vm_stat")
        guard let pages = VMStatParser.parse(vmResult) else { return }

        // vm_stat reports page counts, not bytes. The page size is 4 KB on Intel
        // but 16 KB on Apple Silicon, so it is read at runtime: hardcoding 4096
        // under-reports every memory figure by a factor of 4 on Apple Silicon.
        let pageSize = Int(vm_page_size)
        func gigabytes(_ p: Double) -> Double { MemoryMath.gigabytes(pages: p, pageSize: pageSize) ?? 0 }

        let free       = gigabytes(pages.free)
        let active     = gigabytes(pages.active)
        let inactive   = gigabytes(pages.inactive)
        let wired      = gigabytes(pages.wired)
        let compressed = gigabytes(pages.occupiedByCompressor)

        // Real used memory = active + wired + compressed (inactive is reclaimable)
        let used = active + wired + compressed

        let swapResult = await runShell("sysctl vm.swapusage")
        let swap = SwapUsageParser.parse(swapResult)
        let swapUsed  = swap?.used  ?? 0
        let swapTotal = swap?.total ?? 0

        var history = ram.history
        history.append(totalGB > 0 ? used / totalGB : 0)
        if history.count > 60 { history.removeFirst() }

        var longHistory = ram.longHistory
        longHistory.append(totalGB > 0 ? used / totalGB : 0)
        if longHistory.count > 1800 { longHistory.removeFirst() }

        ram = RAMUsage(totalGB: totalGB, usedGB: used, freeGB: free + inactive,
                       activeGB: active, inactiveGB: inactive, wiredGB: wired,
                       compressedGB: compressed, swapUsedGB: swapUsed,
                       swapTotalGB: swapTotal, history: history, longHistory: longHistory)
    }

    // MARK: - Disk

    func fetchDisk() async {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let total = attrs[.systemSize]     as? Int64,
              let free  = attrs[.systemFreeSize] as? Int64 else { return }
        // Storage is counted in decimal gigabytes (10^9), which is what Finder and
        // System Settings show. Memory keeps binary gigabytes (2^30). Dividing both
        // by 2^30 and labelling the result "GB" under-reported the disk by 7.4%.
        let totalGB = Double(total) / 1_000_000_000
        let freeGB  = Double(free)  / 1_000_000_000
        disk = DiskUsage(totalGB: totalGB, usedGB: totalGB - freeGB, freeGB: freeGB)
    }

    // MARK: - Battery

    func fetchBattery() async {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources  = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array

        guard let source = sources.first,
              let info = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any] else {
            battery = BatteryInfo(isPresent: false, percentage: 0, isCharging: false,
                                  isPlugged: false, cycleCount: 0, health: "N/A", timeRemaining: "N/A", temperature: 0)
            return
        }

        let pct        = info[kIOPSCurrentCapacityKey]   as? Int ?? 0
        let isCharging = (info[kIOPSIsChargingKey]       as? Bool) ?? false
        let isPlugged  = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let tte        = info[kIOPSTimeToEmptyKey]       as? Int ?? -1
        let ttf        = info[kIOPSTimeToFullChargeKey]  as? Int ?? -1

        var timeStr = "--"
        if isCharging && ttf > 0       { timeStr = "\(ttf / 60)h \(ttf % 60)m (charging)" }
        else if !isCharging && tte > 0 { timeStr = "\(tte / 60)h \(tte % 60)m remaining"  }

        // Cycles and health are fetched once at startup only (slow)
        var cycles = battery.cycleCount
        var health  = battery.health
        if !batteryStaticFetched {
            let battResult = await runShell("system_profiler SPPowerDataType 2>/dev/null | grep -E 'Cycle Count|Condition'")
            if let info = BatteryStaticParser.parse(battResult) {
                cycles = info.cycleCount
                health = info.condition
            }
            batteryStaticFetched = true
        }

        battery = BatteryInfo(isPresent: true, percentage: pct, isCharging: isCharging,
                              isPlugged: isPlugged, cycleCount: cycles, health: health,
                              timeRemaining: timeStr, temperature: thermal.batteryTemp)
    }

    // MARK: - Thermal (ProcessInfo.thermalState - the only API available on Apple Silicon)

    func fetchThermal() async {
        let state = ProcessInfo.processInfo.thermalState

        let (level, description) = thermalStateInfo(state)
        powermetricsEnabled = true  // API dispo sans entitlement

        var history = thermal.history
        // Encode the level as a numeric value so the sparkline can plot it
        let numericVal: Double
        switch state {
        case .nominal:  numericVal = 10
        case .fair:     numericVal = 40
        case .serious:  numericVal = 75
        case .critical: numericVal = 100
        @unknown default: numericVal = 0
        }
        history.append(numericVal)
        if history.count > 60 { history.removeFirst() }

        thermal = ThermalInfo(
            thermalLevelValue: numericVal,
            gpuTemp: 0,
            batteryTemp: 0,
            nandTemp: 0,
            thermalLevel: level,
            thermalDescription: description,
            history: history
        )
    }

    private func thermalStateInfo(_ state: ProcessInfo.ThermalState) -> (String, String) {
        switch state {
        case .nominal:
            return ("Nominal", "Running at full speed. Everything is normal.")
        case .fair:
            return ("Fair", "Slight warming detected. Performance may be reduced a little.")
        case .serious:
            return ("Serious", "Serious heat. macOS is reducing performance to cool down.")
        case .critical:
            return ("Critical", "Critical overheating. Close some apps immediately.")
        @unknown default:
            return ("Unknown", "")
        }
    }

    // MARK: - Processes

    /// Physical memory in binary gigabytes, read once from the kernel.
    private lazy var physicalMemoryGB: Double = {
        var bytes: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &bytes, &size, nil, 0) == 0 else { return 0 }
        return Double(bytes) / 1_073_741_824
    }()

    func fetchProcesses() async {
        let result = await runShell("ps aux | sort -rk3 | head -15")
        var procs: [AppProcess] = []
        // No dropFirst here: `sort` mixes the ps header in with the rows, so it is
        // not on the first line. Dropping line 1 removed the top CPU consumer.
        // PSParser rejects the header because it carries no numeric pid.
        for row in PSParser.parse(result) {
            let pid    = row.pid
            let cpuVal = row.cpuPercent
            let memPct = row.memoryPercent
            let name   = row.command
            guard cpuVal > 0 || memPct > 1 else { continue }
            // Read hw.memsize directly instead of depending on ram.totalGB, which is
            // written by fetchRAM in the same TaskGroup with no ordering guarantee and
            // is still 0 on the first cycle.
            // transitional: this is RSS, not phys_footprint. Replaced when the process
            // list moves off `ps` to a native API.
            let memMB  = memPct / 100.0 * physicalMemoryGB * 1024
            procs.append(AppProcess(id: pid, name: name, cpuPercent: cpuVal, memoryMB: memMB, pid: pid))
        }
        processes = Array(procs.prefix(12))
    }

    // MARK: - Uptime

    func fetchUptime() async {
        // Do NOT use ProcessInfo.systemUptime here: it is backed by mach_absolute_time
        // and only counts time the machine was AWAKE. Measured on this machine, it read
        // 10h39 against a real uptime of 15h44 - the 5h04 difference being sleep.
        // kern.boottime is wall-clock and matches the `uptime` command.
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]

        guard sysctl(&mib, 2, &bootTime, &size, nil, 0) == 0, bootTime.tv_sec > 0 else {
            uptime = "--"
            return
        }

        let seconds = Int(Date().timeIntervalSince1970) - bootTime.tv_sec
        guard seconds > 0 else {
            uptime = "--"
            return
        }

        uptime = UptimeFormatter.string(seconds: seconds) ?? "--"
    }

    // MARK: - Alerts

    func checkAlerts() {
        var newAlerts: [Alert] = []

        if cpu.total > 85 {
            newAlerts.append(Alert(message: "CPU at \(Int(cpu.total))% - very high load", level: .warning, timestamp: Date(), icon: "cpu"))
        }
        if ram.swapUsedGB > 1.5 {
            newAlerts.append(Alert(message: "High swap (\(String(format: "%.1f", ram.swapUsedGB)) GB) - memory pressure", level: .warning, timestamp: Date(), icon: "memorychip"))
        }
        if disk.freeGB < 10 {
            newAlerts.append(Alert(message: "Storage almost full - \(String(format: "%.1f", disk.freeGB)) GB left", level: .critical, timestamp: Date(), icon: "internaldrive"))
        }
        // The app has no access to actual temperatures, so alerts report the
        // thermal state macOS publishes, never a number of degrees.
        if thermal.thermalLevel == "Critical" {
            newAlerts.append(Alert(message: "Thermal state critical - close some apps immediately", level: .critical, timestamp: Date(), icon: "thermometer.high"))
        } else if thermal.thermalLevel == "Serious" {
            newAlerts.append(Alert(message: "Thermal state serious - macOS is reducing performance", level: .warning, timestamp: Date(), icon: "thermometer.medium"))
        }
        if battery.isPresent && battery.percentage < 15 && !battery.isPlugged {
            newAlerts.append(Alert(message: "Low battery: \(battery.percentage)%", level: .critical, timestamp: Date(), icon: "battery.25"))
        }

        // Notify when a new critical alert appears
        let hadCritical = alerts.contains { $0.level == .critical }
        let hasCritical = newAlerts.contains { $0.level == .critical }
        if hasCritical && !hadCritical {
            sendNotification(title: "Mac Monitor", body: newAlerts.first(where: { $0.level == .critical })?.message ?? "Critical alert")
        }

        alerts = newAlerts
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Caches

    /// Directories the cleaner is allowed to touch, resolved.
    ///
    /// ~/Library/Caches is enumerated; the two development caches below live
    /// elsewhere and are named explicitly because they are large, well understood,
    /// and the ones most likely to be in use while the user is looking at them.
    nonisolated static func cacheRoots() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/Library/Caches",
            "\(home)/Library/Developer/Xcode/DerivedData",
            "\(home)/.npm",
        ].map { ($0 as NSString).resolvingSymlinksInPath }
    }

    func fetchCaches() async {
        let running = Self.runningApplicationsByBundleID()
        let discovered = await Task.detached(priority: .utility) {
            Self.discoverCaches(running: running)
        }.value
        caches = discovered
    }

    /// Bundle identifier -> localised app name, for applications running right now.
    nonisolated static func runningApplicationsByBundleID() -> [String: String] {
        var map: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier else { continue }
            map[id] = app.localizedName ?? id
        }
        return map
    }

    /// Enumerates the cache roots. Runs off the main actor: this walks tens of
    /// thousands of files and used to freeze the interface for seconds at launch.
    nonisolated static func discoverCaches(running: [String: String]) -> [CacheItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var items: [CacheItem] = []

        func add(path: String, directoryName: String) {
            let described = CacheNaming.describe(directoryName: directoryName)
            let bytes = directorySize(path: path)
            guard bytes > 10_000_000 else { return }   // below 10 MB it is not worth a row

            var runningName: String?
            if let id = described.bundleID, let appName = running[id] { runningName = appName }

            items.append(CacheItem(name: described.name,
                                   path: path,
                                   sizeBytes: bytes,
                                   icon: described.icon,
                                   bundleID: described.bundleID,
                                   runningAppName: runningName))
        }

        // 1. Everything the user has under ~/Library/Caches, minus the exclusions.
        let cachesRoot = "\(home)/Library/Caches"
        if let entries = try? fm.contentsOfDirectory(atPath: cachesRoot) {
            for entry in entries.sorted() {
                guard !entry.hasPrefix("."), !CacheNaming.excluded.contains(entry) else { continue }
                var isDirectory: ObjCBool = false
                let full = (cachesRoot as NSString).appendingPathComponent(entry)
                guard fm.fileExists(atPath: full, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                add(path: full, directoryName: entry)
            }
        }

        // 2. Two development caches that do not live under ~/Library/Caches.
        let derivedData = "\(home)/Library/Developer/Xcode/DerivedData"
        if fm.fileExists(atPath: derivedData) {
            let bytes = directorySize(path: derivedData)
            if bytes > 10_000_000 {
                items.append(CacheItem(name: "Xcode DerivedData",
                                       path: derivedData,
                                       sizeBytes: bytes,
                                       icon: "hammer",
                                       bundleID: "com.apple.dt.Xcode",
                                       runningAppName: running["com.apple.dt.Xcode"]))
            }
        }

        let npmCache = "\(home)/.npm/_cacache"
        if fm.fileExists(atPath: npmCache) {
            let bytes = directorySize(path: npmCache)
            if bytes > 10_000_000 {
                items.append(CacheItem(name: "npm",
                                       path: npmCache,
                                       sizeBytes: bytes,
                                       icon: "chevron.left.forwardslash.chevron.right",
                                       bundleID: nil,
                                       runningAppName: isProcessRunning(named: "node") ? "node" : nil))
            }
        }

        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Command-line tools have no bundle identifier, so NSWorkspace cannot see them.
    nonisolated static func isProcessRunning(named name: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", name]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    nonisolated static func directorySize(path: String) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: URL(fileURLWithPath: path),
                                             includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
                                             options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.totalFileAllocatedSize else { continue }
            total += Int64(size)
        }
        return total
    }

    /// Moves the selected caches to the trash.
    ///
    /// Trash rather than delete: that is what the Finder does, and it makes a wrong
    /// click recoverable without taking anything away from the user.
    ///
    /// - Parameter dryRun: when true nothing is touched and the report lists what
    ///   would have been moved.
    func cleanSelectedCaches(dryRun: Bool = false) {
        let selected = caches.filter(\.isSelected)
        guard !selected.isEmpty else { return }

        isCleaning = true
        let roots = Self.cacheRoots()

        Task { [weak self] in
            let report = await Task.detached(priority: .utility) {
                Self.remove(selected, allowedRoots: roots, dryRun: dryRun)
            }.value

            guard let self else { return }
            self.lastReport = report
            self.isCleaning = false
            await self.fetchCaches()
        }
    }

    /// - Returns: one outcome per item, so a failure is reported with its reason
    ///   instead of being swallowed. The reclaimed figure is derived from the
    ///   outcomes, never accumulated ahead of the work.
    nonisolated static func remove(_ items: [CacheItem],
                                   allowedRoots: [String],
                                   dryRun: Bool) -> CacheRemovalReport {
        let fm = FileManager.default
        var outcomes: [CacheRemovalOutcome] = []

        for item in items {
            let resolved = (item.path as NSString).resolvingSymlinksInPath

            // Re-validated here, immediately before acting, not when the list was
            // built: the path may have been replaced by a symlink in between.
            switch CachePathValidator.validate(candidate: item.path,
                                               resolved: resolved,
                                               allowedRoots: allowedRoots) {
            case .failure(let rejection):
                outcomes.append(CacheRemovalOutcome(path: item.path, name: item.name,
                                                    sizeBytes: item.sizeBytes,
                                                    result: .rejected(rejection.rawValue)))
                continue
            case .success:
                break
            }

            if dryRun {
                outcomes.append(CacheRemovalOutcome(path: item.path, name: item.name,
                                                    sizeBytes: item.sizeBytes,
                                                    result: .wouldBeMovedToTrash))
                continue
            }

            do {
                try fm.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
                outcomes.append(CacheRemovalOutcome(path: item.path, name: item.name,
                                                    sizeBytes: item.sizeBytes,
                                                    result: .movedToTrash))
            } catch {
                outcomes.append(CacheRemovalOutcome(path: item.path, name: item.name,
                                                    sizeBytes: item.sizeBytes,
                                                    result: .failed(error.localizedDescription)))
            }
        }

        return CacheRemovalReport(outcomes: outcomes, wasDryRun: dryRun)
    }

    // MARK: - Shell helper

    func runShell(_ command: String) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let task = Process()
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError  = Pipe()
                task.arguments      = ["-c", command]
                task.executableURL  = URL(fileURLWithPath: "/bin/zsh")
                do {
                    try task.run()
                    task.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}
