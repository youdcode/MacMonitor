import SwiftUI

/// Throughput. The counters were added natively earlier but had nowhere to appear.
struct NetworkView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        DetailScreen(title: "Network", subtitle: "All interfaces except loopback") {

            StatCard(title: "Throughput", icon: "network", iconColour: .indigo) {
                if let n = monitor.networkRate {
                    HStack(spacing: 28) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Format.rate(n.inBytesPerSecond))
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.indigo)
                            Text("down").font(.caption2).foregroundColor(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Download rate")
                        .accessibilityValue(Format.rate(n.inBytesPerSecond))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(Format.rate(n.outBytesPerSecond))
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.indigo)
                            Text("up").font(.caption2).foregroundColor(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Upload rate")
                        .accessibilityValue(Format.rate(n.outBytesPerSecond))

                        Spacer()
                    }

                    Sparkline(data: monitor.networkHistory,
                              scale: .relative,
                              colour: .indigo,
                              height: 44,
                              showTrend: false,
                              accessibilityDescription: "Combined network throughput over the last two minutes")
                } else {
                    Text("Sampling...").font(.caption).foregroundColor(.secondary)
                }
            }

            StatCard(title: "Since boot", icon: "sum", iconColour: .indigo) {
                if let total = monitor.networkTotals {
                    MetricRow(label: "Received", value: Format.bytes(Int64(total.bytesIn)))
                    MetricRow(label: "Sent", value: Format.bytes(Int64(total.bytesWritten)))
                } else {
                    Text("Sampling...").font(.caption).foregroundColor(.secondary)
                }
                Text("Loopback is excluded; VPN tunnels and other virtual interfaces are included.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
