import SwiftUI

struct ProcessesView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        DetailScreen(title: "Processes", subtitle: "Busiest first") {
            StatCard(title: "Top processes by CPU", icon: "list.bullet", iconColour: .orange) {
                VStack(spacing: 0) {
                    HStack {
                        Text("Process").frame(maxWidth: .infinity, alignment: .leading)
                        Text("CPU").frame(width: 58, alignment: .trailing)
                        Text("RSS").frame(width: 78, alignment: .trailing)
                        Text("PID").frame(width: 52, alignment: .trailing)
                    }
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 5)
                    .accessibilityHidden(true)

                    Divider()

                    ForEach(monitor.processes) { proc in
                        HStack {
                            Text(proc.name)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(Format.percent(proc.cpuPercent))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(proc.cpuPercent > 20 ? .orange : .primary)
                                .frame(width: 58, alignment: .trailing)
                            Text("\(Int(proc.memoryMB)) MB")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                                .frame(width: 78, alignment: .trailing)
                            Text("\(proc.id)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                                .frame(width: 52, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(proc.name)
                        .accessibilityValue("\(Format.percent(proc.cpuPercent)) CPU, \(Int(proc.memoryMB)) megabytes resident, process \(proc.id)")

                        Divider()
                    }
                }

                Text("CPU percentages come from ps, which reports a decaying average rather than an instantaneous reading, so they will not match Activity Monitor exactly. RSS is resident size, not the memory footprint Activity Monitor shows.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
