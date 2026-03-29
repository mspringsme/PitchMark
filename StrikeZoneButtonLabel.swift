import SwiftUI

struct PieChartView: View {
    let segments: [Color]

    var body: some View {
        if segments.isEmpty {
            Color.clear
        } else {
            GeometryReader { geo in
                let radius = min(geo.size.width, geo.size.height) / 2
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let sliceCount = segments.count
                let anglePerSlice = 2 * .pi / Double(sliceCount)

                ZStack {
                    ForEach(segments.indices, id: \.self) { index in
                        let startAngle = anglePerSlice * Double(index) - .pi / 2
                        let endAngle = startAngle + anglePerSlice

                        Path { path in
                            path.move(to: center)
                            path.addArc(center: center,
                                        radius: radius,
                                        startAngle: Angle(radians: startAngle),
                                        endAngle: Angle(radians: endAngle),
                                        clockwise: false)
                            path.closeSubpath()
                        }
                        .fill(segments[index])
                    }
                }
            }
        }
    }
}

struct StrikeZoneButtonLabel: View {
    let isStrike: Bool
    let isSelected: Bool
    let fullLabel: String
    let segmentColors: [Color]
    let buttonSize: CGFloat
    let isRecordingResult: Bool
    let actualLocationRecorded: String?
    let calledPitchLocation: String?
    let pendingResultLabel: String?
    let outlineOnly: Bool

    var body: some View {
        let isResultSelected = pendingResultLabel == fullLabel
        let isFaded = isRecordingResult && !isResultSelected
        let isCalledPitch = calledPitchLocation?.trimmingCharacters(in: .whitespacesAndNewlines) == fullLabel
        let overrideFill: Color? = isCalledPitch ? (segmentColors.first ?? .gray) : nil

        return ZStack {
            GlowingShapeView(isStrike: isStrike, isSelected: isSelected, overrideFill: overrideFill, outlineOnly: outlineOnly)

            if !outlineOnly && !segmentColors.isEmpty {
                PieChartView(segments: segmentColors)
                    .frame(width: buttonSize, height: buttonSize)
                    .opacity(1)
                    .animation(.easeInOut(duration: 0.2), value: segmentColors)
            }

            Text(fullLabel)
                .font(.system(size: buttonSize * 0.24, weight: .semibold))
                .foregroundColor(outlineOnly ? Color.primary.opacity(0.7) : .white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .padding(4)
        }
        .frame(width: buttonSize, height: buttonSize)
        .contentShape(Rectangle())
        .opacity(isFaded ? 0.4 : 1)
        .compositingGroup()
    }
}

struct PitchImageGridPreview: View {
    let locations = [
        "Middle", "High", "Low",
        "Up & In", "Up & Out",
        "↓ & In", "↓ & Out",
        "In", "Out", "Up"
    ]

    struct Combo: Identifiable {
        let id = UUID()
        let location: String
        let isStrike: Bool
        let side: BatterSide
    }

    func allCombinations() -> [Combo] {
        let sides: [BatterSide] = [.right, .left]
        let strikeStates: [Bool] = [true, false]

        return sides.flatMap { side in
            strikeStates.flatMap { isStrike in
                locations.map { location in
                    Combo(location: location, isStrike: isStrike, side: side)
                }
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(120), spacing: 16), count: 3), spacing: 24) {
                ForEach(allCombinations()) { combo in
                    let imageName = PitchImageDictionary.imageName(
                        for: combo.location,
                        isStrike: combo.isStrike,
                        batterSide: combo.side
                    )

                    let isMissing = imageName == "Bat"

                    VStack(spacing: 8) {
                        Text(imageName)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .frame(width: 100)
                        Image(imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 100)
                            .border(isMissing ? Color.red : Color.gray.opacity(0.3), width: 2)
                        Text("\(combo.isStrike ? "Strike" : "Ball") \(combo.location)\n[\(combo.side.rawValue)]")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
