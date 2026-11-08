//
//  TrackerSelectionMemory.swift
//  PitchMark
//
//  Who was pitching and who was up, per game, so leaving a game (or the
//  app) and coming back lands on the same side, pitcher and batter
//  (2026-11-02). Each side keeps its own pitcher and batter: switching
//  Us/Them and back returns to whoever was there.
//
//  Device-local (UserDefaults), like the per-game key and pitcher maps. A
//  live room's partner still follows the owner through the room.
//

import Foundation

struct TrackerSelectionMemory: Codable, Equatable {
    struct SideState: Codable, Equatable {
        var pitcherId: String? = nil
        var batterId: String? = nil
    }

    /// The side that was pitching.
    var pitchingSide: String = GameSide.home.rawValue
    var sides: [String: SideState] = [:]

    var side: GameSide { GameSide(rawValue: pitchingSide) ?? .home }

    func pitcherId(for side: GameSide) -> String? { sides[side.rawValue]?.pitcherId }

    func batterId(for side: GameSide) -> UUID? {
        sides[side.rawValue]?.batterId.flatMap(UUID.init(uuidString:))
    }

    mutating func setPitchingSide(_ side: GameSide) {
        pitchingSide = side.rawValue
    }

    mutating func setPitcher(_ id: String?, for side: GameSide) {
        sides[side.rawValue, default: SideState()].pitcherId = id
    }

    mutating func setBatter(_ id: UUID?, for side: GameSide) {
        sides[side.rawValue, default: SideState()].batterId = id?.uuidString
    }

    // MARK: Storage

    static let defaultsKey = "trackerSelectionMemoryByGameId"

    static func load(gameId: String, defaults: UserDefaults = .standard) -> TrackerSelectionMemory {
        guard let all = defaults.dictionary(forKey: defaultsKey) as? [String: Data],
              let data = all[gameId],
              let memory = try? JSONDecoder().decode(TrackerSelectionMemory.self, from: data)
        else { return TrackerSelectionMemory() }
        return memory
    }

    /// Reads, changes and writes back one game's memory.
    static func update(gameId: String, defaults: UserDefaults = .standard, _ change: (inout TrackerSelectionMemory) -> Void) {
        guard !gameId.isEmpty else { return }
        var memory = load(gameId: gameId, defaults: defaults)
        change(&memory)
        var all = defaults.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
        guard let data = try? JSONEncoder().encode(memory) else { return }
        all[gameId] = data
        defaults.set(all, forKey: defaultsKey)
    }
}
