import SwiftUI

// Reusable pieces of the interface.
//
// Two rules run through all of them. Every number that changes while you watch it
// carries .monospacedDigit(), because proportional digits have different widths and
// the layout shifts on every refresh. And every element that carries meaning has an
// accessibility label and value that say the reading, not the name of the component:
// a shape drawn with Path is completely invisible to VoiceOver otherwise.

// MARK: - Ring gauge

struct RingGauge: View {
    var value: Double            // 0 to 1
    var status: Status
    var size: CGFloat = 76
    var lineWidth: CGFloat = 7
    var label: String
    var detail: String

    /// Rounded once, here, and used for both the centre and the caption. They were
    /// computed separately before - Int() truncating in one place, %.0f rounding in
    /// the other - so the same gauge could read 45% in its middle and 46% below it.
    private var percentText: String { Format.percent(ratio: value) }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(status.colour.opacity(0.12), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: min(max(value, 0), 1))
                    .stroke(status.colour, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: value)
                Text(percentText)
                    // Deliberately proportional to the ring rather than to the text
                    // size setting: the glyph has to fit inside a circle of a known
                    // diameter, and Dynamic Type would push it outside. The reading is
                    // available to VoiceOver and repeated in the caption below, which
                    // does scale.
                    .font(.system(size: size * 0.25, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: size, height: size)

            Text(label)
                .font(.caption)
                .fontWeight(.medium)
            Text(detail)
                .font(.caption2)
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(percentText), \(detail), \(status.label)")
    }
}

// MARK: - Speed dial

/// A dial for a measured link capacity, on the logarithmic scale in GaugeScale.
///
/// Deliberately not a RingGauge. A ring runs 0 to 100 % and closes; this runs 1 to
/// 1000 Mbit/s on a logarithmic scale and has two stops, which is a different thing and
/// has to look like one.
///
/// The colour is the screen's accent, not a verdict. Whether a speed is good is said in
/// words and a symbol underneath, by the caller, because a coloured arc on its own
/// tells a colour-blind reader nothing - the same rule that put a shape on every status
/// in this application.
struct SpeedGauge: View {

    /// nil until this direction has been measured. An empty dial reading zero would be
    /// a statement, and a false one: not measured and measured at zero are not the same
    /// thing, so the middle shows a dash and the needle is absent.
    var megabitsPerSecond: Double?
    var caption: String
    /// Spoken by VoiceOver in place of the drawing. "Download capacity", say.
    var accessibilityName: String
    var colour: Color
    var size: CGFloat = 152

    /// Degrees of travel, and where the left stop sits, measured clockwise from twelve
    /// o'clock. 225 + 270 = 495, which is 135: the two stops sit at half past four and
    /// half past seven, leaving the bottom ninety degrees open for the readout.
    private let sweep: Double = 270
    private let zeroAngle: Double = 225

    // Radii, as fractions of the dial's width. The arc sits inside the ticks, the ticks
    // inside the labels, and the readout inside all of it.
    private var arcRadius: CGFloat { size * 0.330 }
    private var arcWidth: CGFloat { size * 0.050 }
    private var tickInner: CGFloat { size * 0.368 }
    private var labelRadius: CGFloat { size * 0.462 }

    private var fraction: Double {
        guard let value = megabitsPerSecond else { return 0 }
        return GaugeScale.fraction(forMegabitsPerSecond: value)
    }

    private func angle(for value: Double) -> Double {
        zeroAngle + sweep * GaugeScale.fraction(forMegabitsPerSecond: value)
    }

    /// Three significant figures at most, and never more than four characters, so the
    /// readout does not resize as the needle climbs during a test.
    private var reading: String {
        guard let value = megabitsPerSecond else { return "—" }
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }

    private var spokenValue: String {
        guard megabitsPerSecond != nil else { return "not measured" }
        return "\(reading) megabits per second"
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                track
                if megabitsPerSecond != nil { value }
                ticks
                tickLabels
                if megabitsPerSecond != nil { marker }
                readout
            }
            .frame(width: size, height: size)

