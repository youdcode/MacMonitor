import SwiftUI

struct MemoryView: View {
    @ObservedObject var monitor: SystemMonitor

    private var status: Status { Status.forOccupancy(monitor.ram.occupancy) }

    private var pressureStatus: Status {
        switch monitor.ram.pressureLevel {
        case .normal: return .normal
        case .warning: return .warning
        case .critical: return .critical
        }
    }

    var body: some View {
        DetailScreen(title: "Memory", subtitle: "\(Format.memory(monitor.ram.totalGB)) installed") {

            StatCard(title: "In use", icon: "memorychip", iconColour: .purple) {
                Sparkline(data: monitor.ram.history,
                          longData: monitor.ram.longHistory,
                          scale: .ratio,
                          colour: .purple,
                          height: 54,
                          accessibilityDescription: "Memory in use over the last two minutes")
                SparklineLegend(colour: .purple)

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Format.memory(monitor.ram.usedGB))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(status.colour)
                        Text("of \(Format.memory(monitor.ram.totalGB))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Memory in use")
                    .accessibilityValue("\(Format.memory(monitor.ram.usedGB)) of \(Format.memory(monitor.ram.totalGB))")

                    Spacer()

                    VStack(spacing: 5) {
                        MetricRow(label: "Active", value: Format.memory(monitor.ram.activeGB))
                        MetricRow(label: "Wired", value: Format.memory(monitor.ram.wiredGB))
                        MetricRow(label: "Compressed", value: Format.memory(monitor.ram.compressedGB))
                        MetricRow(label: "Inactive", value: Format.memory(monitor.ram.inactiveGB))
                    }
                    .frame(width: 180)
                }

                ProgressBar(value: monitor.ram.occupancy,
                            status: status,
                            accessibilityDescription: "Memory in use")
            }

            HStack(alignment: .top, spacing: 12) {
                StatCard(title: "Pressure", icon: "gauge.medium", iconColour: pressureStatus.colour) {
                    HStack(spacing: 8) {
                        StatusDot(status: pressureStatus, accessibilityDescription: "Memory pressure")
                        Text(monitor.ram.pressureLevel.label)
                            .font(.headline)
                            .foregroundColor(pressureStatus.colour)
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)

                    Text("Reported by the kernel. This is what macOS itself acts on, and it is not the same thing as the percentage above.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                StatCard(title: "Swap", icon: "arrow.left.arrow.right", iconColour: .purple) {
                    MetricRow(label: "Used", value: Format.memory(monitor.ram.swapUsedGB),
                              colour: monitor.ram.swapUsedGB > Threshold.swapWarningGB ? .orange : .primary)
                    MetricRow(label: "Total", value: Format.memory(monitor.ram.swapTotalGB))
                    if monitor.ram.swapUsedGB > Threshold.swapWarningGB {
                        Text("Swap in use means memory is being paged to disk.")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            StatCard(title: "How this compares to Activity Monitor", icon: "info.circle", iconColour: .secondary) {
                MetricRow(label: "This app, active + wired + compressed",
                          value: Format.memory(monitor.ram.usedGB))
                MetricRow(label: "Activity Monitor's formula",
                          value: Format.memory(monitor.ram.activityMonitorUsedGB))
                Text("Activity Monitor also folds in inactive and speculative pages and subtracts what is purgeable or file-backed. Both numbers are shown rather than picking one and calling it the truth.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
