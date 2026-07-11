import SwiftUI

struct ArchivePageView: View {
    private let mockCount = 336
    private let startDate: Date = {
        var c = DateComponents()
        c.year = 2025; c.month = 1; c.day = 17
        return Calendar.current.date(from: c) ?? Date()
    }()

    private var daysSinceStart: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                constellationsCard
                heatmapCard
                echoesCard
                lettersCard
                Spacer(minLength: 60)
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
            .padding(.bottom, 24)
        }
        .background(Theme.sidebarBg)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("THE ARCHIVE")
                .font(.system(size: 11, weight: .semibold))
                .tracking(3)
                .foregroundColor(Theme.textMuted)
            Text("\(mockCount)")
                .font(.custom("Georgia", size: 48))
                .foregroundColor(Theme.textPrimary)
            Text("\(mockCount) Things Remembered")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Theme.textPrimary)
            Text("Since January 17, 2025 · \(daysSinceStart)天")
                .font(.system(size: 13))
                .foregroundColor(Theme.textMuted)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Cards

    private var constellationsCard: some View {
        ArchiveCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CONSTELLATIONS")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(2)
                            .foregroundColor(Theme.textMuted)
                        Text("Emotional Map")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textPrimary)
                    }
                    Spacer()
                    Text("View Full Sky →")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.accent)
                }
                ConstellationCanvas()
                    .frame(height: 280)
                constellationLegend
            }
        }
    }

    private var constellationLegend: some View {
        HStack(spacing: 16) {
            ForEach(ConstellationDot.legendItems, id: \.label) { item in
                HStack(spacing: 4) {
                    Circle()
                        .fill(item.color)
                        .frame(width: item.size, height: item.size)
                    Text(item.label)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textMuted)
                }
            }
        }
    }

    private var heatmapCard: some View {
        ArchiveCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HEATMAP")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(2)
                            .foregroundColor(Theme.textMuted)
                        Text("Timeline")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textPrimary)
                    }
                    Spacer()
                    Text("Last 90 Days · 127,439 Words")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textMuted)
                }
                HeatmapGrid()
            }
        }
    }

    private var echoesCard: some View {
        ArchiveCard {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ECHOES")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(2)
                        .foregroundColor(Theme.textMuted)
                    Text("Things We Keep Returning To")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textPrimary)
                }
                VStack(spacing: 8) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 28))
                        .foregroundColor(Theme.textMuted.opacity(0.3))
                    Text("Nothing has echoed yet.")
                        .font(.system(size: 15).italic())
                        .foregroundColor(Theme.textMuted)
                    Text("The archive is listening.")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textMuted)
                    Text("When something is remembered again and again, it will appear here.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textMuted.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .frame(minHeight: 180)
            }
        }
    }

    private var lettersCard: some View {
        ArchiveCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LETTERS")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(2)
                        .foregroundColor(Theme.textMuted)
                    Text("Written For Each Other")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textPrimary)
                }
                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.accent.opacity(0.3))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No letters yet.")
                            .font(.system(size: 15))
                            .foregroundColor(Theme.textPrimary)
                        Text("The first letter you write will be kept here, forever.")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textMuted)
                    }
                    Spacer()
                    Text("0 Letters →")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.accent)
                }
            }
        }
    }
}

// MARK: - ArchiveCard wrapper

private struct ArchiveCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(20)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Constellation Canvas

private struct ConstellationDot {
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let colorHex: UInt

    struct LegendItem {
        let label: String
        let color: Color
        let size: CGFloat
    }

    static let legendItems: [LegendItem] = [
        LegendItem(label: "Anchor", color: Color(hex: 0x4A6B7C), size: 8),
        LegendItem(label: "Recurring", color: Color(hex: 0x7B9DAD), size: 6),
        LegendItem(label: "Fleeting", color: Color(hex: 0xB5CDD8), size: 4)
    ]

