//
//  PitchKeyCaller.swift
//  PitchMark
//
//  Call Sheet, step 2 (2026-11-14): calling pitches from a Pitching key
//  on the coach's phone with no game open. Pick a pitch, tap a spot on the
//  key's Strikes or Balls grid, get a code big. Nothing is recorded - with
//  a game open, pitch calling stays on the game screen, which records it
//  (user's pick; Home offers that first).
//
//  The codes come from the same generator the printed key and the store's
//  location sheet use, on a cleaned copy of the key like the print, so
//  what's on screen is what's on the armband. The pad is laid out like the
//  key's grids - a cell here is the same cell there.
//

import SwiftUI
import UIKit

/// A spot on the key's Strikes or Balls grid.
struct PitchKeySpot: Hashable {
    let isStrike: Bool
    let row: Int
    let column: Int

    /// Balls has no middle.
    var exists: Bool { isStrike || !(row == 1 && column == 1) }

    /// The tracker's name for the spot - classic keys store codes by it.
    var trackerLabel: String {
        let names = [
            ["Up & Out", "Up", "Up & In"],
            ["Out", "Middle", "In"],
            ["↓ & Out", "↓", "↓ & In"]
        ]
        return names[row][column]
    }

    static func all(isStrike: Bool) -> [PitchKeySpot] {
        (0..<3).flatMap { row in
            (0..<3).map { PitchKeySpot(isStrike: isStrike, row: row, column: $0) }
        }
    }
}

/// The pitching calling rules, apart from the view so they can be tested.
struct PitchKeyCaller {
    struct Pitch: Hashable {
        /// The name the key's codes are generated from.
        let name: String
        /// The key's abbreviation when it has one.
        let label: String
    }

    struct Called: Equatable, Identifiable {
        let id = UUID()
        let pitch: Pitch
        let spot: PitchKeySpot
        let code: String

        static func == (lhs: Called, rhs: Called) -> Bool {
            lhs.pitch == rhs.pitch && lhs.spot == rhs.spot && lhs.code == rhs.code
        }
    }

    static let recentLimit = 8

    let template: PitchTemplate
    /// The cleaned copy codes are generated from, as the print does.
    private let codeTemplate: PitchTemplate
    let usesGrid: Bool
    let pitches: [Pitch]
    private(set) var rotation = CodeRotation()
    private(set) var recent: [Called] = []

    init(template: PitchTemplate) {
        self.template = template
        self.codeTemplate = Self.cleaned(template)
        self.usesGrid = Self.hasGridData(template)
        self.pitches = Self.pitches(in: template, usesGrid: usesGrid)
    }

    /// Same test the tracker uses to treat a key as a code grid.
    static func hasGridData(_ t: PitchTemplate) -> Bool {
        !t.pitchGridHeaders.isEmpty || !t.pitchGridValues.isEmpty || !t.strikeTopRow.isEmpty
            || !t.strikeRows.isEmpty || !t.ballsTopRow.isEmpty || !t.ballsRows.isEmpty
    }

    private static func pitches(in t: PitchTemplate, usesGrid: Bool) -> [Pitch] {
        var seen = Set<String>()
        if usesGrid {
            let fromHeaders = t.pitchGridHeaders.compactMap { header -> Pitch? in
                let name = header.pitch.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, seen.insert(name).inserted else { return nil }
                let short = header.abbreviation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return Pitch(name: name, label: short.isEmpty ? name : short)
            }
            if !fromHeaders.isEmpty { return fromHeaders }
        }
        return t.pitches
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .map { Pitch(name: $0, label: $0) }
    }

    private static func cleanedText(_ value: String) -> String {
        value.uppercased().filter { $0.isNumber || ($0.isLetter && $0.isASCII) }
    }

    private static func cleaned(_ template: PitchTemplate) -> PitchTemplate {
        var copy = template
        copy.pitchGridValues = template.pitchGridValues.map { $0.map(cleanedText) }
        copy.strikeTopRow = template.strikeTopRow.map(cleanedText)
        copy.ballsTopRow = template.ballsTopRow.map(cleanedText)
        copy.strikeRows = template.strikeRows.map { $0.map(cleanedText) }
        copy.ballsRows = template.ballsRows.map { $0.map(cleanedText) }
        copy.strikeLocationCells = template.strikeLocationCells.map { $0.map(cleanedText) }
        copy.ballsLocationCells = template.ballsLocationCells.map { $0.map(cleanedText) }
        return copy
    }

