import SwiftUI

// MARK: - CPU & RAM View

struct CPURAMView: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("CPU & RAM")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // CPU Section
                StatCard(title: "Processeur", icon: "cpu", iconColor: .blue) {
                    VStack(alignment: .leading, spacing: 12) {
                        Sparkline(data: monitor.cpu.history, longData: monitor.cpu.longHistory, color: .blue, height: 60)
                        SparklineLegend(color: .blue)
                        
                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(format: "%.1f%%", monitor.cpu.total))
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(.blue)
                                Text("Utilisation totale")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 8) {
                                MetricRow(label: "Utilisateur", value: String(format: "%.1f%%", monitor.cpu.user))
                                MetricRow(label: "Système", value: String(format: "%.1f%%", monitor.cpu.system))
                                MetricRow(label: "Inactif", value: String(format: "%.1f%%", monitor.cpu.idle))
                            }
                            .frame(width: 200)
                        }
                        
                        ProgressBar(value: monitor.cpu.total / 100, color: .statusColor(for: monitor.cpu.total / 100))
                    }
                }
                
                // RAM Section
                StatCard(title: "Mémoire RAM", icon: "memorychip", iconColor: .purple) {
                    VStack(alignment: .leading, spacing: 12) {
                        Sparkline(data: monitor.ram.history, longData: monitor.ram.longHistory, color: .purple, height: 60)
                        SparklineLegend(color: .purple)
                        
                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formatGB(monitor.ram.usedGB))
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(.purple)
                                Text("sur \(formatGB(monitor.ram.totalGB)) utilisés")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 8) {
                                MetricRow(label: "Active", value: formatGB(monitor.ram.activeGB))
                                MetricRow(label: "Inactive", value: formatGB(monitor.ram.inactiveGB))
                                MetricRow(label: "Wired", value: formatGB(monitor.ram.wiredGB))
                                MetricRow(label: "Compressée", value: formatGB(monitor.ram.compressedGB))
                                MetricRow(label: "Libre", value: formatGB(monitor.ram.freeGB), color: .green)
                            }
                            .frame(width: 200)
                        }
                        
                        ProgressBar(value: monitor.ram.pressure, color: .statusColor(for: monitor.ram.pressure))
                        
                        Divider()
                        
                        // Swap
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Swap (mémoire virtuelle)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text("Utilisé quand la RAM est pleine — signe de pression mémoire")
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
                                Text("Swap élevé — libère de l'espace disque ou ferme des apps")
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
                Text("Stockage")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                StatCard(title: "Disque principal", icon: "internaldrive", iconColor: .teal) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formatGB(monitor.disk.freeGB))
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(.teal)
                                Text("disponibles sur \(formatGB(monitor.disk.totalGB))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 8) {
                                MetricRow(label: "Utilisé", value: formatGB(monitor.disk.usedGB))
                                MetricRow(label: "Libre", value: formatGB(monitor.disk.freeGB),
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
                        
                        Text("\(Int(monitor.disk.usedPercent * 100))% utilisé")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if monitor.disk.usedPercent > 0.85 {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text("Disque presque plein — va dans le Nettoyeur pour libérer de l'espace")
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
                Text("Batterie")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                if !monitor.battery.isPresent {
                    Text("Aucune batterie détectée (Mac branché sans batterie)")
                        .foregroundColor(.secondary)
                } else {
                    StatCard(title: "État de la batterie", icon: "battery.100", iconColor: batteryColor()) {
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
                                        Text(monitor.battery.isCharging ? "En charge" : (monitor.battery.isPlugged ? "Branché (chargé)" : "Sur batterie"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .leading, spacing: 8) {
                                    MetricRow(label: "Temps restant", value: monitor.battery.timeRemaining)
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
                                    Text("Nombre de cycles élevé (\(monitor.battery.cycleCount)/1000) — la batterie approche de sa fin de vie")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            } else {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                    Text("Batterie en bonne santé (\(monitor.battery.cycleCount) cycles sur ~1000 max)")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                    
                    // Tips
                    StatCard(title: "Conseils", icon: "lightbulb", iconColor: .yellow) {
                        VStack(alignment: .leading, spacing: 8) {
                            tipRow(icon: "bolt.slash", text: "Ne charge pas à 100% en permanence — 20-80% est idéal")
                            tipRow(icon: "thermometer.medium", text: "Évite les environnements chauds, ils dégradent la batterie")
                            tipRow(icon: "moon.fill", text: "Active le mode 'Batterie optimisée' dans les Réglages")
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
                    Text("Processus")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                    Button("Actualiser") {
                        Task { await monitor.fetchProcesses() }
                    }
                    .buttonStyle(.bordered)
                }
                
                StatCard(title: "Top processus par CPU", icon: "cpu", iconColor: .orange) {
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("Processus").font(.caption).fontWeight(.semibold).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            Text("CPU").font(.caption).fontWeight(.semibold).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
                            Text("Mémoire").font(.caption).fontWeight(.semibold).foregroundColor(.secondary).frame(width: 80, alignment: .trailing)
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
