import SwiftUI

/// Sidebar entries, grouped the way the Finder groups its own.
///
/// Thermal no longer has an entry: a four-level signal and a list of what those four
/// levels mean did not justify one, and the state describes the chip, so it lives in
/// Processor. Network gained one: the throughput counters had nowhere to appear.
enum Tab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case processor = "Processor"
    case memory = "Memory"
    case storage = "Storage"
    case network = "Network"
    case battery = "Battery"
    case processes = "Processes"
    case cleaner = "Cleaner"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "gauge.medium"
        case .processor: return "cpu"
        case .memory: return "memorychip"
        case .storage: return "internaldrive"
        case .network: return "network"
        case .battery: return "battery.100"
        case .processes: return "list.bullet.rectangle"
        case .cleaner: return "trash"
        }
    }

    static let hardware: [Tab] = [.processor, .memory, .storage, .network, .battery]
    static let tools: [Tab] = [.processes, .cleaner]
}

struct ContentView: View {
    @StateObject private var monitor = SystemMonitor()
    @State private var selection: Tab = .overview
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label(Tab.overview.rawValue, systemImage: Tab.overview.icon)
                    .tag(Tab.overview)

                Section("Hardware") {
                    ForEach(Tab.hardware) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }

                Section("Tools") {
                    ForEach(Tab.tools) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Mac Monitor")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 1) {
                    Divider()
                    Text(monitor.macModel)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.top, 6)
                    Text(monitor.macOS)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        } detail: {
            Group {
                switch selection {
                case .overview: OverviewView(monitor: monitor)
                case .processor: ProcessorView(monitor: monitor)
                case .memory: MemoryView(monitor: monitor)
                case .storage: StorageView(monitor: monitor)
                case .network: NetworkView(monitor: monitor)
                case .battery: BatteryView(monitor: monitor)
                case .processes: ProcessesView(monitor: monitor)
                case .cleaner: CleanerView(monitor: monitor)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Only the visible screen's detail is collected. Everything else stays on the
        // permanent set that Overview and the alerts need.
        .onChange(of: selection) { newValue in
            monitor.setVisibleScope(newValue.scope)
        }
        // Suspended when the window is not frontmost, resumed when it comes back.
        // startMonitoring is idempotent, and onAppear calls it: stopMonitoring used to
        // be a one-way door with nothing to reopen it.
        .onChange(of: controlActiveState) { state in
            switch state {
            case .key, .active: monitor.resume()
            default: monitor.suspend()
            }
        }
        .onAppear {
            monitor.setVisibleScope(selection.scope)
            monitor.startMonitoring()
        }
        .onDisappear { monitor.stopMonitoring() }
    }
}

extension Tab {
    /// What each screen needs beyond the permanent set.
    var scope: CollectionScope {
        switch self {
        case .overview: return .none
        case .processor: return .processor
        case .memory: return .none          // the permanent set already covers memory
        case .storage: return .storage
        case .network: return .network
        case .battery: return .battery
        case .processes: return .none       // processes are in the permanent set
        case .cleaner: return .none
        }
    }
}
