//
//  FieldPositionsView.swift
//  PitchMark
//
//  The gear sheet's field view (2026-11-03): a square diamond with a spot
//  per position. Tapping a spot picks which of the team's in-game players
//  stands there - another way to set the same positions the rows' Pos
//  buttons set (LineupFieldPositions), so the two always agree.
//

import SwiftUI

struct FieldPositionsTarget: Identifiable {
    let id: String
    let title: String
    let cells: [JerseyCell]
}

struct FieldPositionsView: View {
    let title: String
    let cells: [JerseyCell]
    let positions: [UUID: String]
    var nameById: [UUID: String] = [:]
    /// The whole new map. nil = read-only.
    let onChange: (([UUID: String]) -> Void)?

    @Environment(\.dismiss) private var dismiss

    /// Spot centres as fractions of the square, home plate at the bottom,
    /// placed on `FieldImage2`'s diamond (see `FieldBackground`). DH sits
    /// off the field in the bottom-left corner.
    static let spots: [String: CGPoint] = [
        "C": CGPoint(x: 0.50, y: 0.87),
        "P": CGPoint(x: 0.50, y: 0.71),
        "1B": CGPoint(x: 0.73, y: 0.63),
        "2B": CGPoint(x: 0.62, y: 0.49),
        "SS": CGPoint(x: 0.38, y: 0.49),
        "3B": CGPoint(x: 0.27, y: 0.63),
        "LF": CGPoint(x: 0.20, y: 0.31),
        "CF": CGPoint(x: 0.50, y: 0.18),
        "RF": CGPoint(x: 0.80, y: 0.31),
        "DH": CGPoint(x: 0.10, y: 0.87)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    ZStack {
                        FieldBackground()
                        ForEach(LineupFieldPositions.choices, id: \.self) { position in
                            if let point = Self.spots[position] {
                                spot(position)
                                    .position(x: point.x * side, y: point.y * side)
                            }
                        }
                    }
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity)
                }
                .aspectRatio(1, contentMode: .fit)

                Text(onChange == nil
                     ? "Positions for this game."
                     : "Tap a position to place a player there.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if !unplaced.isEmpty {
                    Text("Not placed: " + unplaced.map { $0.jerseyNumber }.joined(separator: ", "))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var unplaced: [JerseyCell] {
        cells.filter { positions[$0.id] == nil }
    }

    private func occupant(of position: String) -> JerseyCell? {
        cells.first { positions[$0.id] == position }
    }

    @ViewBuilder
    private func spot(_ position: String) -> some View {
        let player = occupant(of: position)
        let label = VStack(spacing: 2) {
            Text(player?.jerseyNumber ?? "–")
                .font(.headline.weight(.bold))
                .foregroundStyle(player == nil ? Color.secondary : Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 44, height: 44)
                .background(Circle().fill(player == nil ? Color(.systemBackground).opacity(0.85) : Color.pitchMarkActiveGray))
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
            Text(position)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.black.opacity(0.45)))
        }
        if let onChange {
            Menu {
                ForEach(cells) { cell in
                    Button {
                        onChange(LineupFieldPositions.assign(
                            position, to: cell.id, in: positions, teamCellIds: Set(cells.map { $0.id })
                        ))
                    } label: {
                        let name = nameById[cell.id].map { " \($0)" } ?? ""
                        if player?.id == cell.id {
                            Label("#\(cell.jerseyNumber)\(name)", systemImage: "checkmark")
                        } else {
                            Text("#\(cell.jerseyNumber)\(name)")
                        }
                    }
                }
                if let player {
                    Divider()
                    Button("Clear \(position)", role: .destructive) {
                        onChange(LineupFieldPositions.assign(
                            nil, to: player.id, in: positions, teamCellIds: Set(cells.map { $0.id })
                        ))
                    }
                }
            } label: {
                label
            }
            .accessibilityLabel("\(position): \(player.map { "number \($0.jerseyNumber)" } ?? "empty")")
        } else {
            label
                .accessibilityLabel("\(position): \(player.map { "number \($0.jerseyNumber)" } ?? "empty")")
        }
    }
}

/// The same field picture the hit-location screen uses (`FieldImage2`,
/// 596x842), cropped to the square around the field. The Display app has
/// no copy of the picture, so it falls back to the drawn diagram.
private struct FieldBackground: View {
    /// The field's square inside the picture, in its pixels.
    private static let crop = CGRect(x: 65.5, y: 159, width: 464, height: 464)
    private static let imageSize = CGSize(width: 596, height: 842)

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let k = side / Self.crop.width
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                if let image = UIImage(named: "FieldImage2") {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: Self.imageSize.width * k, height: Self.imageSize.height * k)
                        .offset(x: -Self.crop.minX * k, y: -Self.crop.minY * k)
                } else {
                    FieldDiagram()
                }
            }
            .frame(width: side, height: side, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .allowsHitTesting(false)
    }
}

/// Grass, the dirt infield and the bases, drawn to fit a square.
private struct FieldDiagram: View {
    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            let home = CGPoint(x: 0.50 * s, y: 0.85 * s)
            let first = CGPoint(x: 0.68 * s, y: 0.67 * s)
            let second = CGPoint(x: 0.50 * s, y: 0.49 * s)
            let third = CGPoint(x: 0.32 * s, y: 0.67 * s)
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.36, green: 0.62, blue: 0.33))
                // Fair territory: the foul lines out to an outfield arc.
                Path { path in
                    path.move(to: home)
                    path.addLine(to: CGPoint(x: 0.02 * s, y: 0.37 * s))
                    path.addQuadCurve(
                        to: CGPoint(x: 0.98 * s, y: 0.37 * s),
                        control: CGPoint(x: 0.50 * s, y: -0.12 * s)
                    )
                    path.closeSubpath()
                }
                .fill(Color(red: 0.42, green: 0.70, blue: 0.38))
                Path { path in
                    path.move(to: home)
                    path.addLine(to: first)
                    path.addLine(to: CGPoint(x: 0.50 * s, y: 0.40 * s))
                    path.addLine(to: third)
                    path.closeSubpath()
                }
                .fill(Color(red: 0.78, green: 0.62, blue: 0.43))
                Path { path in
                    path.move(to: home)
                    path.addLine(to: CGPoint(x: 0.02 * s, y: 0.37 * s))
                    path.move(to: home)
                    path.addLine(to: CGPoint(x: 0.98 * s, y: 0.37 * s))
                }
                .stroke(Color.white.opacity(0.85), lineWidth: 2)
                ForEach(Array([first, second, third].enumerated()), id: \.offset) { _, base in
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 0.035 * s, height: 0.035 * s)
                        .rotationEffect(.degrees(45))
                        .position(base)
                }
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 0.035 * s, height: 0.035 * s)
                    .position(home)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .allowsHitTesting(false)
    }
}
