import SwiftUI

struct ThermalView: View {
    @ObservedObject var monitor: SystemMonitor

    var levelColor: Color {
        switch monitor.thermal.thermalLevel {
        case "Critique": return .red
        case "Élevé":    return .orange
        case "Modéré":   return .yellow
        default:         return .green
        }
    }

    var levelIcon: String {
        switch monitor.thermal.thermalLevel {
        case "Critique": return "thermometer.high"
        case "Élevé":    return "thermometer.medium"
        case "Modéré":   return "thermometer.low"
        default:         return "thermometer"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Thermique")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("État thermique système en temps réel")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                // Info Apple Silicon
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("Sur Apple Silicon (M4 Pro), macOS 26 ne permet pas l'accès aux températures en °C depuis des apps tierces. L'état thermique système reste disponible.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // État thermique principal — grande carte
                StatCard(title: "État thermique", icon: levelIcon, iconColor: levelColor) {
                    VStack(alignment: .leading, spacing: 16) {

                        // Sparkline historique
                        Sparkline(data: monitor.thermal.history, color: levelColor, height: 40, showAverages: false)

                        // Badge niveau
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

                        // Barre visuelle du niveau
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressBar(value: monitor.thermal.cpuTemp / 100.0, color: levelColor, height: 10)
                            HStack {
                                Text("Normal")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Critique")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Grille des 4 états possibles
                StatCard(title: "Niveaux possibles", icon: "list.bullet", iconColor: .secondary) {
                    VStack(spacing: 12) {
                        ThermalLevelRow(
                            level: "Nominal",
                            description: "Pleine puissance, aucune limitation",
                            color: .green,
                            icon: "thermometer",
                            isActive: monitor.thermal.thermalLevel == "Nominal"
                        )
                        Divider()
                        ThermalLevelRow(
                            level: "Modéré",
                            description: "Légère réduction de performance",
                            color: .yellow,
                            icon: "thermometer.low",
                            isActive: monitor.thermal.thermalLevel == "Modéré"
                        )
                        Divider()
                        ThermalLevelRow(
                            level: "Élevé",
                            description: "Réduction significative — macOS intervient",
                            color: .orange,
                            icon: "thermometer.medium",
                            isActive: monitor.thermal.thermalLevel == "Élevé"
                        )
                        Divider()
                        ThermalLevelRow(
                            level: "Critique",
                            description: "Surchauffe — ferme des apps immédiatement",
                            color: .red,
                            icon: "thermometer.high",
                            isActive: monitor.thermal.thermalLevel == "Critique"
                        )
                    }
                }

                // Alertes
                if !monitor.alerts.isEmpty {
                    StatCard(title: "Alertes actives", icon: "bell.badge", iconColor: .red) {
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
                        Text("Aucune alerte — tout est normal")
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
                Text("ACTUEL")
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
