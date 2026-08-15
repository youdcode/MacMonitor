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
                        Text("Nettoyeur")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Sélectionne les caches à supprimer")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await monitor.fetchCaches() }
                    } label: {
                        Label("Actualiser", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                
                // Last clean result
                if monitor.lastCleanedGB > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(String(format: "%.1f Go libérés lors du dernier nettoyage", monitor.lastCleanedGB))
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
                        Text("Aucun cache significatif trouvé")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text("Ton Mac est propre !")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else {
                    StatCard(title: "Caches détectés", icon: "archivebox", iconColor: .orange) {
                        VStack(spacing: 0) {
                            // Select all
                            HStack {
                                Button(action: selectAll) {
                                    Text("Tout sélectionner (sûr)")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.blue)
                                
                                Button(action: deselectAll) {
                                    Text("Tout désélectionner")
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
                            Text("\(selectedCount) élément\(selectedCount > 1 ? "s" : "") sélectionné\(selectedCount > 1 ? "s" : "")")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(String(format: "%.1f Go à libérer", selectedGB))
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
                                    Text("Nettoyage...")
                                }
                            } else {
                                Label("Nettoyer la sélection", systemImage: "trash")
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
                    Text("Seuls les caches marqués comme sûrs sont affichés. Les caches système sensibles sont exclus.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Confirmer le nettoyage", isPresented: $showingConfirmation) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {
                monitor.cleanSelectedCaches()
            }
        } message: {
            Text("Tu vas supprimer \(String(format: "%.1f Go", selectedGB)) de caches. Ces fichiers sont régénérés automatiquement par les apps.")
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
            return String(format: "%.1f Go", item.sizeGB)
        } else {
            return String(format: "%.0f Mo", item.sizeGB * 1024)
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
                Text("Système")
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
