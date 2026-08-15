import SwiftUI

/// Everything about the chip: load, core clusters, GPU, and the thermal state.
///
/// Thermal used to have a tab of its own. A four-value signal and a list of what those
/// four values mean did not justify one, and the state is a property of the SoC, so it
/// belongs next to the load that causes it.
struct ProcessorView: View {
    @ObservedObject var monitor: SystemMonitor

    private var cpuStatus: Status { Status.forOccupancy(monitor.cpu.total / 100) }

    var body: some View {
        DetailScreen(title: "Processor", subtitle: monitor.macModel) {

            StatCard(title: "Load", icon: "cpu", iconColour: .blue) {
                Sparkline(data: monitor.cpu.history,
                          longData: monitor.cpu.longHistory,
                          scale: .percent,
                          colour: .blue,
                          height: 54,
                          accessibilityDescription: "Processor load over the last two minutes")
                SparklineLegend(colour: .blue)

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Format.percent(monitor.cpu.total))
                            .font(.system(.title, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundColor(cpuStatus.colour)
                        Text("in use")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Processor in use")
                    .accessibilityValue(Format.percent(monitor.cpu.total))

                    Spacer()

                    VStack(spacing: 5) {
                        MetricRow(label: "User", value: Format.percent(monitor.cpu.user))
                        MetricRow(label: "System", value: Format.percent(monitor.cpu.system))
                        MetricRow(label: "Idle", value: Format.percent(monitor.cpu.idle))
                    }
                    .frame(width: 180)
                }

                ProgressBar(value: monitor.cpu.total / 100,
                            status: cpuStatus,
                            accessibilityDescription: "Processor load")
            }

            HStack(alignment: .top, spacing: 12) {
                StatCard(title: "Cores", icon: "square.grid.2x2", iconColour: .blue) {
                    if let p = monitor.clusterLoad.performance {
                        MetricRow(label: "Performance", value: Format.percent(p))
                    }
                    if let e = monitor.clusterLoad.efficiency {
                        MetricRow(label: "Efficiency", value: Format.percent(e))
                    }
                    if monitor.clusterLoad.performance == nil && monitor.clusterLoad.efficiency == nil {
                        Text("Single cluster")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                StatCard(title: "Load average", icon: "chart.bar", iconColour: .blue) {
                    if let l = monitor.loadAverages {
                        MetricRow(label: "1 min", value: Format.decimal(l.one))
                        MetricRow(label: "5 min", value: Format.decimal(l.five))
                        MetricRow(label: "15 min", value: Format.decimal(l.fifteen))
                    } else {
                        Text("Unavailable").font(.caption).foregroundColor(.secondary)
                    }
                }

                StatCard(title: "GPU", icon: "cpu.fill", iconColour: .pink) {
                    if let g = monitor.gpu, let device = g.deviceUtilization {
                        ProgressBar(value: device / 100,
                                    status: Status.forOccupancy(device / 100),
                                    accessibilityDescription: "GPU utilisation")
                        MetricRow(label: "Device", value: Format.percent(device))
                        if let r = g.rendererUtilization { MetricRow(label: "Renderer", value: Format.percent(r)) }
                        if let t = g.tilerUtilization { MetricRow(label: "Tiler", value: Format.percent(t)) }
                    } else {
                        Text("No accelerator reported").font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            ThermalCard(monitor: monitor)
        }
    }
}

/// The thermal state, folded in from what used to be its own tab.
struct ThermalCard: View {
    @ObservedObject var monitor: SystemMonitor

    private var status: Status {
        switch monitor.thermal.thermalLevel {
        case "Critical": return .critical
        case "Serious": return .warning
        case "Fair": return .warning
        default: return .normal
        }
    }

    var body: some View {
        StatCard(title: "Thermal state", icon: "thermometer.medium", iconColour: status.colour) {
            HStack(alignment: .top, spacing: 12) {
                StatusDot(status: status, accessibilityDescription: "Thermal state")

                VStack(alignment: .leading, spacing: 3) {
                    Text(monitor.thermal.thermalLevel)
                        .font(.headline)
                        .foregroundColor(status.colour)
                    Text(monitor.thermal.thermalDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)

            Text("macOS publishes a four-level thermal state. No CPU or GPU temperature was reachable from a third-party process on the machine this was tested on, so there is no reading in degrees here.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
