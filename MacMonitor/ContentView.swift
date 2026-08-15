import SwiftUI

enum Tab: String, CaseIterable {
    case overview  = "Overview"
    case cpu       = "CPU & Memory"
    case thermal   = "Thermal"
    case disk      = "Storage"
    case battery   = "Battery"
    case processes = "Processes"
    case cleaner   = "Cleaner"

    var icon: String {
        switch self {
        case .overview:  return "gauge.medium"
        case .cpu:       return "cpu"
        case .thermal:   return "thermometer.medium"
        case .disk:      return "internaldrive"
        case .battery:   return "battery.100"
        case .processes: return "list.bullet.rectangle"
        case .cleaner:   return "trash"
        }
    }
}

struct ContentView: View {
    @StateObject var monitor = SystemMonitor()
    @State private var selectedTab: Tab = .overview

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                HStack {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                    Spacer()
                    if tab == .overview && !monitor.alerts.isEmpty {
                        Text("\(monitor.alerts.count)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                    if tab == .thermal && !monitor.powermetricsEnabled {
                        StatusDot(color: .orange)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Mac Monitor")

            VStack(alignment: .leading, spacing: 4) {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(monitor.macModel)
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("Uptime: \(monitor.uptime)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        } detail: {
            Group {
                switch selectedTab {
                case .overview:  OverviewView(monitor: monitor)
                case .cpu:       CPURAMView(monitor: monitor)
                case .thermal:   ThermalView(monitor: monitor)
                case .disk:      DiskView(monitor: monitor)
                case .battery:   BatteryView(monitor: monitor)
                case .processes: ProcessesView(monitor: monitor)
                case .cleaner:   CleanerView(monitor: monitor)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onDisappear { monitor.stopMonitoring() }

    }
}
