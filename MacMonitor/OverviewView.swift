import SwiftUI

struct OverviewView: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Overview")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text(monitor.macOS)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Date(), style: .time)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text("Uptime: \(monitor.uptime)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 4)
                
                // Global health
                let overallHealth = overallScore()
                HStack(spacing: 12) {
                    StatusDot(color: overallHealth.color)
                    Text(overallHealth.label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(overallHealth.color)
                    Spacer()
                }
                .padding(12)
                .background(overallHealth.color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                // Main gauges
                HStack(spacing: 24) {
                    Spacer()
                    RingGauge(
                        value: monitor.cpu.total / 100,
                        color: .statusColor(for: monitor.cpu.total / 100),
                        size: 90,
                        label: "CPU",
                        sublabel: String(format: "%.0f%%", monitor.cpu.total)
                    )
                    RingGauge(
                        value: monitor.ram.pressure,
                        color: .statusColor(for: monitor.ram.pressure),
                        size: 90,
                        label: "Memory",
                        sublabel: "\(formatGB(monitor.ram.usedGB)) / \(formatGB(monitor.ram.totalGB))"
                    )
                    RingGauge(
                        value: monitor.disk.usedPercent,
                        color: .statusColor(for: monitor.disk.usedPercent),
                        size: 90,
                        label: "Storage",
                        sublabel: "\(formatGB(monitor.disk.usedGB)) / \(formatGB(monitor.disk.totalGB))"
                    )
                    if monitor.battery.isPresent {
                        RingGauge(
                            value: Double(monitor.battery.percentage) / 100,
                            color: batteryColor(),
                            size: 90,
                            label: "Battery",
                            sublabel: "\(monitor.battery.percentage)%"
                        )
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                
                // Cards grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    
                    // CPU card
                    StatCard(title: "CPU", icon: "cpu", iconColor: .blue) {
                        Sparkline(data: monitor.cpu.history, longData: monitor.cpu.longHistory, color: .blue)
                        HStack {
                            MetricRow(label: "User", value: String(format: "%.1f%%", monitor.cpu.user))
                            Spacer()
                            MetricRow(label: "System", value: String(format: "%.1f%%", monitor.cpu.system))
                        }
                    }
                    
                    // Memory card
                    StatCard(title: "Memory", icon: "memorychip", iconColor: .purple) {
                        Sparkline(data: monitor.ram.history.map { $0 }, color: .purple)
                        MetricRow(label: "Used", value: formatGB(monitor.ram.usedGB))
                        MetricRow(label: "Free", value: formatGB(monitor.ram.freeGB))
                        MetricRow(label: "Swap", value: formatGB(monitor.ram.swapUsedGB),
                                  color: monitor.ram.swapUsedGB > 0.5 ? .orange : .secondary)
                    }
                    
                    // Storage card
                    StatCard(title: "Storage", icon: "internaldrive", iconColor: .teal) {
                        ProgressBar(value: monitor.disk.usedPercent, color: .statusColor(for: monitor.disk.usedPercent))
                        MetricRow(label: "Used", value: formatGB(monitor.disk.usedGB))
                        MetricRow(label: "Free", value: formatGB(monitor.disk.freeGB),
                                  color: monitor.disk.freeGB < 20 ? .orange : .green)
                        MetricRow(label: "S.M.A.R.T.", value: monitor.disk.smartStatus, color: .green)
                    }
                    
                    // Battery card
                    if monitor.battery.isPresent {
                        StatCard(title: "Battery", icon: "battery.100", iconColor: batteryColor()) {
                            ProgressBar(value: Double(monitor.battery.percentage) / 100, color: batteryColor())
                            MetricRow(label: "Status", value: monitor.battery.isCharging ? "Charging" : "On battery")
                            MetricRow(label: "Cycles", value: "\(monitor.battery.cycleCount)")
                            MetricRow(label: "Condition", value: monitor.battery.health,
                                      color: monitor.battery.health == "Normal" ? .green : .orange)
                        }
                    }
                }
                
                // Top processes, quick view
                StatCard(title: "Active processes", icon: "list.bullet", iconColor: .orange) {
                    ForEach(monitor.processes.prefix(5)) { proc in
                        HStack {
                            Text(proc.name)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(format: "%.1f%%", proc.cpuPercent))
                                .font(.caption)
                                .foregroundColor(proc.cpuPercent > 20 ? .orange : .secondary)
                                .frame(width: 50, alignment: .trailing)
                            Text(String(format: "%.0f MB", proc.memoryMB))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 60, alignment: .trailing)
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
    
    func overallScore() -> (label: String, color: Color) {
        let issues = [
            monitor.cpu.total > 80,
            monitor.ram.pressure > 0.85,
            monitor.disk.usedPercent > 0.90,
            monitor.ram.swapUsedGB > 1.0
        ].filter { $0 }.count
        
        switch issues {
        case 0: return ("All good - your Mac is healthy", .green)
        case 1: return ("One issue to look at", .orange)
        default: return ("Several issues detected", .red)
        }
    }
}
