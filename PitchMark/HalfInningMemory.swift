//
//  HalfInningMemory.swift
//  PitchMark
//
//  Count, outs and runners per batting team (2026-11-21, user's call:
//  always ask). The tracker has one count / outs / runners on screen. When
//  the scorer taps the other pitcher, the team at bat changes, but the
//  board used to carry the old team's runners and count over. Now each
//  team's half-inning is saved when it stops batting, the board starts
//  fresh for the new team, and if that team was mid-half-inning last time
//  a quick card asks: keep it (runner on 1st · 1-2 · 1 out) or reset.
//
//  Device-local (per game, per batting side) - the restored values go back
//  through the normal count/outs/bases writers, so a live room syncs them.
//
//  Plain rules, kept out of PitchTrackerView so they can be tested.
//

import Foundation

/// One batting team's half-inning as it stood when it stopped batting.
struct HalfInningState: Codable, Equatable {
    var balls: Int = 0
    var strikes: Int = 0
    var outs: Int = 0
    var bases: BaseOccupancy = .empty

    static let fresh = HalfInningState()

    var isFresh: Bool { self == .fresh }

    /// "runner on 1st · 1-2 · 1 out" / "runners on 1st, 3rd · 0-0 · 2 outs".
    var summary: String {
        let occupied = [1, 2, 3].filter { bases[$0] != nil }
        let ordinal = ["", "1st", "2nd", "3rd"]
        let runners: String
        switch occupied.count {
        case 0: runners = "bases empty"
        case 3: runners = "bases loaded"
        case 1: runners = "runner on \(ordinal[occupied[0]])"
        default: runners = "runners on " + occupied.map { ordinal[$0] }.joined(separator: ", ")
        }
        return "\(runners) · \(balls)-\(strikes) · \(outs) out\(outs == 1 ? "" : "s")"
    }
}

enum HalfInningMemory {
    enum Side: String, Codable { case home, away }

    /// What happens when a team comes up to bat.
    enum Plan: Equatable {
        /// Nothing saved (or it ended clean - a third out resets the board):
        /// start fresh, no question.
        case fresh
        /// It was mid-half-inning: ask Keep or Reset.
        case ask(HalfInningState)
    }

    static func plan(saved: HalfInningState?) -> Plan {
        guard let saved, !saved.isFresh else { return .fresh }
        return .ask(saved)
    }

    private static func key(gameId: String, batting: Side) -> String {
        "halfInning.\(gameId).\(batting.rawValue)"
    }

    static func load(gameId: String, batting: Side, defaults: UserDefaults = .standard) -> HalfInningState? {
        guard let data = defaults.data(forKey: key(gameId: gameId, batting: batting)) else { return nil }
        return try? JSONDecoder().decode(HalfInningState.self, from: data)
    }

    static func save(_ state: HalfInningState, gameId: String, batting: Side, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key(gameId: gameId, batting: batting))
    }
}

import SwiftUI

/// The question when a team comes up to bat mid-half-inning.
struct HalfInningPrompt: Equatable {
    var teamName: String
    var state: HalfInningState
}

/// A quick card over the bottom of the tracker - not a sheet - asking to
/// keep the team's last half-inning or start fresh. Reads only `ui`: Keep
/// goes back through `ui.requestedHalfInning` (the tracker applies it).
struct HalfInningPromptCard: View {
    @ObservedObject var ui: TrackerUIState

    var body: some View {
        if let prompt = ui.halfInningPrompt {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(prompt.teamName) at bat")
                    .font(.headline)
                Text("Last time: \(prompt.state.summary)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("halfInning.summary")
                HStack(spacing: 10) {
                    Button {
                        ui.requestedHalfInning = prompt.state
                        ui.halfInningPrompt = nil
                    } label: {
                        Text("Keep").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.pitchMarkActiveGray)
                    .accessibilityIdentifier("halfInning.keep")
                    Button {
                        ui.halfInningPrompt = nil
                    } label: {
                        Text("Reset").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                    .accessibilityIdentifier("halfInning.reset")
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("halfInning.card")
        }
    }
}
