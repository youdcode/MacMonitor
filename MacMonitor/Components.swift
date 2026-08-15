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

    // Moyenne glissante sur les N derniers points de longData
    private func movingAvg(points: Int) -> [Double] {
        guard !longData.isEmpty, points > 0 else { return [] }
        let src = longData
        // 60 output points, evenly spread over the whole span of src
        let outCount = 60
        guard src.count >= 2 else { return Array(repeating: src.last ?? 0, count: outCount) }

        return (0..<outCount).map { i in
            // Position dans src correspondant au point i
            let pos = Int(Double(i) / Double(outCount - 1) * Double(src.count - 1))
            let start = max(0, pos - points / 2)
            let end   = min(src.count, pos + points / 2)
            let slice = src[start..<end]
            return slice.isEmpty ? 0 : slice.reduce(0, +) / Double(slice.count)
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

            // Moving averages, oldest to newest = most transparent to most opaque
            let avgConfigs: [(pts: Int, opacity: Double, width: CGFloat)] = [
                (1800, 0.20, 1.0),   // h1
                (450,  0.30, 1.0),   // m15
                (150,  0.40, 1.2),   // m5
                (30,   0.55, 1.4),   // m1
            ]

            ZStack {
                // Remplissage live (fond)
                makeFill(data: data, in: geo, safeMax: safeMax)
                    .fill(LinearGradient(
                        colors: [color.opacity(0.18), color.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    ))

                // Courbes moyennes glissantes (si longData dispo)
                if showAverages && longData.count > 30 {
                    ForEach(avgConfigs.indices, id: \.self) { idx in
                        let cfg = avgConfigs[idx]
                        makePath(data: movingAvg(points: cfg.pts), in: geo, safeMax: safeMax)
                            .stroke(
                                color.opacity(cfg.opacity),
                                style: StrokeStyle(lineWidth: cfg.width, lineCap: .round, lineJoin: .round)
                            )
                    }
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
            LegendItem(color: color, opacity: 1.0,  width: 2.0, label: "Live")
            LegendItem(color: color, opacity: 0.55, width: 1.4, label: "m1")
            LegendItem(color: color, opacity: 0.40, width: 1.2, label: "m5")
            LegendItem(color: color, opacity: 0.30, width: 1.0, label: "m15")
            LegendItem(color: color, opacity: 0.20, width: 1.0, label: "1h")
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

// MARK: - GB formatter

func formatGB(_ gb: Double) -> String {
    if gb < 0.1 { return "\(Int(gb * 1024))MB" }
    return String(format: "%.1f GB", gb)
}
