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
    let id = UUID()
    var name: String
    var path: String
    var sizeGB: Double
    var isSelected: Bool = false
    var isSafe: Bool
    var icon: String
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
    @Published var lastCleanedGB: Double = 0
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

    private var lastCPUTicks: (user: UInt32, sys: UInt32, idle: UInt32, nice: UInt32) = (0, 0, 0, 0)
    private var hasCPUBaseline = false

    func fetchCPU() async {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var cpuLoad = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return }

        let curUser = cpuLoad.cpu_ticks.0
        let curSys  = cpuLoad.cpu_ticks.1
        let curIdle = cpuLoad.cpu_ticks.2
        let curNice = cpuLoad.cpu_ticks.3

        let dUser = Double(curUser &- lastCPUTicks.user)
        let dSys  = Double(curSys  &- lastCPUTicks.sys)
        let dIdle = Double(curIdle &- lastCPUTicks.idle)
        let dNice = Double(curNice &- lastCPUTicks.nice)
        let total = dUser + dSys + dIdle + dNice

        lastCPUTicks = (curUser, curSys, curIdle, curNice)

        // The first call has no previous sample, so the delta would be the tick
        // counts since boot: an average since startup, not an instant reading.
        // Seed the baseline and publish nothing.
        guard hasCPUBaseline else {
            hasCPUBaseline = true
            return
        }

        guard total > 0 else { return }

        let userVal = (dUser + dNice) / total * 100
        let sysVal  = dSys  / total * 100
        let idleVal = dIdle / total * 100

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
        var free = 0.0, active = 0.0, inactive = 0.0, wired = 0.0, compressed = 0.0

        // vm_stat reports page counts, not bytes. The page size is 4 KB on Intel
        // but 16 KB on Apple Silicon, so it must be read at runtime: hardcoding
        // 4096 under-reports every memory figure by a factor of 4 on Apple Silicon.
        let gb = Double(vm_page_size) / 1_073_741_824

        for line in vmResult.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: ":")
            guard parts.count >= 2 else { continue }
            let val = Double(parts[1].trimmingCharacters(in: .init(charactersIn: " ."))) ?? 0
            let key = parts[0]
            if key == "Pages free"                        { free       = val * gb }
            else if key == "Pages active"                { active     = val * gb }
            else if key == "Pages inactive"              { inactive   = val * gb }
            else if key == "Pages wired down"            { wired      = val * gb }
            else if key == "Pages occupied by compressor" { compressed = val * gb }
        }

        // Real used memory = active + wired + compressed (inactive is reclaimable)
        let used = active + wired + compressed

        let swapResult = await runShell("sysctl vm.swapusage")
        var swapUsed = 0.0, swapTotal = 0.0
        if let r = swapResult.range(of: #"used = (\d+\.?\d*)M"#, options: .regularExpression) {
            let s = swapResult[r].replacingOccurrences(of: "used = ", with: "").replacingOccurrences(of: "M", with: "")
            swapUsed = (Double(s) ?? 0) / 1024
        }
        if let r = swapResult.range(of: #"total = (\d+\.?\d*)M"#, options: .regularExpression) {
            let s = swapResult[r].replacingOccurrences(of: "total = ", with: "").replacingOccurrences(of: "M", with: "")
            swapTotal = (Double(s) ?? 0) / 1024
        }

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
            for line in battResult.components(separatedBy: "\n") {
                if line.contains("Cycle Count"), let val = line.components(separatedBy: ": ").last {
                    cycles = Int(val.trimmingCharacters(in: .whitespaces)) ?? 0
                }
                if line.contains("Condition"), let val = line.components(separatedBy: ": ").last {
                    health = val.trimmingCharacters(in: .whitespaces)
                }
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
        // The header is discarded by the guard below, which cannot parse it.
        for line in result.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: true)
            guard parts.count >= 11 else { continue }
            let pid    = Int32(parts[1]) ?? 0
            let cpuVal = Double(parts[2]) ?? 0
            let memPct = Double(parts[3]) ?? 0
            let name   = String(parts[10]).components(separatedBy: "/").last ?? String(parts[10])
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

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            uptime = "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            uptime = "\(hours)h \(minutes)m"
        } else {
            uptime = "\(minutes)m"
        }
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

    func fetchCaches() async {
        let home      = FileManager.default.homeDirectoryForCurrentUser.path
        let cachePath = "\(home)/Library/Caches"

        let knownCaches: [(name: String, path: String, safe: Bool, icon: String)] = [
            ("Adobe",             "\(cachePath)/Adobe",                             true,  "paintbrush"),
            ("Google Chrome",     "\(cachePath)/Google",                            true,  "globe"),
            ("Homebrew",          "\(cachePath)/Homebrew",                          true,  "shippingbox"),
            ("Telegram",          "\(cachePath)/ru.keepcoder.Telegram",             true,  "paperplane"),
            ("Discord",           "\(cachePath)/com.hnc.Discord",                   true,  "bubble.left"),
            ("Spotify",           "\(cachePath)/com.spotify.client",                true,  "music.note"),
            ("Slack",             "\(cachePath)/com.tinyspeck.slackmacgap",         true,  "number"),
            ("Music",             "\(cachePath)/com.apple.Music",                   true,  "music.quarternote.3"),
            ("Xcode DerivedData", "\(home)/Library/Developer/Xcode/DerivedData",    true,  "hammer"),
            ("npm",               "\(home)/.npm/_cacache",                          true,  "chevron.left.forwardslash.chevron.right"),
            ("pip",               "\(cachePath)/pip",                               true,  "chevron.left.forwardslash.chevron.right"),
            ("Loom",              "\(cachePath)/com.loom.desktop.ShipIt",           true,  "video"),
            ("TradingView",       "\(cachePath)/tradingview-desktop-updater",       true,  "chart.line.uptrend.xyaxis"),
            ("SiriTTS",           "\(cachePath)/SiriTTS",                           false, "waveform"),
            ("iCloud Mail",       "\(cachePath)/icloudmailagent",                   false, "envelope"),
        ]

        var items: [CacheItem] = []
        let fm = FileManager.default
        for cache in knownCaches {
            guard fm.fileExists(atPath: cache.path) else { continue }
            let sizeBytes = directorySize(path: cache.path)
            let sizeGB    = Double(sizeBytes) / 1_073_741_824
            if sizeGB > 0.01 {
                items.append(CacheItem(name: cache.name, path: cache.path,
                                       sizeGB: sizeGB, isSafe: cache.safe, icon: cache.icon))
            }
        }
        caches = items.sorted { $0.sizeGB > $1.sizeGB }
    }

    func directorySize(path: String) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
        var total: Int64 = 0
        for case let file as String in enumerator {
            let fp = (path as NSString).appendingPathComponent(file)
            if let attrs = try? fm.attributesOfItem(atPath: fp),
               let size  = attrs[.size] as? Int64 { total += size }
        }
        return total
    }

    func cleanSelectedCaches() {
        isCleaning = true
        let toClean = caches.filter { $0.isSelected && $0.isSafe }
        Task.detached {
            var freed = 0.0
            for item in toClean {
                freed += item.sizeGB
                try? FileManager.default.removeItem(atPath: item.path)
            }
            await MainActor.run {
                self.lastCleanedGB = freed
                self.isCleaning    = false
                Task { await self.fetchCaches() }
            }
        }
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