    // Hardcoded mock dots: 4 large deep, 16 medium, 24 small light
    static let mockDots: [ConstellationDot] = [
        // Large deep (#4A6B7C) size 14-16
        ConstellationDot(x: 0.22, y: 0.31, size: 15, colorHex: 0x4A6B7C),
        ConstellationDot(x: 0.68, y: 0.58, size: 16, colorHex: 0x4A6B7C),
        ConstellationDot(x: 0.45, y: 0.72, size: 14, colorHex: 0x4A6B7C),
        ConstellationDot(x: 0.81, y: 0.25, size: 15, colorHex: 0x4A6B7C),

        // Medium (#7B9DAD) size 8-12
        ConstellationDot(x: 0.12, y: 0.55, size: 10, colorHex: 0x7B9DAD),
        ConstellationDot(x: 0.35, y: 0.18, size: 11, colorHex: 0x7B9DAD),
        ConstellationDot(x: 0.58, y: 0.35, size: 9, colorHex: 0x7B9DAD),
        ConstellationDot(x: 0.72, y: 0.78, size: 12, colorHex: 0x7B9DAD),
        ConstellationDot(x: 0.28, y: 0.65, size: 10, colorHex: 0x7B9DAD),
        ConstellationDot(x: 0.88, y: 0.48, size: 11, colorHex: 0x7B9DAD),
        ConstellationDot(x: 0.15, y: 0.82, size: 9, colorHex: 0x7B9DAD),
        ConstellationDot(x: 0.52, y: 0.52, size: 10, colorHex: 0x7B9DAD),
        ConstellationDot(x: 0.42, y: 0.88, size: 11, colorHex: 0x7B9DAD),
        ConstellationDot(x: 0.78, y: 0.12, size: 9, colorHex: 0x7B9DAD),
        ConstellationDot(x: 0.62, y: 0.92, size: 10, colorHex: 0x7B9DAD),
        ConstellationDot(x: 0.08, y: 0.28, size: 12, colorHex: 0x7B9DAD),
        ConstellationDot(x: 0.92, y: 0.68, size: 9, colorHex: 0x7B9DAD),
        ConstellationDot(x: 0.33, y: 0.42, size: 11, colorHex: 0x7B9DAD),
        ConstellationDot(x: 0.55, y: 0.15, size: 10, colorHex: 0x7B9DAD),
        ConstellationDot(x: 0.18, y: 0.38, size: 9, colorHex: 0x7B9DAD),

        // Small light (#B5CDD8) size 4-6
        ConstellationDot(x: 0.06, y: 0.72, size: 5, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.25, y: 0.08, size: 4, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.48, y: 0.62, size: 5, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.76, y: 0.42, size: 6, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.38, y: 0.78, size: 4, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.85, y: 0.88, size: 5, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.10, y: 0.45, size: 4, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.64, y: 0.22, size: 5, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.30, y: 0.55, size: 6, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.95, y: 0.35, size: 4, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.20, y: 0.92, size: 5, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.70, y: 0.05, size: 4, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.50, y: 0.82, size: 6, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.82, y: 0.62, size: 5, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.04, y: 0.15, size: 4, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.42, y: 0.25, size: 5, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.60, y: 0.68, size: 6, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.88, y: 0.08, size: 4, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.16, y: 0.62, size: 5, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.72, y: 0.95, size: 4, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.38, y: 0.35, size: 5, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.56, y: 0.48, size: 4, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.92, y: 0.18, size: 6, colorHex: 0xB5CDD8),
        ConstellationDot(x: 0.24, y: 0.75, size: 5, colorHex: 0xB5CDD8)
    ]
}