    /// Every code on the key for this pitch at this spot.
    func codes(for pitch: Pitch, at spot: PitchKeySpot) -> [String] {
        guard spot.exists else { return [] }
        let codes: [String]
        if usesGrid {
            let kind: EncryptedGridKind = spot.isStrike ? .strikes : .balls
            codes = codeTemplate.codeMode == .normal
                ? EncryptedCodeGenerator.generateNormalCalls(
                    template: codeTemplate, selectedPitch: pitch.name,
                    gridKind: kind, columnIndex: spot.column, rowIndex: spot.row)
                : EncryptedCodeGenerator.generateCalls(
                    template: codeTemplate, selectedPitch: pitch.name,
                    gridKind: kind, columnIndex: spot.column, rowIndex: spot.row)
        } else {
            let label = "\(spot.isStrike ? "Strike" : "Ball") \(spot.trackerLabel)"
            codes = template.codeAssignments
                .filter { $0.pitch == pitch.name && $0.location == label }
                .map(\.code)
        }
        var seen = Set<String>()
        return codes.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The next code for this pitch at this spot, or nil when the key has
    /// none there.
    @discardableResult
    mutating func call(
        _ pitch: Pitch,
        at spot: PitchKeySpot,
        pick: ([String]) -> String? = { $0.randomElement() }
    ) -> Called? {
        let key = "\(pitch.name)|\(spot.isStrike)|\(spot.row)|\(spot.column)"
        guard let code = rotation.next(for: key, from: codes(for: pitch, at: spot), pick: pick) else { return nil }
        let called = Called(pitch: pitch, spot: spot, code: code)
        recent.insert(called, at: 0)
        if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
        return called
    }

    /// Grid codes split the way the key prints them: pitch · location.
    func display(_ code: String) -> String {
        guard usesGrid, code.count >= 3 else { return code }
        let chars = Array(code)
        return String(chars[0...1]) + "·" + String(chars[2...])
    }
}

/// The Pitching tab of the Call Sheet (CallSheet.swift). The caller lives
/// in the Call Sheet so rotation survives switching tabs and keys.
struct PitchKeyCallPanel: View {
    let template: PitchTemplate
    @Binding var caller: PitchKeyCaller
    @Binding var current: PitchKeyCaller.Called?

    @State private var pitch: PitchKeyCaller.Pitch?
    @State private var showKey = false
    @State private var keyScale: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if caller.pitches.isEmpty {
                CallSheetEmptyMessage(
                    systemImage: "baseball",
                    title: "No pitches on this key yet",
                    detail: "Add pitches to the key in its editor, then call from here."
                )
            } else {
                CallDisplayBox(
                    title: current.map { "\($0.pitch.name) · \($0.spot.isStrike ? "Strike" : "Ball")" },
                    code: current.map { caller.display($0.code) },
                    hint: current.map { caller.codes(for: $0.pitch, at: $0.spot).count > 1 ? "Tap for another code" : "Its only code" },
                    placeholder: "Pick a pitch, then a spot",
                    codeIdentifier: "pitchCall.code"
                ) {
                    if let current { call(current.pitch, at: current.spot) }
                }
                if caller.usesGrid {
                    CallSheetToggleButton(
                        isOn: $showKey,
                        onTitle: "Hide Key",
                        offTitle: "Show Key",
                        identifier: "pitchCall.key"
                    )
                    if showKey { keyView }
                }
                CallRecentStrip(items: caller.recent.map {
                    CallRecentStrip.Item(id: $0.id, text: "\($0.pitch.label) \($0.spot.isStrike ? "K" : "B") · \(caller.display($0.code))")
                })
                pitchChips
                HStack(alignment: .top, spacing: 12) {
                    spotGrid(isStrike: true)
                    spotGrid(isStrike: false)
                }
                Text("Tap the same spot as on the key. Nothing is recorded - to record pitches, call them from a game.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if pitch == nil { pitch = current?.pitch ?? caller.pitches.first }
        }
    }

    /// The key as it prints, scaled to the screen's width.
    private var keyView: some View {
        let size = template.chosenPrintSize.points
        return GeometryReader { proxy in
            let fit = proxy.size.width / max(size.width, 1)
            ZStack {
                Color.white
                if let keyScale {
                    GridKeyPrint.view(for: template, scale: keyScale)
                }
            }
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .light)
            .scaleEffect(fit, anchor: .topLeading)
            .frame(width: proxy.size.width, height: size.height * fit, alignment: .topLeading)
        }
        .aspectRatio(size.width / max(size.height, 1), contentMode: .fit)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))
        .onAppear {
            if keyScale == nil { keyScale = GridKeyPrint.fitScale(for: template, on: size) }
        }
        .accessibilityIdentifier("pitchCall.keyCard")
    }

    private var pitchChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pitch")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                ForEach(caller.pitches, id: \.self) { item in
                    let isSelected = pitch == item
                    Button {
                        pitch = item
                    } label: {
                        Text(item.name)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.horizontal, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? Color.pitchMarkActiveGray : Color.secondary.opacity(0.14))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pitchCall.pitch.\(item.name)")
                }
            }
        }
    }

    private func spotGrid(isStrike: Bool) -> some View {
        VStack(spacing: 6) {
            Text(isStrike ? "Strikes" : "Balls")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(PitchKeySpot.all(isStrike: isStrike), id: \.self) { spot in
                    let isCurrent = current?.spot == spot && current?.pitch == pitch
                    let available = spot.exists && pitch.map { !caller.codes(for: $0, at: spot).isEmpty } == true
                    Button {
                        if let pitch { call(pitch, at: spot) }
                    } label: {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(spotColor(isStrike: isStrike, isCurrent: isCurrent, available: available))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.primary.opacity(isCurrent ? 0.9 : 0.15), lineWidth: isCurrent ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!available)
                    .opacity(spot.exists ? 1 : 0)
                    .accessibilityLabel("\(isStrike ? "Strike" : "Ball") row \(spot.row + 1) column \(spot.column + 1)")
                    .accessibilityIdentifier("pitchCall.spot.\(isStrike ? "K" : "B").\(spot.row).\(spot.column)")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func spotColor(isStrike: Bool, isCurrent: Bool, available: Bool) -> Color {
        guard available else { return Color.secondary.opacity(0.08) }
        let base: Color = isStrike ? .green : .red
        return base.opacity(isCurrent ? 0.75 : 0.35)
    }

    private func call(_ pitch: PitchKeyCaller.Pitch, at spot: PitchKeySpot) {
        if let called = caller.call(pitch, at: spot) {
            current = called
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
