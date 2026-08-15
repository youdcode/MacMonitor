import SwiftUI

struct BatteryView: View {
    @ObservedObject var monitor: SystemMonitor

    private var colour: Color {
        batteryStatusColour(percentage: monitor.battery.percentage, isCharging: monitor.battery.isCharging)
    }

    private var stateLabel: String {
        if monitor.battery.isCharging { return "Charging" }
        if monitor.battery.isPlugged { return "Plugged in" }
        return "On battery"
    }

    var body: some View {
        DetailScreen(title: "Battery", subtitle: stateLabel) {
            if !monitor.battery.isPresent {
                StatCard(title: "No battery", icon: "powerplug", iconColour: .secondary) {
                    Text("This Mac has no internal battery.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                StatCard(title: "Charge", icon: "battery.100", iconColour: colour) {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(monitor.battery.percentage)%")
                                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                                .monospacedDigit()
                                .foregroundColor(colour)
                            Text(stateLabel).font(.caption2).foregroundColor(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Battery charge")
                        .accessibilityValue("\(monitor.battery.percentage) percent, \(stateLabel)")

                        Spacer()

                        VStack(spacing: 5) {
                            MetricRow(label: "Time remaining", value: monitor.battery.timeRemaining)
                            MetricRow(label: "Cycles",
                                      value: "\(monitor.battery.cycleCount) of ~\(Threshold.batteryCycleRating)",
                                      colour: monitor.battery.cycleCount > Threshold.batteryCycleWarning ? .orange : .primary)
                            MetricRow(label: "Condition", value: monitor.battery.health)
                        }
                        .frame(width: 210)
                    }

                    ProgressBar(value: Double(monitor.battery.percentage) / 100,
                                status: monitor.battery.percentage > 20 ? .normal : .critical,
                                height: 8,
                                accessibilityDescription: "Battery charge")
                }

                if let d = monitor.batteryDetail {
                    HStack(alignment: .top, spacing: 12) {
                        StatCard(title: "Sensors", icon: "thermometer.medium", iconColour: .orange) {
                            if let t = d.temperature {
                                MetricRow(label: "Temperature", value: String(format: "%.1f C", t))
                            }
                            if let p = d.power, abs(p) > 0.05 {
                                MetricRow(label: "Power", value: String(format: "%.1f W", p))
                            }
                            if d.temperature == nil && d.power == nil {
                                Text("Unavailable").font(.caption).foregroundColor(.secondary)
                            }
                        }

                        StatCard(title: "Full-charge capacity", icon: "bolt.badge.clock", iconColour: .orange) {
                            if let ratio = d.fullChargeRatio, let raw = d.rawMaxCapacity, let design = d.designCapacity {
                                MetricRow(label: "Measured", value: "\(raw) of \(design) mAh")
                                MetricRow(label: "Ratio", value: Format.percent(ratio: ratio))
                                Text("AppleRawMaxCapacity over DesignCapacity. This is deliberately not labelled Maximum Capacity: it does not reproduce the figure System Settings shows, and Apple's formula is not published. Expect it a few points lower.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text("Unavailable").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}
