//
//  ProfileMerge.swift
//  PitchMark
//
//  The decisions behind Link / Merge Duplicates (PlayerLinks.swift) and the
//  cleanup that follows (Player.swift), as plain values so they can be
//  tested without Firestore. The AuthManager code only carries them out.
//
//  The one rule everything here serves: a merge may delete a roster row or
//  record only when nothing still uses it and it holds no history, and
//  every ambiguity - a roster that couldn't be read, a record whose history
//  couldn't be checked - resolves toward keeping.
//

import Foundation

enum ProfileMerge {

    // MARK: Roster rows

    struct RowStep {
        enum Action: Equatable { case repoint, remove }
        let action: Action
        let entry: PlayerRosterEntry
    }

    /// What happens to each folded roster row, in order. Merge Duplicates
    /// removes a folded row on a team the kept player is already on (the
    /// same kid entered twice there); every other row - and every row in
    /// Link - is repointed. A row that has moved covers its team for the
    /// rows after it.
    static func rowSteps(
        keep: PlayerProfile,
        fold: [PlayerProfile],
        mode: AuthManager.ProfileCombineMode
    ) -> [RowStep] {
        var covered = Set(keep.teams.compactMap { $0.id })
        var steps: [RowStep] = []
        for entry in fold.flatMap(\.entries) {
            guard let teamId = entry.team.id, entry.teamPlayer.id != nil else { continue }
            if mode == .mergeDuplicate, covered.contains(teamId) {
                steps.append(RowStep(action: .remove, entry: entry))
            } else {
                covered.insert(teamId)
                steps.append(RowStep(action: .repoint, entry: entry))
            }
        }
        return steps
    }

    /// The duplicate's records that need a history check before the row
    /// may move off them. The kept player's own record is nothing to check.
    static func recordsToCheck(on duplicate: TeamPlayer, canonical: Player) -> (pitcherId: String?, hitterId: String?) {
        (
            duplicate.pitcherId.flatMap { $0 == canonical.pitcherId ? nil : $0 },
            duplicate.hitterId.flatMap { $0 == canonical.hitterId ? nil : $0 }
        )
    }

    struct Repoint: Equatable {
        let playerId: String
        let name: String
        /// Set only when the row moves onto the kept player's record.
        let pitcherId: String?
        let hitterId: String?

        var data: [String: Any] {
            var data: [String: Any] = ["playerId": playerId, "name": name]
            if let pitcherId { data["pitcherId"] = pitcherId }
            if let hitterId { data["hitterId"] = hitterId }
            return data
        }
    }

    /// A repointed row always takes the kept player's id and name. It takes
    /// the kept Pitcher/Hitter only where its own record is empty - a record
    /// with history (`keptPitcherId`/`keptHitterId`) stays on the row.
    static func repoint(
        _ duplicate: TeamPlayer,
        onto canonical: Player,
        keptPitcherId: String?,
        keptHitterId: String?
    ) -> Repoint? {
        guard duplicate.id != nil, let playerId = canonical.id else { return nil }
        return Repoint(
            playerId: playerId,
            name: canonical.name,
            pitcherId: keptPitcherId == nil ? canonical.pitcherId : nil,
            hitterId: keptHitterId == nil ? canonical.hitterId : nil
        )
    }

    struct Candidates: Equatable {
        var playerId: String? = nil
        var pitcherId: String? = nil
        var hitterId: String? = nil

        var isEmpty: Bool { playerId == nil && pitcherId == nil && hitterId == nil }
    }

    /// What a repointed row leaves behind for cleanup: the identity it left,
    /// and the records it moved off (never one it kept because of history).
    static func leftBehind(
        by duplicate: TeamPlayer,
        canonical: Player,
        keptPitcherId: String?,
        keptHitterId: String?
    ) -> Candidates {
        Candidates(
            playerId: duplicate.playerId == canonical.id ? nil : duplicate.playerId,
            pitcherId: keptPitcherId == nil ? duplicate.pitcherId : nil,
            hitterId: keptHitterId == nil ? duplicate.hitterId : nil
        )
    }

    // MARK: Records

    /// Every record and identity the folded profiles bring, minus the kept
    /// player's own. The records with history get added to the kept
    /// player's linked lists; the rest go to cleanup.
    static func foldedRecords(
        _ fold: [PlayerProfile],
        canonical: Player
    ) -> (pitcherIds: [String], hitterIds: [String], playerIds: [String]) {
        let ownPitchers = Set(canonical.allPitcherIds)
        let ownHitters = Set(canonical.allHitterIds)
        return (
            PlayerLinks.uniqueOrdered(fold.flatMap(\.pitcherIds)).filter { !ownPitchers.contains($0) },
            PlayerLinks.uniqueOrdered(fold.flatMap(\.hitterIds)).filter { !ownHitters.contains($0) },
            PlayerLinks.uniqueOrdered(fold.flatMap(\.playerIds)).filter { $0 != canonical.id }
        )
    }

