import SwiftUI

struct NetworkView: View {
    @ObservedObject var monitor: SystemMonitor
    @StateObject private var speedTest = SpeedTest()

    var body: some View {
        DetailScreen(title: "Network", subtitle: "All interfaces except loopback") {
            currentThroughput
            capacityTest
            if case .finished(let result) = speedTest.state { capacityResult(result) }
            totals
        }
    }

    // MARK: - Current throughput

    private var currentThroughput: some View {
        StatCard(title: "Current throughput", icon: "network", iconColour: .indigo) {
            if let n = monitor.networkRate {
                HStack(spacing: 28) {
                    reading(Format.rate(n.inBytesPerSecond), "down", "Current download throughput")
                    reading(Format.rate(n.outBytesPerSecond), "up", "Current upload throughput")
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

            // The distinction that catches everyone, including the author of this app.
            Text("This is what is passing right now, not what the link can carry. A connection sitting idle shows a few kilobytes per second on a line capable of a hundred megabytes per second, and both numbers are correct. Use the test below to measure capacity.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reading(_ value: String, _ caption: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundColor(.indigo)
            Text(caption).font(.caption2).foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    // MARK: - Capacity test

    private var capacityTest: some View {
        StatCard(title: "Download speed test", icon: "gauge.high", iconColour: .indigo) {
            // Stated before the button, not in a footnote: on a metered connection this
            // is the whole decision.
            Text("This test downloads about \(Int(SpeedTestFacts.approximateDownloadBytes / 1_000_000)) MB. It runs the ndt7 test against M-Lab servers, only when you start it, and never on its own.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(SpeedTestFacts.privacyNote)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("M-Lab privacy policy", destination: SpeedTestFacts.privacyURL)
                        .font(.caption2)
                }
            }
            .accessibilityElement(children: .combine)

            Text("M-Lab allows \(SpeedTestFacts.dailyTestLimit) tests per client per day.")
                .font(.caption2)
                .foregroundColor(.secondary)

            Divider()

            HStack(spacing: 10) {
                switch speedTest.state {
                case .locating:
                    ProgressView().controlSize(.small)
                    Text("Finding a server...").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Cancel") { speedTest.cancel() }.buttonStyle(.bordered)

                case .running(let progress, let mbps):
                    ProgressView(value: progress)
                        .frame(width: 130)
                        .accessibilityLabel("Speed test progress")
                        .accessibilityValue(Format.percent(ratio: progress))
                    Text(String(format: "%.0f Mbit/s", mbps))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                    Spacer()
                    Button("Cancel") { speedTest.cancel() }.buttonStyle(.bordered)

                default:
                    Button {
                        speedTest.start()
                    } label: {
                        Label("Download speed test", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
            }

            if case .failed(let reason) = speedTest.state {
                Label("Test failed: \(reason)", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .cancelled = speedTest.state {
                Text("Test cancelled.").font(.caption).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Capacity result

    private func capacityResult(_ result: SpeedTestResult) -> some View {
        StatCard(title: "Measured capacity", icon: result.tier.symbol, iconColour: result.tier.colour) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.0f Mbit/s", result.megabitsPerSecond))
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundColor(result.tier.colour)
                    HStack(spacing: 5) {
                        Image(systemName: result.tier.symbol)
                            .font(.caption)
                            .foregroundColor(result.tier.colour)
                        Text(result.tier.label)
                            .font(.caption)
                            .foregroundColor(result.tier.colour)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Measured download capacity")
                .accessibilityValue("\(Int(result.megabitsPerSecond)) megabits per second, \(result.tier.label)")

                Spacer()

                VStack(spacing: 5) {
                    MetricRow(label: "Measured", value: result.finishedAt.formatted(date: .omitted, time: .standard))
                    MetricRow(label: "Transferred", value: Format.bytes(Int64(result.bytesTransferred)))
                    MetricRow(label: "Server", value: result.server.components(separatedBy: ".").first ?? result.server)
                }
                .frame(width: 210)
            }

            // Only ever computed from a measured capacity, never from idle throughput.
            if let seconds = TransferEstimate.seconds(forBytes: TransferEstimate.fourKFilmBytes,
                                                      atMegabitsPerSecond: result.megabitsPerSecond) {
                Text("At this rate a 15 GB 4K film takes \(TransferEstimate.humanDuration(seconds: seconds)).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Capacity, measured by filling the link. Not comparable with the throughput above.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Totals

    private var totals: some View {
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
