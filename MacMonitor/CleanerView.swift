import SwiftUI

struct CleanerView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var showingConfirmation = false
    
    var selectedCount: Int { monitor.caches.filter { $0.isSelected }.count }
    var selectedGB: Double { monitor.caches.filter { $0.isSelected }.reduce(0) { $0 + $1.sizeGB } }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cleaner")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Select the caches to remove")
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
                
                // Last cleanup result
                if monitor.lastCleanedGB > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(String(format: "%.1f GB freed in the last cleanup", monitor.lastCleanedGB))
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                // Cache list
                if monitor.caches.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        Text("No significant cache found")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text("Your Mac is clean!")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else {
                    StatCard(title: "Detected caches", icon: "archivebox", iconColor: .orange) {
                        VStack(spacing: 0) {
                            // Select all
                            HStack {
                                Button(action: selectAll) {
                                    Text("Select all (safe)")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.blue)
                                
                                Button(action: deselectAll) {
                                    Text("Deselect all")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text("Total: \(formatGB(totalCacheGB()))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.bottom, 12)
                            
                            Divider()
                            
                            ForEach(monitor.caches.indices, id: \.self) { i in
                                CacheRow(item: $monitor.caches[i])
                                Divider()
                            }
                        }
                    }
                }
                
                // Action bar
                if selectedCount > 0 {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(selectedCount) item\(selectedCount > 1 ? "s" : "") selected")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(String(format: "%.1f GB to free", selectedGB))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            showingConfirmation = true
                        } label: {
                            if monitor.isCleaning {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Cleaning...")
                                }
                            } else {
                                Label("Clean selection", systemImage: "trash")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(monitor.isCleaning)
                        .tint(.red)
                    }
                    .padding(16)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.2), lineWidth: 1))
                }
                
                // Warning
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("Only caches marked as safe are shown. Sensitive system caches are excluded.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Confirm cleanup", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                monitor.cleanSelectedCaches()
            }
        } message: {
            Text("You are about to delete \(String(format: "%.1f GB", selectedGB)) of caches. Apps regenerate these files automatically.")
        }
    }
    
    func selectAll() {
        for i in monitor.caches.indices {
            if monitor.caches[i].isSafe {
                monitor.caches[i].isSelected = true
            }
        }
    }
    
    func deselectAll() {
        for i in monitor.caches.indices {
            monitor.caches[i].isSelected = false
        }
    }
    
    func totalCacheGB() -> Double {
        monitor.caches.reduce(0) { $0 + $1.sizeGB }
    }
}

// MARK: - Cache Row

struct CacheRow: View {
    @Binding var item: CacheItem
    
    var sizeLabel: String {
        if item.sizeGB >= 1 {
            return String(format: "%.1f GB", item.sizeGB)
        } else {
            return String(format: "%.0f MB", item.sizeGB * 1024)
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $item.isSelected)
                .toggleStyle(.checkbox)
                .disabled(!item.isSafe)
            
            Image(systemName: item.icon)
                .foregroundColor(item.isSafe ? .primary : .secondary)
                .frame(width: 18)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13))
                    .fontWeight(.medium)
                Text(item.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if !item.isSafe {
                Text("System")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundColor(.secondary)
            }
            
            Text(sizeLabel)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(item.sizeGB > 1 ? .orange : .primary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if item.isSafe { item.isSelected.toggle() }
        }
    }
}