            Text(caption)
                .font(.caption)
                .fontWeight(.medium)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(spokenValue)
    }

    // MARK: - Parts

    private var track: some View {
        Circle()
            .trim(from: 0, to: sweep / 360)
            .stroke(Color.primary.opacity(0.10), style: StrokeStyle(lineWidth: arcWidth, lineCap: .round))
            .frame(width: arcRadius * 2, height: arcRadius * 2)
            .rotationEffect(.degrees(zeroAngle - 90))
    }

    private var value: some View {
        Circle()
            .trim(from: 0, to: (sweep / 360) * fraction)
            .stroke(colour, style: StrokeStyle(lineWidth: arcWidth, lineCap: .round))
            .frame(width: arcRadius * 2, height: arcRadius * 2)
            .rotationEffect(.degrees(zeroAngle - 90))
            .animation(.easeOut(duration: 0.25), value: fraction)
    }

    private var ticks: some View {
        ZStack {
            ForEach(GaugeScale.majorTicks, id: \.self) { tick(at: $0, length: size * 0.048, width: 1.6) }
            ForEach(GaugeScale.minorTicks, id: \.self) { tick(at: $0, length: size * 0.028, width: 1) }
        }
    }

    /// Offset, then rotate. The offset moves the drawing without moving the layout
    /// frame, so the rotation still turns about the centre of the dial and the mark
    /// orbits it.
    private func tick(at value: Double, length: CGFloat, width: CGFloat) -> some View {
        Capsule()
            .fill(Color.secondary.opacity(0.5))
            .frame(width: width, height: length)
            .offset(y: -(tickInner + length / 2))
            .rotationEffect(.degrees(angle(for: value)))
    }

    private var tickLabels: some View {
        ZStack {
            ForEach(GaugeScale.majorTicks, id: \.self) { value in
                Text(GaugeScale.label(forTick: value))
                    // Proportional to the dial rather than to the text size setting, for
                    // the reason written on the RingGauge: these have to fit between the
                    // ticks of a circle of known diameter, and Dynamic Type would push
                    // them across it. The caption below the dial does scale, and the
                    // reading is available to VoiceOver.
                    .font(.system(size: size * 0.072, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    // Undo the placement rotation so the numbers stay upright.
                    .rotationEffect(.degrees(-angle(for: value)))
                    .offset(y: -labelRadius)
                    .rotationEffect(.degrees(angle(for: value)))
            }
        }
    }

    private var marker: some View {
        Capsule()
            .fill(Color.primary.opacity(0.85))
            .frame(width: size * 0.014, height: arcWidth + size * 0.030)
            .offset(y: -arcRadius)
            .rotationEffect(.degrees(zeroAngle + sweep * fraction))
            .animation(.easeOut(duration: 0.25), value: fraction)
    }

    private var readout: some View {
        VStack(spacing: 0) {
            Text(reading)
                .font(.system(size: size * 0.200, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("Mbit/s")
                .font(.system(size: size * 0.082, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        // The needle never enters the bottom ninety degrees, which is where the two
        // stops leave the dial open, so the readout can sit slightly low without ever
        // being crossed.
        .offset(y: size * 0.045)
    }
}

// MARK: - Sparkline

struct Sparkline: View {
    var data: [Double]              // 60 points, roughly two minutes
    var longData: [Double] = []     // 1800 points, roughly an hour
    /// What the numbers mean. Without it the view normalised on whatever maximum
    /// happened to be in its own data, so an idle CPU and a saturated one drew the
    /// same picture, and three callers fed it percentages, ratios and a state code
    /// with no way to tell them apart.
    var scale: SparklineScale
    var colour: Color
    var height: CGFloat = 38
    var showTrend: Bool = true
    /// Spoken by VoiceOver in place of the shape.
    var accessibilityDescription: String

    /// Downsamples longData by averaging each bucket.
    ///
    /// Replaces a per-render moving average that recomputed four windows of
    /// 1800/450/150/30 points from inside `body` - roughly 146,000 additions per
    /// sparkline per render, on the main thread, memoised nowhere. One bucket-averaged
    /// pass gives a trend line of the same shape at a fraction of the cost; it replaces
    /// the four moving averages rather than reproducing them.
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

    private func makePath(_ points: [Double], in geo: GeometryProxy, ceiling: Double, closed: Bool) -> Path {
        var path = Path()
        guard points.count > 1, ceiling > 0 else { return path }
        let w = geo.size.width, h = geo.size.height
        let step = w / CGFloat(points.count - 1)
        if closed { path.move(to: CGPoint(x: 0, y: h)) }
        for (i, value) in points.enumerated() {
            let x = CGFloat(i) * step
            let y = h - (CGFloat(min(value / ceiling, 1)) * h * 0.9)
            if i == 0 && !closed { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        if closed {
            path.addLine(to: CGPoint(x: w, y: h))
            path.closeSubpath()
        }
        return path
    }

    var body: some View {
        GeometryReader { geo in
            let ceiling = scale.upperBound(for: showTrend && !longData.isEmpty ? longData : data)
            let trend = showTrend && longData.count > 30 ? downsampled(longData, into: 60) : []

            ZStack {
                // Live fill, behind everything else
                makePath(data, in: geo, ceiling: ceiling, closed: true)
                    .fill(LinearGradient(colors: [colour.opacity(0.18), colour.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))

                if !trend.isEmpty {
                    makePath(trend, in: geo, ceiling: ceiling, closed: false)
                        .stroke(colour.opacity(0.35),
                                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                }

                // Live curve - the most visible one
                makePath(data, in: geo, ceiling: ceiling, closed: false)
                    .stroke(colour, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue(currentReading)
    }

    private var currentReading: String {
        guard let latest = data.last else { return "no data" }
        switch scale {
        case .percent: return Format.percent(latest)
        case .ratio: return Format.percent(ratio: latest)
        case .relative: return Format.decimal(latest)
        }
    }
}

struct SparklineLegend: View {
    var colour: Color

    var body: some View {
        HStack(spacing: 12) {
            LegendItem(colour: colour, opacity: 1.0, width: 1.8, label: "Live, 2 min")
            LegendItem(colour: colour, opacity: 0.35, width: 1.2, label: "Trend, 1 h")
        }
        // The legend explains the drawing; VoiceOver gets the reading instead.
        .accessibilityHidden(true)
    }
}

struct LegendItem: View {
    var colour: Color
    var opacity: Double
    var width: CGFloat
    var label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(colour.opacity(opacity))
                .frame(width: 12, height: width)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Stat card

struct StatCard<Content: View>: View {
    var title: String
    var icon: String
    var iconColour: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(iconColour)
                    .font(.caption.weight(.medium))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .accessibilityAddTraits(.isHeader)

            content()
        }
        .padding(14)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Metric row

struct MetricRow: View {
    var label: String
    var value: String
    var colour: Color = .primary

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundColor(colour)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Progress bar

struct ProgressBar: View {
    var value: Double
    var status: Status
    var height: CGFloat = 6
    /// Spoken by VoiceOver. A bare bar says nothing to it.
    var accessibilityDescription: String

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(status.colour.opacity(0.12))
                    .frame(height: height)
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(status.colour)
                    .frame(width: geo.size.width * min(max(value, 0), 1), height: height)
                    .animation(.easeInOut(duration: 0.4), value: value)
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue("\(Format.percent(ratio: value)), \(status.label)")
    }
}

// MARK: - Status indicator

/// Carries a shape as well as a colour.
///
/// The previous version was a bare coloured circle, which tells a colour-blind reader
/// nothing and tells VoiceOver nothing at all.
struct StatusDot: View {
    var status: Status
    var accessibilityDescription: String

    var body: some View {
        Image(systemName: status.symbol)
            .font(.caption)
            .foregroundColor(status.colour)
            .accessibilityLabel(accessibilityDescription)
            .accessibilityValue(status.label)
    }
}
