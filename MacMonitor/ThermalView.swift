import SwiftUI

struct ThermalView: View {
    @ObservedObject var monitor: SystemMonitor

    var levelColor: Color {
        switch monitor.thermal.thermalLevel {
        case "Critical": return .red
        case "Serious":  return .orange
        case "Fair":     return .yellow
        default:         return .green
        }
    }

    var levelIcon: String {
        switch monitor.thermal.thermalLevel {
        case "Critical": return "thermometer.high"
        case "Serious":  return "thermometer.medium"
        case "Fair":     return "thermometer.low"
        default:         return "thermometer"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Thermal")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Live system thermal state")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                // Apple Silicon note
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("On Apple Silicon, macOS does not expose CPU or GPU temperatures in degrees Celsius to third-party apps. The system thermal state is still available.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Main thermal state - large card
                StatCard(title: "Thermal state", icon: levelIcon, iconColor: levelColor) {
                    VStack(alignment: .leading, spacing: 16) {

                        // History sparkline
                        Sparkline(data: monitor.thermal.history, color: levelColor, height: 40, showAverages: false)

                        // Level badge
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(levelColor.opacity(0.15))
                                    .frame(width: 56, height: 56)
                                Image(systemName: levelIcon)
                                    .font(.title2)
                                    .foregroundColor(levelColor)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(monitor.thermal.thermalLevel)
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(levelColor)
                                Text(monitor.thermal.thermalDescription)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        // Visual level bar
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressBar(value: monitor.thermal.thermalLevelValue / 100.0, color: levelColor, height: 10)
                            HStack {
                                Text("Normal")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Critical")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Grid of the four possible states
                StatCard(title: "Possible levels", icon: "list.bullet", iconColor: .secondary) {
                    VStack(spacing: 12) {
                        ThermalLevelRow(
                            level: "Nominal",
                            description: "Full speed, no throttling",
                            color: .green,
                            icon: "thermometer",
                            isActive: monitor.thermal.thermalLevel == "Nominal"
                        )
                        Divider()
                        ThermalLevelRow(
                            level: "Fair",
                            description: "Slight performance reduction",
                            color: .yellow,
                            icon: "thermometer.low",
                            isActive: monitor.thermal.thermalLevel == "Fair"
                        )
                        Divider()
                        ThermalLevelRow(
                            level: "Serious",
                            description: "Significant reduction - macOS is stepping in",
                            color: .orange,
                            icon: "thermometer.medium",
                            isActive: monitor.thermal.thermalLevel == "Serious"
                        )
                        Divider()
                        ThermalLevelRow(
                            level: "Critical",
                            description: "Overheating - close some apps immediately",
                            color: .red,
                            icon: "thermometer.high",
                            isActive: monitor.thermal.thermalLevel == "Critical"
                        )
                    }
                }

                // Alerts
                if !monitor.alerts.isEmpty {
                    StatCard(title: "Active alerts", icon: "bell.badge", iconColor: .red) {
                        VStack(spacing: 8) {
                            ForEach(monitor.alerts) { alert in
                                HStack(spacing: 10) {
                                    Image(systemName: alert.icon)
                                        .foregroundColor(alert.level == .critical ? .red : .orange)
                                        .frame(width: 20)
                                    Text(alert.message)
                                        .font(.caption)
                                        .foregroundColor(alert.level == .critical ? .red : .orange)
                                    Spacer()
                                    Text(alert.timestamp, style: .time)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
                        Text("No alerts - everything is normal")
                            .font(.subheadline).foregroundColor(.green)
                    }
                    .padding(14)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Level Row

struct ThermalLevelRow: View {
    var level: String
    var description: String
    var color: Color
    var icon: String
    var isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(isActive ? color : .secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(level)
                    .font(.subheadline)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundColor(isActive ? color : .primary)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isActive {
                Text("CURRENT")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }
}