    /// A record has history when any of its event collections has an event.
    /// A read that failed counts as history - keep the record, never delete
    /// one on a guess. A Hitter's history is its pitches *and* its runner
    /// events (steals, caught stealing, pickoffs), so a pinch runner who
    /// never batted still has one.
    static func hasHistory(_ reads: [Result<Bool, Error>]) -> Bool {
        reads.contains { read in
            switch read {
            case .success(let has): return has
            case .failure: return true
            }
        }
    }

    /// The event collections whose events make up a record's history.
    static func historyPaths(pitcherId: String) -> [String] {
        ["pitchers/\(pitcherId)/pitchEvents"]
    }

    static func historyPaths(hitterId: String) -> [String] {
        ["hitters/\(hitterId)/pitchEvents", "hitters/\(hitterId)/\(RunnerEventStore.collection)"]
    }

    /// The linked histories a duplicate Player doc carries that the kept
    /// player doesn't yet. They must reach the kept player before the
    /// duplicate doc may be deleted, or those records stop belonging to
    /// the kid. (Its primary records are on its roster rows, which the row
    /// steps already handle.)
    static func linksToMove(from duplicate: Player, onto canonical: Player) -> (pitcherIds: [String], hitterIds: [String]) {
        let ownPitchers = Set(canonical.allPitcherIds)
        let ownHitters = Set(canonical.allHitterIds)
        return (
            PlayerLinks.uniqueOrdered(duplicate.linkedPitcherIds ?? []).filter { !ownPitchers.contains($0) },
            PlayerLinks.uniqueOrdered(duplicate.linkedHitterIds ?? []).filter { !ownHitters.contains($0) }
        )
    }

    // MARK: Cleanup

    /// Which candidates nothing references any more, given one roster read
    /// per team. `nil` means delete nothing: no teams, a read that failed
    /// (a failed read looks like an empty roster, and an empty roster would
    /// make everything on it look unused), or no rows seen at all. The kept
    /// player's own identity and records are never candidates.
    /// The candidates minus the kept player's own identity and records.
    static func excludingKept(_ candidates: Candidates, canonical: Player) -> Candidates {
        var candidates = candidates
        if candidates.playerId == canonical.id { candidates.playerId = nil }
        if let id = candidates.pitcherId, canonical.allPitcherIds.contains(id) { candidates.pitcherId = nil }
        if let id = candidates.hitterId, canonical.allHitterIds.contains(id) { candidates.hitterId = nil }
        return candidates
    }

    static func unreferenced(
        _ candidates: Candidates,
        canonical: Player,
        rosterReads: [Result<[TeamPlayer], Error>]
    ) -> Candidates? {
        var candidates = excludingKept(candidates, canonical: canonical)
        guard !candidates.isEmpty, !rosterReads.isEmpty else { return nil }

        var rows: [TeamPlayer] = []
        for read in rosterReads {
            guard case .success(let teamRows) = read else { return nil }
            rows += teamRows
        }
        guard !rows.isEmpty else { return nil }

        if let id = candidates.playerId, rows.contains(where: { $0.playerId == id }) { candidates.playerId = nil }
        if let id = candidates.pitcherId, rows.contains(where: { $0.pitcherId == id }) { candidates.pitcherId = nil }
        if let id = candidates.hitterId, rows.contains(where: { $0.hitterId == id }) { candidates.hitterId = nil }
        return candidates.isEmpty ? nil : candidates
    }

    // MARK: Linking to a new team

    /// The row Link adds on a team the kid isn't on yet: the kept player's
    /// identity, name and records. Jersey numbers are team-local, so it
    /// starts blank unless one is given.
    static func newRosterRow(
        for player: Player,
        rowId: String,
        jerseyNumber: String?,
        createdByUid: String,
        createdAt: Date
    ) -> TeamPlayer {
        TeamPlayer(
            id: rowId,
            name: player.name,
            jerseyNumber: jerseyNumber,
            pitcherId: player.pitcherId,
            playerId: player.id,
            hitterId: player.hitterId,
            positions: player.positions,
            battingSide: player.battingSide,
            createdByUid: createdByUid,
            createdAt: createdAt
        )
    }

    // MARK: Open game

    /// Profiles on either team of the game open in the tracker. Merging can
    /// remove one of their roster rows, so - like archiving - it waits for
    /// the game to close.
    static func lockedByOpenGame(_ profiles: [PlayerProfile], openGameTeamIds: Set<String>) -> [PlayerProfile] {
        profiles.filter { !openGameTeamIds.isDisjoint(with: $0.teams.compactMap(\.id)) }
    }
}
