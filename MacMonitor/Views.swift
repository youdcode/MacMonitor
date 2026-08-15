import SwiftUI

// MARK: - CPU & Memory View

struct CPURAMView: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("CPU & Memory")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // CPU section
                StatCard(title: "Processor", icon: "cpu", iconColor: .blue) {
                    VStack(alignment: .leading, spacing: 12) {
                        Sparkline(data: monitor.cpu.history, longData: monitor.cpu.longHistory, color: .blue, height: 60)
                        SparklineLegend(color: .blue)
                        
                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(format: "%.1f%%", monitor.cpu.total))
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(.blue)
                                Text("Total usage")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 8) {
                                MetricRow(label: "User", value: String(format: "%.1f%%", monitor.cpu.user))
                                MetricRow(label: "System", value: String(format: "%.1f%%", monitor.cpu.system))
                                MetricRow(label: "Idle", value: String(format: "%.1f%%", monitor.cpu.idle))
                            }
                            .frame(width: 200)
                        }
                        
                        ProgressBar(value: monitor.cpu.total / 100, color: .statusColor(for: monitor.cpu.total / 100))
                    }
                }
                
                // Memory section
                StatCard(title: "Memory", icon: "memorychip", iconColor: .purple) {
                    VStack(alignment: .leading, spacing: 12) {
                        Sparkline(data: monitor.ram.history, longData: monitor.ram.longHistory, color: .purple, height: 60)
                        SparklineLegend(color: .purple)
                        
                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formatGB(monitor.ram.usedGB))
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(.purple)
                                Text("of \(formatGB(monitor.ram.totalGB)) used")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 8) {
                                MetricRow(label: "Active", value: formatGB(monitor.ram.activeGB))
                                MetricRow(label: "Inactive", value: formatGB(monitor.ram.inactiveGB))
                                MetricRow(label: "Wired", value: formatGB(monitor.ram.wiredGB))
                                MetricRow(label: "Compressed", value: formatGB(monitor.ram.compressedGB))
                                MetricRow(label: "Free", value: formatGB(monitor.ram.freeGB), color: .green)
                            }
                            .frame(width: 200)
                        }
                        
                        ProgressBar(value: monitor.ram.pressure, color: .statusColor(for: monitor.ram.pressure))
                        
                        Divider()
                        
                        // Swap
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Swap (virtual memory)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text("Used when memory is full - a sign of memory pressure")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(formatGB(monitor.ram.swapUsedGB))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(monitor.ram.swapUsedGB > 0.5 ? .orange : .green)
                                Text("/ \(formatGB(monitor.ram.swapTotalGB))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if monitor.ram.swapUsedGB > 0.5 {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text("High swap - free up storage or close some apps")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Disk View

struct DiskView: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Storage")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                StatCard(title: "Startup disk", icon: "internaldrive", iconColor: .teal) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formatGB(monitor.disk.freeGB))
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(.teal)
                                Text("available of \(formatGB(monitor.disk.totalGB))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 8) {
                                MetricRow(label: "Used", value: formatGB(monitor.disk.usedGB))
                                MetricRow(label: "Free", value: formatGB(monitor.disk.freeGB),
                                          color: monitor.disk.freeGB < 20 ? .orange : .green)
                                MetricRow(label: "Total", value: formatGB(monitor.disk.totalGB))
                                MetricRow(label: "S.M.A.R.T.", value: monitor.disk.smartStatus, color: .green)
                            }
                            .frame(width: 200)
                        }
                        
                        ProgressBar(
                            value: monitor.disk.usedPercent,
                            color: .statusColor(for: monitor.disk.usedPercent),
                            height: 10
                        )
                        
                        Text("\(Int(monitor.disk.usedPercent * 100))% used")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if monitor.disk.usedPercent > 0.85 {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text("Storage almost full - open Cleaner to free up space")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Battery View

struct BatteryView: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Battery")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                if !monitor.battery.isPresent {
                    Text("No battery detected (desktop Mac)")
                        .foregroundColor(.secondary)
                } else {
                    StatCard(title: "Battery status", icon: "battery.100", iconColor: batteryColor()) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 24) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text("\(monitor.battery.percentage)")
                                            .font(.system(size: 52, weight: .bold, design: .rounded))
                                            .foregroundColor(batteryColor())
                                        Text("%")
                                            .font(.title)
                                            .foregroundColor(batteryColor())
                                    }
                                    HStack(spacing: 6) {
                                        Image(systemName: monitor.battery.isCharging ? "bolt.fill" : (monitor.battery.isPlugged ? "powerplug.fill" : "battery.25"))
                                            .foregroundColor(batteryColor())
                                            .font(.caption)
                                        Text(monitor.battery.isCharging ? "Charging" : (monitor.battery.isPlugged ? "Plugged in (charged)" : "On battery"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .leading, spacing: 8) {
                                    MetricRow(label: "Time remaining", value: monitor.battery.timeRemaining)
                                    MetricRow(label: "Cycles", value: "\(monitor.battery.cycleCount)",
                                              color: monitor.battery.cycleCount > 800 ? .orange : .primary)
                                    MetricRow(label: "Condition", value: monitor.battery.health,
                                              color: monitor.battery.health == "Normal" ? .green : .orange)
                                }
                                .frame(width: 220)
                            }
                            
                            ProgressBar(value: Double(monitor.battery.percentage) / 100, color: batteryColor(), height: 10)
                            
                            // Cycle count advice
                            if monitor.battery.cycleCount > 800 {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    Text("High cycle count (\(monitor.battery.cycleCount)/1000) - the battery is nearing end of life")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            } else {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                    Text("Battery in good health (\(monitor.battery.cycleCount) of ~1000 cycles)")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                    
                    // Tips
                    StatCard(title: "Tips", icon: "lightbulb", iconColor: .yellow) {
                        VStack(alignment: .leading, spacing: 8) {
                            tipRow(icon: "bolt.slash", text: "Avoid keeping it at 100% all the time - 20-80% is ideal")
                            tipRow(icon: "thermometer.medium", text: "Avoid hot environments, they degrade the battery")
                            tipRow(icon: "moon.fill", text: "Turn on Optimized Battery Charging in System Settings")
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    func batteryColor() -> Color {
        if monitor.battery.isCharging { return .green }
        if monitor.battery.percentage > 50 { return .green }
        if monitor.battery.percentage > 20 { return .orange }
        return .red
    }
    
    func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Processes View

struct ProcessesView: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Processes")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                    Button("Refresh") {
                        Task { await monitor.fetchProcesses() }
                    }
                    .buttonStyle(.bordered)
                }
                
                StatCard(title: "Top processes by CPU", icon: "cpu", iconColor: .orange) {
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("Processes").font(.caption).fontWeight(.semibold).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            Text("CPU").font(.caption).fontWeight(.semibold).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
                            Text("Memory").font(.caption).fontWeight(.semibold).foregroundColor(.secondary).frame(width: 80, alignment: .trailing)
                            Text("PID").font(.caption).fontWeight(.semibold).foregroundColor(.secondary).frame(width: 50, alignment: .trailing)
                        }
                        .padding(.bottom, 8)
                        
                        Divider()
                        
                        ForEach(monitor.processes) { proc in
                            HStack {
                                Text(proc.name)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Text(String(format: "%.1f%%", proc.cpuPercent))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(proc.cpuPercent > 20 ? .orange : (proc.cpuPercent > 5 ? .primary : .secondary))
                                    .frame(width: 60, alignment: .trailing)
                                
                                Text(String(format: "%.0f MB", proc.memoryMB))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 80, alignment: .trailing)
                                
                                Text("\(proc.pid)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 50, alignment: .trailing)
                            }
                            .padding(.vertical, 6)
                            
                            Divider()
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
