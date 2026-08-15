import SwiftUI

// MARK: - Gauge Ring

struct RingGauge: View {
    var value: Double // 0 to 1
    var color: Color
    var size: CGFloat = 80
    var lineWidth: CGFloat = 8
    var label: String
    var sublabel: String
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.12), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: min(value, 1))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: value)
                VStack(spacing: 1) {
                    Text("\(Int(value * 100))%")
                        .font(.system(size: size * 0.22, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                }
            }
            .frame(width: size, height: size)
            
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            Text(sublabel)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Sparkline with moving averages

struct Sparkline: View {
    var data: [Double]           // 60 pts live (2 min)
    var longData: [Double] = []  // 1800 pts (1h) - source for the m1/m5/m15/h1 averages
    var color: Color
    var height: CGFloat = 40
    var showAverages: Bool = true

    /// Downsamples longData to `outCount` points by averaging each bucket.
    ///
    /// Replaces a per-render moving average that recomputed four windows of
    /// 1800/450/150/30 points from inside `body` - roughly 146 000 additions per
    /// sparkline per render, on the main thread, memoised nowhere. One pass gives the
    /// same visual result for a fraction of the work.
    private func downsampled(_ source: [Double], into outCount: Int) -> [Double] {
        guard outCount > 0 else { return [] }
        guard source.count > outCount else { return source }
        let bucket = Double(source.count) / Double(outCount)
        return (0..<outCount).map { i in
            let lower = Int(Double(i) * bucket)
            let upper = min(source.count, max(lower + 1, Int(Double(i + 1) * bucket)))
            let slice = source[lower..<upper]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    private func makePath(data pts: [Double], in geo: GeometryProxy, safeMax: Double) -> Path {
        var path = Path()
        guard pts.count > 1 else { return path }
        let w = geo.size.width
        let h = geo.size.height
        let step = w / CGFloat(pts.count - 1)
        for (i, val) in pts.enumerated() {
            let x = CGFloat(i) * step
            let y = h - (CGFloat(val / safeMax) * h * 0.88)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else       { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }

    private func makeFill(data pts: [Double], in geo: GeometryProxy, safeMax: Double) -> Path {
        var path = Path()
        guard pts.count > 1 else { return path }
        let w = geo.size.width
        let h = geo.size.height
        let step = w / CGFloat(pts.count - 1)
        path.move(to: CGPoint(x: 0, y: h))
        for (i, val) in pts.enumerated() {
            let x = CGFloat(i) * step
            let y = h - (CGFloat(val / safeMax) * h * 0.88)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()
        return path
    }

    var body: some View {
        GeometryReader { geo in
            let allData   = showAverages && !longData.isEmpty ? longData : data
            let globalMax = allData.max() ?? 1
            let safeMax   = globalMax < 0.01 ? 1.0 : globalMax

            let trend = showAverages && longData.count > 30 ? downsampled(longData, into: 60) : []

            ZStack {
                // Remplissage live (fond)
                makeFill(data: data, in: geo, safeMax: safeMax)
                    .fill(LinearGradient(
                        colors: [color.opacity(0.18), color.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    ))

                if !trend.isEmpty {
                    makePath(data: trend, in: geo, safeMax: safeMax)
                        .stroke(color.opacity(0.35),
                                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                }

                // Live curve - the most visible one
                makePath(data: data, in: geo, safeMax: safeMax)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Moving-average legend
struct SparklineLegend: View {
    var color: Color

    var body: some View {
        HStack(spacing: 14) {
            LegendItem(color: color, opacity: 1.0,  width: 2.0, label: "Live, 2 min")
            LegendItem(color: color, opacity: 0.35, width: 1.2, label: "Trend, 1 h")
        }
    }
}

struct LegendItem: View {
    var color: Color
    var opacity: Double
    var width: CGFloat
    var label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color.opacity(opacity))
                .frame(width: 14, height: width + 0.5)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Stat Card

struct StatCard<Content: View>: View {
    var title: String
    var icon: String
    var iconColor: Color
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
            }
            content()
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Metric Row

struct MetricRow: View {
    var label: String
    var value: String
    var color: Color = .primary
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}

// MARK: - Progress Bar

struct ProgressBar: View {
    var value: Double
    var color: Color
    var height: CGFloat = 6
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color.opacity(0.12))
                    .frame(height: height)
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color)
                    .frame(width: geo.size.width * min(value, 1), height: height)
                    .animation(.easeInOut(duration: 0.5), value: value)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Status Dot

struct StatusDot: View {
    var color: Color
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}

// MARK: - Color helpers

extension Color {
    static func statusColor(for value: Double) -> Color {
        if value < 0.6 { return .green }
        if value < 0.8 { return .orange }
        return .red
    }
}

// MARK: - Size formatters

/// Formats a throughput in bytes per second.
func formatRate(_ bytesPerSecond: Double) -> String {
    let b = max(bytesPerSecond, 0)
    if b >= 1_000_000 { return String(format: "%.1f MB/s", b / 1_000_000) }
    if b >= 1_000 { return String(format: "%.0f KB/s", b / 1_000) }
    return "0 KB/s"
}

/// Formats a value already expressed in BINARY gigabytes (2^30). Use for memory,
/// which is what the hardware and the kernel report.
func formatMemoryGB(_ gb: Double) -> String {
    if gb < 0.1 { return "\(Int(gb * 1024)) MB" }
    return String(format: "%.1f GB", gb)
}

/// Formats a raw byte count in decimal units, the way Finder shows file sizes.
func formatBytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000
    if gb >= 1 { return String(format: "%.1f GB", gb) }
    return "\(bytes / 1_000_000) MB"
}

/// Formats a value already expressed in DECIMAL gigabytes (10^9). Use for storage,
/// which is how Finder and System Settings count it.
func formatStorageGB(_ gb: Double) -> String {
    if gb < 0.1 { return "\(Int(gb * 1000)) MB" }
    return String(format: "%.1f GB", gb)
}
