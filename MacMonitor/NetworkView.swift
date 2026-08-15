import SwiftUI

struct NetworkView: View {
    @ObservedObject var monitor: SystemMonitor
    @StateObject private var speedTest = SpeedTest()

    var body: some View {
        DetailScreen(title: "Network", subtitle: "All interfaces except loopback") {
            currentThroughput
            capacityTest
            dials
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
        StatCard(title: "Speed test", icon: "gauge.high", iconColour: .indigo) {
            // Stated before the button, not in a footnote: on a metered connection this
            // is the whole decision.
            //
            // Once a complete test has been made, this is the reader's own last figure
            // rather than a rule they have to apply to themselves. It used to be a
            // number measured on the author's machine, which was wrong for everybody
            // else and most wrong for the people on a slow line - the ones the warning
            // is for.
            if let last = speedTest.lastVolume {
                Text("Your last test, on \(last.at.formatted(date: .abbreviated, time: .omitted)), moved \(Format.bytes(Int64(last.downloadBytes))) down and \(Format.bytes(Int64(last.uploadBytes))) up: \(Format.bytes(Int64(last.totalBytes))) in all.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("It fills the link for ten seconds each way, so what it moves follows what your connection carries - about \(SpeedTestFacts.megabytesPerMegabitPerSecond, specifier: "%.2f") MB for every Mbit/s, in each direction.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("The test fills the link for ten seconds in each direction, so what it moves is not a fixed amount: it follows what your connection carries, about \(SpeedTestFacts.megabytesPerMegabitPerSecond, specifier: "%.2f") MB for every Mbit/s, each way. After the first run this line says what yours actually cost.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("It runs the ndt7 test against M-Lab servers, only when you start it, and never on its own.")
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

            Text("M-Lab allows \(SpeedTestFacts.dailyTestLimit) tests per client per day. One request to its server list covers both directions, so a full test costs one of them.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 10) {
                switch speedTest.state {
                case .locating:
                    ProgressView().controlSize(.small)
                    Text("Finding a server...").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Cancel") { speedTest.cancel() }.buttonStyle(.bordered)

                case .running(let direction, let progress, _, _):
                    ProgressView(value: progress)
                        .frame(width: 130)
                        .accessibilityLabel("Speed test progress")
                        .accessibilityValue(Format.percent(ratio: progress))
                    Text(direction == .download ? "Measuring download..." : "Measuring upload...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Cancel") { speedTest.cancel() }.buttonStyle(.bordered)

                default:
                    Button {
                        speedTest.start()
                    } label: {
                        Label("Speed test", systemImage: "arrow.up.arrow.down.circle")
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

    // MARK: - The dials

    /// One card, live during the test and kept afterwards. The dials appear as soon as
    /// there is something to put on them and the needles climb while the test runs; a
    /// progress bar alone would waste a measurement the protocol hands over for nothing.
    @ViewBuilder
    private var dials: some View {
        switch speedTest.state {
        case .running(_, _, let download, let upload):
            dialCard(download: download, upload: upload, result: nil)
        case .finished(let result):
            dialCard(download: result.downloadMegabitsPerSecond,
                     upload: result.uploadMegabitsPerSecond,
                     result: result)
        default:
            EmptyView()
        }
    }

    private func dialCard(download: Double?, upload: Double?, result: SpeedTestResult?) -> some View {
        StatCard(title: result == nil ? "Measuring capacity" : "Measured capacity",
                 icon: result?.tier.symbol ?? "gauge.high",
                 iconColour: result?.tier.colour ?? .indigo) {

            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 7) {
                    SpeedGauge(megabitsPerSecond: download,
                               caption: "Download",
                               accessibilityName: "Download capacity",
                               colour: .indigo)
                    if let result {
                        // The rating hangs under the download dial, which is what it
                        // describes. Symbol as well as colour, so it survives greyscale
                        // and a colour-blind reader.
                        HStack(spacing: 5) {
                            Image(systemName: result.tier.symbol).font(.caption)
                            Text(result.tier.label).font(.caption)
                        }
                        .foregroundColor(result.tier.colour)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Download rating")
                        .accessibilityValue(result.tier.label)
                    }
                }

                SpeedGauge(megabitsPerSecond: upload,
                           caption: "Upload",
                           accessibilityName: "Upload capacity",
                           colour: .indigo)

                Spacer(minLength: 8)

                if let result {
                    VStack(spacing: 5) {
                        MetricRow(label: "Measured", value: result.finishedAt.formatted(date: .omitted, time: .standard))
                        MetricRow(label: "Downloaded", value: Format.bytes(Int64(result.downloadBytes)))
                        MetricRow(label: "Uploaded", value: Format.bytes(Int64(result.uploadBytes)))
                        // The one that matters on a metered connection, spelled out
                        // rather than left as an addition for the reader to do.
                        MetricRow(label: "Total moved", value: Format.bytes(Int64(result.totalBytes)))
                        MetricRow(label: "Server", value: result.server.components(separatedBy: ".").first ?? result.server)
                    }
                    .frame(width: 210)
                }
            }

            if let result {
                if let failure = result.uploadFailure {
                    Label("The upload half did not finish: \(failure)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Only ever computed from a measured capacity, never from idle
                // throughput, and from the download because that is the direction a
                // film arrives in.
                if let seconds = TransferEstimate.seconds(forBytes: TransferEstimate.fourKFilmBytes,
                                                          atMegabitsPerSecond: result.downloadMegabitsPerSecond) {
                    Text("At this download rate a 15 GB 4K film takes \(TransferEstimate.humanDuration(seconds: seconds)).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("Capacity, measured by filling the link in each direction. The rating describes the download. Not comparable with the throughput above.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
