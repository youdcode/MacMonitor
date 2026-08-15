import SwiftUI

struct OverviewView: View {
    @ObservedObject var monitor: SystemMonitor

    private var verdict: HealthVerdict {
        HealthVerdict.evaluate(cpuBusyPercent: monitor.cpu.total,
                               memoryOccupancy: monitor.ram.occupancy,
                               diskOccupancy: monitor.disk.usedPercent,
                               swapUsedGB: monitor.ram.swapUsedGB)
    }

    private var verdictStatus: Status {
        switch verdict {
        case .allGood: return .normal
        case .oneIssue: return .warning
        case .severalIssues: return .critical
        }
    }

    private var verdictText: String {
        switch verdict {
        case .allGood: return "All good"
        case .oneIssue: return "One issue to look at"
        case .severalIssues: return "Several issues to look at"
        }
    }

    private var thermalStatus: Status {
        switch monitor.thermal.thermalLevel {
        case "Critical": return .critical
        case "Serious", "Fair": return .warning
        default: return .normal
        }
    }

    var body: some View {
        DetailScreen(title: "Overview", subtitle: "\(monitor.macModel) - up \(monitor.uptime)") {

            HStack(spacing: 10) {
                StatusDot(status: verdictStatus, accessibilityDescription: "Overall state")
                Text(verdictText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(verdictStatus.colour)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "thermometer.medium")
                        .font(.caption)
                        .foregroundColor(thermalStatus.colour)
                    Text(monitor.thermal.thermalLevel)
                        .font(.caption)
                        .foregroundColor(thermalStatus.colour)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Thermal state")
                .accessibilityValue(monitor.thermal.thermalLevel)
            }
            .padding(10)
            .background(verdictStatus.colour.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 18) {
                Spacer()
                RingGauge(value: monitor.cpu.total / 100,
                          status: Status.forOccupancy(monitor.cpu.total / 100),
                          label: "Processor",
                          detail: Format.percent(monitor.cpu.total))
                RingGauge(value: monitor.ram.occupancy,
                          status: Status.forOccupancy(monitor.ram.occupancy),
                          label: "Memory",
                          detail: "\(Format.memory(monitor.ram.usedGB)) / \(Format.memory(monitor.ram.totalGB))")
                RingGauge(value: monitor.disk.usedPercent,
                          status: Status.forOccupancy(monitor.disk.usedPercent),
                          label: "Storage",
                          detail: "\(Format.storage(monitor.disk.freeGB)) free")
                if monitor.battery.isPresent {
                    RingGauge(value: Double(monitor.battery.percentage) / 100,
                              status: monitor.battery.percentage > 20 ? .normal : .critical,
                              label: "Battery",
                              detail: "\(monitor.battery.percentage)%")
                }
                Spacer()
            }
            .padding(.vertical, 4)

            if !monitor.alerts.isEmpty {
                StatCard(title: "Alerts", icon: "bell.badge", iconColour: .orange) {
                    ForEach(monitor.alerts) { alert in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: alert.level == .critical ? Status.critical.symbol : Status.warning.symbol)
                                .font(.caption)
                                .foregroundColor(alert.level == .critical ? .red : .orange)
                            Text(alert.message)
                                .font(.caption)
                                .foregroundColor(alert.level == .critical ? .red : .orange)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Text(alert.timestamp, style: .time)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                StatCard(title: "Processor", icon: "cpu", iconColour: .blue) {
                    Sparkline(data: monitor.cpu.history,
                              longData: monitor.cpu.longHistory,
                              scale: .percent,
                              colour: .blue,
                              accessibilityDescription: "Processor load over the last two minutes")
                    MetricRow(label: "User", value: Format.percent(monitor.cpu.user))
                    MetricRow(label: "System", value: Format.percent(monitor.cpu.system))
                }

                StatCard(title: "Memory", icon: "memorychip", iconColour: .purple) {
                    Sparkline(data: monitor.ram.history,
                              longData: monitor.ram.longHistory,
                              scale: .ratio,
                              colour: .purple,
                              accessibilityDescription: "Memory in use over the last two minutes")
                    MetricRow(label: "In use", value: Format.memory(monitor.ram.usedGB))
                    MetricRow(label: "Pressure", value: monitor.ram.pressureLevel.label)
                }
            }

            StatCard(title: "Busiest processes", icon: "list.bullet", iconColour: .orange) {
                ForEach(monitor.processes.prefix(5)) { proc in
                    HStack {
                        Text(proc.name)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Format.percent(proc.cpuPercent))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(proc.cpuPercent > 20 ? .orange : .secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(proc.name)
                    .accessibilityValue("\(Format.percent(proc.cpuPercent)) CPU")
                }
            }
        }
    }
}
