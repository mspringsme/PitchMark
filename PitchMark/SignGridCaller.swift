//
//  SignGridCaller.swift
//  PitchMark
//
//  Call Sheet, step 1 (2026-11-14): calling a Batting Bases & Fielding
//  card's signs from the coach's phone. Tap a call, get one of its numbers
//  big; the numbers are the calling card's (`SignGridCallingCard`), so they
//  always match the armband the players wear.
//
//  Which number (user's picks): rotate on every call, never the same number
//  twice in a row for a call, and every number used evenly - each within
//  one use of the others. Signs never go to the Display device.
//

import SwiftUI
import UIKit

/// Which of a call's numbers to give next - shared by the batting and the
/// pitching Call Sheets (2026-11-14, user's picks): never the same number
/// twice in a row for a call, and every number used evenly, each within
/// one use of the others. Keyed by whatever names the call.
struct CodeRotation {
    /// How often each number of each call has been given.
    private(set) var uses: [String: [String: Int]] = [:]
    private(set) var lastCode: [String: String] = [:]

    /// The next of `codes` for `key`, or nil when there are none. `pick`
    /// chooses among equally good numbers (random in the app; tests pass a
    /// fixed one).
    mutating func next(
        for key: String,
        from codes: [String],
        pick: ([String]) -> String? = { $0.randomElement() }
    ) -> String? {
        guard !codes.isEmpty else { return nil }
        let counts = uses[key] ?? [:]
        let fewest = codes.map { counts[$0] ?? 0 }.min() ?? 0
        var pool = codes.filter { (counts[$0] ?? 0) == fewest }
        // Even use already keeps the last number out of the pool unless
        // every number is tied; then skip it so it never comes twice.
        if pool.count > 1, let last = lastCode[key] {
            pool.removeAll { $0 == last }
        }
        guard let code = pick(pool) ?? pool.first else { return nil }
        uses[key, default: [:]][code, default: 0] += 1
        lastCode[key] = code
        return code
    }
}

/// The batting calling rules, apart from the view so they can be tested.
struct SignGridCaller {
    struct Called: Equatable, Identifiable {
        let id = UUID()
        let label: String
        let code: String

        static func == (lhs: Called, rhs: Called) -> Bool {
            lhs.label == rhs.label && lhs.code == rhs.code
        }
    }

    static let recentLimit = 8

    let card: SignGridCallingCard
    private(set) var rotation = CodeRotation()
    /// Newest first, at most `recentLimit`.
    private(set) var recent: [Called] = []

    init(card: SignGridCallingCard) {
        self.card = card
    }

    func codes(for label: String) -> [String] {
        card.calls.first { $0.label == label }?.codes ?? []
    }

    /// The next number for `label`, or nil when the call has none.
    @discardableResult
    mutating func call(
        _ label: String,
        pick: ([String]) -> String? = { $0.randomElement() }
    ) -> Called? {
        guard let code = rotation.next(for: label, from: codes(for: label), pick: pick) else { return nil }
        let called = Called(label: label, code: code)
        recent.insert(called, at: 0)
        if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
        return called
    }
}

/// The Batting & Fielding tab of the Call Sheet (CallSheet.swift): the
/// latest call big at the top, the armband one tap away, recent calls,
/// then a button per call. The caller lives in the Call Sheet so rotation
/// survives switching tabs and cards.
struct SignGridCallPanel: View {
    let grid: SignGrid
    @Binding var caller: SignGridCaller
    @Binding var current: SignGridCaller.Called?

    @State private var showArmband = false
    @State private var search = ""

    private var card: SignGridCallingCard { caller.card }

    private var filteredCalls: [SignGridCallingCard.Call] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return card.calls }
        return card.calls.filter { $0.label.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if card.isEmpty {
                CallSheetEmptyMessage(
                    systemImage: "rectangle.grid.3x2",
                    title: "No calls to make yet",
                    detail: "Type calls into this card's cells. Each call is called by its column number and row number, like on the calling card."
                )
            } else {
                CallDisplayBox(
                    title: current?.label,
                    code: current?.code,
                    hint: current.map { caller.codes(for: $0.label).count > 1 ? "Tap for another number" : "Its only number" },
                    placeholder: "Tap a call",
                    codeIdentifier: "callSheet.code"
                ) {
                    if let label = current?.label { call(label) }
                }
                CallSheetToggleButton(
                    isOn: $showArmband,
                    onTitle: "Hide Armband",
                    offTitle: "Show Armband",
                    identifier: "callSheet.armband"
                )
                if showArmband { armband }
                CallRecentStrip(items: caller.recent.map { CallRecentStrip.Item(id: $0.id, text: "\($0.label) · \($0.code)") })
                searchField
                callButtons
                if card.unnumberedCount > 0 {
                    Text(card.unnumberedCount == 1
                         ? "1 call has no row or column number, so it can't be called."
                         : "\(card.unnumberedCount) calls have no row or column number, so they can't be called.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var armband: some View {
        let size = (grid.printSize ?? GridKeyPrintSize(widthInches: 5, heightInches: 3)).points
        return GeometryReader { proxy in
            let scale = proxy.size.width / max(size.width, 1)
            SignGridCardView(grid: grid, size: size)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: proxy.size.width, height: size.height * scale, alignment: .topLeading)
        }
        .aspectRatio(size.width / max(size.height, 1), contentMode: .fit)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))
        .accessibilityIdentifier("callSheet.armbandCard")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find a call", text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
    }

    private var callButtons: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
            ForEach(filteredCalls, id: \.label) { item in
                let isCurrent = current?.label == item.label
                Button {
                    call(item.label)
                } label: {
                    VStack(spacing: 2) {
                        Text(item.label)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .multilineTextAlignment(.center)
                        Text(item.codes.count == 1 ? "1 number" : "\(item.codes.count) numbers")
                            .font(.caption2)
                            .opacity(0.7)
                    }
                    .foregroundStyle(isCurrent ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isCurrent ? Color.pitchMarkActiveGray : Color.secondary.opacity(0.14))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("callSheet.call.\(item.label)")
            }
        }
    }

    private func call(_ label: String) {
        if let called = caller.call(label) {
            current = called
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
