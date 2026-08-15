import SwiftUI

struct StorageView: View {
    @ObservedObject var monitor: SystemMonitor

    private var status: Status {
        // Two conditions, one named threshold each. This used to be four different
        // numbers in four files: 80%, 85%, 90% and "under 10 GB".
        let byBytes = Int64(monitor.disk.freeGB * 1_000_000_000) < Threshold.lowStorageBytes
        let byRatio = Status.forOccupancy(monitor.disk.usedPercent)
        return byBytes ? .critical : byRatio
    }

    var body: some View {
        DetailScreen(title: "Storage", subtitle: "Startup disk") {

            StatCard(title: "Capacity", icon: "internaldrive", iconColour: .teal) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Format.storage(monitor.disk.freeGB))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(status.colour)
                        Text("available of \(Format.storage(monitor.disk.totalGB))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Storage available")
                    .accessibilityValue("\(Format.storage(monitor.disk.freeGB)) of \(Format.storage(monitor.disk.totalGB))")

                    Spacer()

                    VStack(spacing: 5) {
                        MetricRow(label: "Used", value: Format.storage(monitor.disk.usedGB))
                        MetricRow(label: "Free", value: Format.storage(monitor.disk.freeGB))
                        MetricRow(label: "Total", value: Format.storage(monitor.disk.totalGB))
                    }
                    .frame(width: 180)
                }

                ProgressBar(value: monitor.disk.usedPercent,
                            status: status,
                            height: 8,
                            accessibilityDescription: "Storage used")

                Text("Counted in decimal gigabytes, the way Finder and System Settings count.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            StatCard(title: "Activity", icon: "arrow.up.arrow.down", iconColour: .teal) {
                if let io = monitor.diskIORate {
                    HStack(spacing: 28) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Format.rate(io.readBytesPerSecond))
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text("read").font(.caption2).foregroundColor(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Disk read rate")
                        .accessibilityValue(Format.rate(io.readBytesPerSecond))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(Format.rate(io.writeBytesPerSecond))
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text("write").font(.caption2).foregroundColor(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Disk write rate")
                        .accessibilityValue(Format.rate(io.writeBytesPerSecond))

                        Spacer()
                    }
                } else {
                    Text("Sampling...").font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }
}
