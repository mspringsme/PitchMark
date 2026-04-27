import SwiftUI

struct StrikeZoneHeatmapView: View {
    let events: [PitchEvent]
    var interactionHint: String? = nil
    var onLocationTap: ((String, Bool) -> Void)? = nil

    private enum Slot: Hashable {
        case inner(row: Int, col: Int)
        case outer(index: Int)
    }

    private struct MissLine: Identifiable {
        let id: String
        let from: CGPoint
        let to: CGPoint
    }

    private struct Marker: Identifiable {
        enum Kind {
            case redCalled
            case resultLabel
        }

        let id: String
        let kind: Kind
        let point: CGPoint
        let label: String?
        let matched: Bool
    }

    private func parseSlot(for rawLocation: String, preferStrike: Bool? = nil) -> Slot? {
        let trimmed = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix: String? = {
            if trimmed.hasPrefix("Strike ") { return "strike" }
            if trimmed.hasPrefix("Ball ") { return "ball" }
            return nil
        }()
        let resolvedPrefix: String? = {
            if let prefix { return prefix }
            if let preferStrike { return preferStrike ? "strike" : "ball" }
            return nil
        }()

        var zone = trimmed
        if trimmed.hasPrefix("Strike ") {
            zone = String(trimmed.dropFirst("Strike ".count))
        } else if trimmed.hasPrefix("Ball ") {
            zone = String(trimmed.dropFirst("Ball ".count))
        }

        let normalized = zone
            .lowercased()
            .replacingOccurrences(of: "—", with: " ")
            .replacingOccurrences(of: "–", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if resolvedPrefix == "ball" {
            if normalized.contains("up") && normalized.contains("out") { return .outer(index: 0) }
            if normalized == "up" || normalized == "high" { return .outer(index: 1) }
            if normalized.contains("up") && normalized.contains("in") { return .outer(index: 2) }
            if normalized == "out" { return .outer(index: 3) }
            if normalized == "in" { return .outer(index: 4) }
            if (normalized.contains("↓") || normalized.contains("down") || normalized.contains("low")) && normalized.contains("out") { return .outer(index: 5) }
            if normalized == "↓" || normalized == "down" || normalized == "low" { return .outer(index: 6) }
            if (normalized.contains("↓") || normalized.contains("down") || normalized.contains("low")) && normalized.contains("in") { return .outer(index: 7) }
        }

        if resolvedPrefix == "strike" {
            if normalized.contains("up") && normalized.contains("out") { return .inner(row: 0, col: 0) }
            if normalized == "up" || normalized == "high" { return .inner(row: 0, col: 1) }
            if normalized.contains("up") && normalized.contains("in") { return .inner(row: 0, col: 2) }
            if normalized == "out" { return .inner(row: 1, col: 0) }
            if normalized == "middle" { return .inner(row: 1, col: 1) }
            if normalized == "in" { return .inner(row: 1, col: 2) }
            if (normalized.contains("↓") || normalized.contains("down") || normalized.contains("low")) && normalized.contains("out") { return .inner(row: 2, col: 0) }
            if normalized == "↓" || normalized == "down" || normalized == "low" { return .inner(row: 2, col: 1) }
            if (normalized.contains("↓") || normalized.contains("down") || normalized.contains("low")) && normalized.contains("in") { return .inner(row: 2, col: 2) }
        }

        let row: Int? = {
            if normalized.contains("up") || normalized.contains("high") { return 0 }
            if normalized.contains("↓") || normalized.contains("low") || normalized.contains("down") { return 2 }
            if normalized.contains("middle") { return 1 }
            if normalized.contains("in") || normalized.contains("out") { return 1 }
            return nil
        }()

        let col: Int? = {
            if normalized.contains("out") { return 0 }
            if normalized.contains("middle") { return 1 }
            if normalized.contains("in") { return 2 }
            if normalized.contains("up") || normalized.contains("high") || normalized.contains("↓") || normalized.contains("low") || normalized.contains("down") {
                return 1
            }
            return nil
        }()

        guard let row, let col else { return nil }
        return .inner(row: row, col: col)
    }

    private func basePoint(for slot: Slot, originX: CGFloat, originY: CGFloat, zoneWidth: CGFloat, zoneHeight: CGFloat, slotSize: CGFloat) -> CGPoint {
        let cellW = zoneWidth / 3.0
        let cellH = zoneHeight / 3.0

        switch slot {
        case let .inner(row, col):
            return CGPoint(
                x: originX + CGFloat(col) * cellW + cellW / 2.0,
                y: originY + CGFloat(row) * cellH + cellH / 2.0
            )
        case let .outer(index):
            let points: [CGPoint] = [
                CGPoint(x: originX - slotSize * 0.58, y: originY - slotSize * 0.58),
                CGPoint(x: originX + zoneWidth / 2.0, y: originY - slotSize * 0.72),
                CGPoint(x: originX + zoneWidth + slotSize * 0.58, y: originY - slotSize * 0.58),
                CGPoint(x: originX - slotSize * 0.72, y: originY + zoneHeight / 2.0),
                CGPoint(x: originX + zoneWidth + slotSize * 0.72, y: originY + zoneHeight / 2.0),
                CGPoint(x: originX - slotSize * 0.58, y: originY + zoneHeight + slotSize * 0.58),
                CGPoint(x: originX + zoneWidth / 2.0, y: originY + zoneHeight + slotSize * 0.72),
                CGPoint(x: originX + zoneWidth + slotSize * 0.58, y: originY + zoneHeight + slotSize * 0.58)
            ]
            return points.indices.contains(index) ? points[index] : CGPoint(x: originX, y: originY)
        }
    }

    private func layoutForAllEvents(originX: CGFloat, originY: CGFloat, zoneWidth: CGFloat, zoneHeight: CGFloat, slotSize: CGFloat) -> (markers: [Marker], lines: [MissLine]) {
        var markers: [Marker] = []
        var lines: [MissLine] = []

        // Per-slot placement index so markers don't overlap.
        var nextOffsetIndex: [Slot: Int] = [:]
        let innerRadius = slotSize * 0.36
        let outerRadius = slotSize * 0.60
        let offsets: [CGSize] = [.zero] + (0..<8).map { i in
            let a = CGFloat(i) * (.pi / 4.0)
            return CGSize(width: cos(a) * innerRadius, height: sin(a) * innerRadius)
        } + (0..<12).map { i in
            let a = CGFloat(i) * (2.0 * .pi / 12.0)
            return CGSize(width: cos(a) * outerRadius, height: sin(a) * outerRadius)
        }

        func placedPoint(for slot: Slot) -> CGPoint {
            let base = basePoint(for: slot, originX: originX, originY: originY, zoneWidth: zoneWidth, zoneHeight: zoneHeight, slotSize: slotSize)
            let idx = nextOffsetIndex[slot, default: 0]
            nextOffsetIndex[slot] = idx + 1
            let offset = offsets[idx % offsets.count]
            return CGPoint(x: base.x + offset.width, y: base.y + offset.height)
        }

        for event in events {
            let eventId = event.identity
            guard let calledSlot = parseSlot(
                for: event.calledPitch?.location ?? "",
                preferStrike: event.calledPitch?.isStrike
            ) else { continue }
            guard let resultSlot = parseSlot(for: event.location) else { continue }
            let label = designation(for: event, resultSlot: resultSlot)

            if calledSlot == resultSlot {
                markers.append(
                    Marker(
                        id: "\(eventId)-result",
                        kind: .resultLabel,
                        point: placedPoint(for: resultSlot),
                        label: label,
                        matched: true
                    )
                )
            } else {
                let calledPoint = placedPoint(for: calledSlot)
                let resultPoint = placedPoint(for: resultSlot)
                lines.append(MissLine(id: "\(eventId)-line", from: calledPoint, to: resultPoint))
                markers.append(Marker(id: "\(eventId)-called", kind: .redCalled, point: calledPoint, label: nil, matched: false))
                markers.append(
                    Marker(
                        id: "\(eventId)-result",
                        kind: .resultLabel,
                        point: resultPoint,
                        label: label,
                        matched: false
                    )
                )
            }
        }

        return (markers, lines)
    }

    private func designation(for event: PitchEvent, resultSlot: Slot) -> String {
        let outcome = (event.outcome ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let descriptorTokens: Set<String> = Set(
            (event.descriptor ?? "")
                .lowercased()
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
        let resultInStrikeZone: Bool = {
            if case .inner = resultSlot { return true }
            return false
        }()
        // Explicit user designations only (not inferred from tap location).
        let designatedAsBall =
            (event.isBall ?? false) ||
            outcome == "ball" ||
            outcome == "bb" ||
            outcome == "walk"
        let calledIsStrike = event.calledPitch?.isStrike ?? false
        let designatedAsStrike =
            event.strikeSwinging ||
            event.strikeLooking ||
            outcome == "foul" ||
            outcome == "k" ||
            outcome == "ꓘ" ||
            outcome == "strikeout"

        // Mismatch markers should win over strike-style labels when designation
        // contradicts where the result was tapped.
        if resultInStrikeZone && designatedAsBall { return "B?" }
        if !resultInStrikeZone && designatedAsStrike && calledIsStrike { return "S?" }

        if event.strikeSwinging { return "SS" }
        if event.strikeLooking { return "SL" }
        if outcome == "foul" || descriptorTokens.contains("foul") { return "F" }
        if event.wildPitch { return "WP" }
        if event.passedBall { return "PB" }
        if outcome == "hbp" || descriptorTokens.contains("hit batter") || descriptorTokens.contains("hbp") {
            return "HB"
        }
        if outcome == "1b" { return "H1B" }
        if outcome == "2b" { return "H2B" }
        if outcome == "3b" { return "H3B" }
        if outcome == "hr" { return "HHR" }
        if outcome == "hit" || descriptorTokens.contains("hit") { return "H" }
        return resultInStrikeZone ? "S" : "B"
    }

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let zoneWidth = w * 0.54
                let zoneHeight = h * 0.74
                let cellW = zoneWidth / 3.0
                let cellH = zoneHeight / 3.0
                let slotSize = min(cellW, cellH) * 1.01
                let originX = (w - zoneWidth) / 2.0
                let backgroundTop: CGFloat = 0
                let backgroundHeight = h
                let zoneOriginY = backgroundTop + slotSize * 0.95
                let layout = layoutForAllEvents(
                    originX: originX,
                    originY: zoneOriginY,
                    zoneWidth: zoneWidth,
                    zoneHeight: zoneHeight,
                    slotSize: slotSize
                )

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .stroke(Color.black, lineWidth: 2)
                        .frame(width: zoneWidth, height: zoneHeight)
                        .position(x: originX + zoneWidth / 2.0, y: zoneOriginY + zoneHeight / 2.0)
                        .allowsHitTesting(false)

                    ForEach(0..<3, id: \.self) { row in
                        ForEach(0..<3, id: \.self) { col in
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.12))
                                Circle()
                                    .stroke(Color.green, lineWidth: 3.8)
                                Circle()
                                    .stroke(Color.black.opacity(0.55), lineWidth: 1.2)
                            }
                            .shadow(color: Color.black.opacity(0.24), radius: 6, x: 0, y: 3)
                            .shadow(color: Color.black.opacity(0.14), radius: 2, x: 0, y: 1)
                            .frame(width: slotSize, height: slotSize)
                            .position(
                                x: originX + CGFloat(col) * cellW + cellW / 2.0,
                                y: zoneOriginY + CGFloat(row) * cellH + cellH / 2.0
                            )
                            .allowsHitTesting(false)
                        }
                    }

