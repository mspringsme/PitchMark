import SwiftUI

struct StrikeZoneHeatmapView: View {
    let summary: HeatmapSummary

    private func strikeCellColor(count: Int) -> Color {
        guard summary.maxCount > 0, count > 0 else {
            return Color.gray.opacity(0.18)
        }
        let t = Double(count) / Double(summary.maxCount)
        return Color.green.opacity(0.25 + (0.7 * t))
    }

    private func outerCellColor(count: Int) -> Color {
        guard summary.outerMaxCount > 0, count > 0 else {
            return Color.red.opacity(0.08)
        }
        let t = Double(count) / Double(summary.outerMaxCount)
        return Color.red.opacity(0.18 + (0.65 * t))
    }

    private func countForCell(row: Int, col: Int) -> Int {
        summary.cells.first(where: { $0.row == row && $0.col == col })?.count ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let zoneWidth = w * 0.52
                let zoneHeight = h * 0.64
                let cellW = zoneWidth / 3.0
                let cellH = zoneHeight / 3.0
                let circleSize = min(cellW, cellH) * 0.72
                let originX = (w - zoneWidth) / 2.0
                let originY = h * 0.16

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .stroke(Color.black, lineWidth: 2)
                        .frame(width: zoneWidth, height: zoneHeight)
                        .position(x: originX + zoneWidth / 2.0, y: originY + zoneHeight / 2.0)

                    ForEach(0..<3, id: \.self) { row in
                        ForEach(0..<3, id: \.self) { col in
                            let count = countForCell(row: row, col: col)
                            let x = originX + CGFloat(col) * cellW + cellW / 2.0
                            let y = originY + CGFloat(row) * cellH + cellH / 2.0

                            ZStack {
                                Circle()
                                    .fill(strikeCellColor(count: count))
                                Circle()
                                    .stroke(Color.black.opacity(0.45), lineWidth: 1.4)
                                Text("\(count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(count > 0 ? Color.primary : Color.secondary)
                            }
                            .frame(width: circleSize, height: circleSize)
                            .position(x: x, y: y)
                        }
                    }

                    // Decorative outside-zone circles to mirror StrikeZoneView visuals.
                    let outerPoints: [(CGFloat, CGFloat)] = [
                        (originX - circleSize * 0.55, originY - circleSize * 0.55),
                        (originX + zoneWidth / 2.0, originY - circleSize * 0.72),
                        (originX + zoneWidth + circleSize * 0.55, originY - circleSize * 0.55),
                        (originX - circleSize * 0.72, originY + zoneHeight / 2.0),
                        (originX + zoneWidth + circleSize * 0.72, originY + zoneHeight / 2.0),
                        (originX - circleSize * 0.55, originY + zoneHeight + circleSize * 0.55),
                        (originX + zoneWidth / 2.0, originY + zoneHeight + circleSize * 0.72),
                        (originX + zoneWidth + circleSize * 0.55, originY + zoneHeight + circleSize * 0.55)
                    ]

                    ForEach(Array(outerPoints.enumerated()), id: \.offset) { idx, p in
                        let count = summary.outerCounts.indices.contains(idx) ? summary.outerCounts[idx] : 0
                        ZStack {
                            Circle()
                                .fill(outerCellColor(count: count))
                            Circle()
                                .stroke(Color.red.opacity(0.65), lineWidth: 2)
                            Text("\(count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(count > 0 ? Color.primary : Color.secondary)
                        }
                        .frame(width: circleSize * 0.95, height: circleSize * 0.95)
                        .position(x: p.0, y: p.1)
                    }
                }
            }
            .frame(height: 260)

            HStack(spacing: 8) {
                Text("Less")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LinearGradient(
                    colors: [Color.green.opacity(0.18), Color.green.opacity(0.95)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 8)
                .clipShape(Capsule())
                Text("More")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Sample: \(summary.totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