private struct ConstellationCanvas: View {
    private let axisLabels = [
        (text: "Sorrow", xFrac: CGFloat(0.5), yFrac: CGFloat(0.03), alignment: Alignment.top),
        (text: "Joy", xFrac: CGFloat(0.5), yFrac: CGFloat(0.97), alignment: Alignment.bottom),
        (text: "Longing", xFrac: CGFloat(0.02), yFrac: CGFloat(0.5), alignment: Alignment.leading),
        (text: "Devotion", xFrac: CGFloat(0.98), yFrac: CGFloat(0.5), alignment: Alignment.trailing)
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Canvas { ctx, size in
                    // Cross lines
                    let lineColor = GraphicsContext.Shading.color(.gray.opacity(0.1))
                    var hLine = Path()
                    hLine.move(to: CGPoint(x: 0, y: size.height / 2))
                    hLine.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    ctx.stroke(hLine, with: lineColor, lineWidth: 1)

                    var vLine = Path()
                    vLine.move(to: CGPoint(x: size.width / 2, y: 0))
                    vLine.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                    ctx.stroke(vLine, with: lineColor, lineWidth: 1)

                    // Dots
                    for dot in ConstellationDot.mockDots {
                        let cx = dot.x * size.width
                        let cy = dot.y * size.height
                        let r = dot.size / 2
                        let rect = CGRect(x: cx - r, y: cy - r, width: dot.size, height: dot.size)
                        var circle = Path()
                        circle.addEllipse(in: rect)
                        ctx.fill(circle, with: .color(Color(hexString: dot.colorHex)))
                    }
                }

                // Axis labels
                ForEach(0..<axisLabels.count, id: \.self) { i in
                    let label = axisLabels[i]
                    Text(label.text)
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.35))
                        .position(
                            x: label.xFrac * geo.size.width,
                            y: label.yFrac * geo.size.height
                        )
                }
            }
        }
    }
}

// MARK: - Heatmap Grid

private struct HeatmapGrid: View {
    private let rows = 7
    private let cols = 13
    private let cellSize: CGFloat = 12
    private let spacing: CGFloat = 3
    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    private let heatColors: [Color] = [
        Color(hex: 0xF0EBE3),
        Color(hex: 0xD9CEBE),
        Color(hex: 0xC2B09B),
        Color(hex: 0xA89278),
        Color(hex: 0x8B7355)
    ]

    private var mockIntensities: [[Int]] {
        // 7 rows × 13 cols; right cols (recent) slightly denser
        var grid = [[Int]]()
        for row in 0..<rows {
            var rowData = [Int]()
            for col in 0..<cols {
                let base = (col * 5) / cols  // 0-4 bias toward right
                let seed = (row * 13 + col * 7 + row + col) % 7
                let raw = max(0, min(4, base + (seed < 3 ? seed : seed - 4)))
                rowData.append(raw)
            }
            grid.append(rowData)
        }
        return grid
    }

    private var monthLabels: [String] {
        let cal = Calendar.current
        let now = Date()
        return (-2...0).map { offset in
            let date = cal.date(byAdding: .month, value: offset, to: now) ?? now
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM"
            return formatter.string(from: date)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let intensities = mockIntensities
            HStack(alignment: .top, spacing: spacing) {
                // Day labels column
                VStack(spacing: spacing) {
                    ForEach(0..<rows, id: \.self) { i in
                        Text(dayLabels[i])
                            .font(.system(size: 9))
                            .foregroundColor(Theme.textMuted)
                            .frame(width: 12, height: cellSize)
                    }
                }
                // Grid
                HStack(spacing: spacing) {
                    ForEach(0..<cols, id: \.self) { col in
                        VStack(spacing: spacing) {
                            ForEach(0..<rows, id: \.self) { row in
                                let intensity = intensities[row][col]
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(heatColors[intensity])
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
            }
            // Month labels
            HStack(spacing: 0) {
                Spacer().frame(width: 12 + spacing) // offset for day labels
                ForEach(0..<3, id: \.self) { i in
                    Text(monthLabels[i])
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textMuted)
                    if i < 2 {
                        Spacer()
                    }
                }
            }
        }
    }
}