                    let outerPoints: [CGPoint] = [
                        CGPoint(x: originX - slotSize * 0.58, y: zoneOriginY - slotSize * 0.58),
                        CGPoint(x: originX + zoneWidth / 2.0, y: zoneOriginY - slotSize * 0.72),
                        CGPoint(x: originX + zoneWidth + slotSize * 0.58, y: zoneOriginY - slotSize * 0.58),
                        CGPoint(x: originX - slotSize * 0.72, y: zoneOriginY + zoneHeight / 2.0),
                        CGPoint(x: originX + zoneWidth + slotSize * 0.72, y: zoneOriginY + zoneHeight / 2.0),
                        CGPoint(x: originX - slotSize * 0.58, y: zoneOriginY + zoneHeight + slotSize * 0.58),
                        CGPoint(x: originX + zoneWidth / 2.0, y: zoneOriginY + zoneHeight + slotSize * 0.72),
                        CGPoint(x: originX + zoneWidth + slotSize * 0.58, y: zoneOriginY + zoneHeight + slotSize * 0.58)
                    ]

                    ForEach(Array(outerPoints.enumerated()), id: \.offset) { _, p in
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.10))
                            Circle()
                                .stroke(Color.red, lineWidth: 3.8)
                            Circle()
                                .stroke(Color.black.opacity(0.55), lineWidth: 1.2)
                        }
                        .shadow(color: Color.black.opacity(0.24), radius: 6, x: 0, y: 3)
                        .shadow(color: Color.black.opacity(0.14), radius: 2, x: 0, y: 1)
                        .frame(width: slotSize * 0.96, height: slotSize * 0.96)
                        .position(x: p.x, y: p.y)
                        .allowsHitTesting(false)
                    }

                    ForEach(layout.lines) { line in
                        ZStack {
                            let dx = line.to.x - line.from.x
                            let dy = line.to.y - line.from.y
                            let length = max(sqrt(dx * dx + dy * dy), 0.001)
                            let ux = dx / length
                            let uy = dy / length

                            // Keep arrow visible by ending slightly before the result label center.
                            let labelInset: CGFloat = 10
                            let tip = CGPoint(
                                x: line.to.x - ux * labelInset,
                                y: line.to.y - uy * labelInset
                            )

                            Path { path in
                                path.move(to: line.from)
                                path.addLine(to: tip)
                            }
                            .stroke(Color.red.opacity(0.85), lineWidth: 0.5)

                            // Arrowhead at the result endpoint.
                            let arrowLength: CGFloat = 7
                            let arrowHalfWidth: CGFloat = 3.5
                            let baseX = tip.x - ux * arrowLength
                            let baseY = tip.y - uy * arrowLength
                            let px = -uy
                            let py = ux
                            let left = CGPoint(x: baseX + px * arrowHalfWidth, y: baseY + py * arrowHalfWidth)
                            let right = CGPoint(x: baseX - px * arrowHalfWidth, y: baseY - py * arrowHalfWidth)

                            Path { path in
                                path.move(to: tip)
                                path.addLine(to: left)
                                path.addLine(to: right)
                                path.closeSubpath()
                            }
                            .fill(Color.red.opacity(0.9))
                        }
                        .allowsHitTesting(false)
                    }

                    ForEach(layout.markers) { marker in
                        switch marker.kind {
                        case .redCalled:
                            Image("redBlurCircle")
                                .position(marker.point)
                                .allowsHitTesting(false)
                        case .resultLabel:
                            Text(marker.label ?? "")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(
                                            marker.matched
                                            ? Color(red: 0.88, green: 0.96, blue: 0.89)
                                            : Color(.systemBackground)
                                        )
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(marker.matched ? Color.green.opacity(0.55) : Color.red.opacity(0.5), lineWidth: 1)
                                )
                                .position(marker.point)
                                .zIndex(20)
                                .allowsHitTesting(false)
                        }
                    }

                    // Keep tap targets as the top-most layer so they remain responsive.
                    let strikeLabels: [[String]] = [
                        ["Up & Out", "Up", "Up & In"],
                        ["Out", "Middle", "In"],
                        ["↓ & Out", "↓", "↓ & In"]
                    ]
                    ForEach(0..<3, id: \.self) { row in
                        ForEach(0..<3, id: \.self) { col in
                            Button {
                                onLocationTap?(strikeLabels[row][col], true)
                            } label: {
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: slotSize * 1.12, height: slotSize * 1.12)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .position(
                                x: originX + CGFloat(col) * cellW + cellW / 2.0,
                                y: zoneOriginY + CGFloat(row) * cellH + cellH / 2.0
                            )
                        }
                    }

                    let ballLabels: [String] = ["Up & Out", "Up", "Up & In", "Out", "In", "↓ & Out", "↓", "↓ & In"]
                    ForEach(Array(outerPoints.enumerated()), id: \.offset) { idx, p in
                        Button {
                            guard ballLabels.indices.contains(idx) else { return }
                            onLocationTap?(ballLabels[idx], false)
                        } label: {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: slotSize * 1.12, height: slotSize * 1.12)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .position(x: p.x, y: p.y)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxWidth: .infinity, alignment: .center)
            .aspectRatio(0.96, contentMode: .fit)
            .layoutPriority(1)

            VStack(alignment: .leading, spacing: 2) {
                Text(interactionHint ?? " ")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .opacity((interactionHint ?? "").isEmpty ? 0 : 1)
                    .padding(.bottom, 2)
                    .padding(.top, -4)
                    .frame(height: 16)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 18) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("SS = Swinging Strike")
                                Text("SL = Looking Strike")
                                Text("F = Foul")
                                Text("B? = Tapped strike zone, designated Ball")
                                Text("S? = Tapped ball zone, designated Strike")
                                Text("----- = not available")
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("WP = Wild Pitch")
                                Text("PB = Passed Ball")
                                Text("HB = Hit Batter")
                                Text("H1B = Hit Single")
                                Text("H2B = Hit Double")
                                Text("H3B = Hit Triple")
                                Text("HHR = Hit Home Run")
                                Text("H = Hit")
                            }
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.visible)
                .overlay(alignment: .trailing) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 3, height: 34)
                        .padding(.trailing, 1)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 96)
            .padding(.top, 72)
            .padding(.horizontal, 6)
        }
        .transaction { t in t.animation = nil }
    }
}
