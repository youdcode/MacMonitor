import SwiftUI

struct CleanerView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var showingConfirmation = false

    var selected: [CacheItem] { monitor.caches.filter(\.isSelected) }
    var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.sizeBytes } }
    var totalBytes: Int64 { monitor.caches.reduce(0) { $0 + $1.sizeBytes } }
    var selectedRunningApps: [String] {
        Array(Set(selected.compactMap(\.runningAppName))).sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cleaner")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Caches found on this Mac, largest first")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await monitor.fetchCaches() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                // Always on the page, never a dismissible sheet.
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("These folders are caches. Applications rebuild them as they go, so removing one costs disk activity and a slower first launch, not data. Some of them still hold things you may care about, and only you know which. Read the paths before you select. Items are moved to the Trash, so a wrong choice can be undone until you empty it.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if let report = monitor.lastReport {
                    CleanupReportCard(report: report)
                }

                if monitor.caches.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        Text("No cache above 10 MB")
                            .font(.title3)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else {
                    StatCard(title: "Caches", icon: "archivebox", iconColor: .orange) {
                        VStack(spacing: 0) {
                            HStack {
                                Button("Select all") { setAllSelected(true) }
                                    .buttonStyle(.borderless)
                                    .foregroundColor(.blue)
                                Button("Deselect all") { setAllSelected(false) }
                                    .buttonStyle(.borderless)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(monitor.caches.count) items, \(formatBytes(totalBytes)) total")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.bottom, 12)

                            Divider()

                            ForEach($monitor.caches) { $item in
                                CacheRow(item: $item)
                                Divider()
                            }
                        }
                    }
                }

                if !selected.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        if !selectedRunningApps.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("\(selectedRunningApps.joined(separator: ", ")) \(selectedRunningApps.count == 1 ? "is" : "are") running. Removing a cache underneath a running app can interrupt whatever it is doing - a build in progress, an install, an export. Quitting it first is safer.")
                                    .font(.callout)
                                    .foregroundColor(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(selected.count) item\(selected.count > 1 ? "s" : "") selected")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("\(formatBytes(selectedBytes)) to move to the Trash")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Preview") {
                                monitor.cleanSelectedCaches(dryRun: true)
                            }
                            .buttonStyle(.bordered)
                            .disabled(monitor.isCleaning)
                            .help("List what would be moved, without touching anything")

                            Button {
                                showingConfirmation = true
                            } label: {
                                if monitor.isCleaning {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text("Working...")
                                    }
                                } else {
                                    Label("Move to Trash", systemImage: "trash")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(monitor.isCleaning)
                        }
                    }
                    .padding(16)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Move \(selected.count) item\(selected.count > 1 ? "s" : "") to the Trash?", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash") { monitor.cleanSelectedCaches() }
        } message: {
            Text("\(formatBytes(selectedBytes)) will be moved to the Trash. Nothing is freed on disk until you empty it.")
        }
    }

    func setAllSelected(_ value: Bool) {
        for i in monitor.caches.indices { monitor.caches[i].isSelected = value }
    }
}

// MARK: - Report

struct CleanupReportCard: View {
    let report: CacheRemovalReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: report.wasDryRun ? "eye" : "checkmark.circle.fill")
                    .foregroundColor(report.wasDryRun ? .blue : .green)
                if report.wasDryRun {
                    Text("Preview: \(report.outcomes.count) item\(report.outcomes.count > 1 ? "s" : "") would be moved to the Trash")
                        .font(.subheadline)
                } else {
                    Text("\(formatBytes(report.movedBytes)) moved to the Trash. Empty the Trash to reclaim it on disk.")
                        .font(.subheadline)
                }
                Spacer()
            }

            ForEach(report.outcomes) { outcome in
                if let problem = describe(outcome) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text("\(outcome.name): \(problem)")
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .background((report.failures.isEmpty ? Color.green : Color.red).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Only failures produce a line; successes are already covered by the total.
    private func describe(_ outcome: CacheRemovalOutcome) -> String? {
        switch outcome.result {
        case .movedToTrash, .wouldBeMovedToTrash: return nil
        case .rejected(let reason): return "not removed, \(reason)"
        case .failed(let reason): return "not removed, \(reason)"
        }
    }
}

// MARK: - Cache Row

struct CacheRow: View {
    @Binding var item: CacheItem

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $item.isSelected) {
                Text("Select \(item.name)")
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel("Select \(item.name), \(formatBytes(item.sizeBytes))")

            Image(systemName: item.icon)
                .foregroundColor(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13))
                        .fontWeight(.medium)
                    if let app = item.runningAppName {
                        Text("\(app) is running")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                    }
                }
                Text(item.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(formatBytes(item.sizeBytes))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(item.sizeBytes > 1_000_000_000 ? .orange : .primary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }
}
