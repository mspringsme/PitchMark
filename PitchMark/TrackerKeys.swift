//
//  TrackerKeys.swift
//  PitchMark
//
//  "No Key" in a game (2026-11-21, user's calls). A pitching key belongs to
//  one pitcher; carrying the last pitcher's key over to the next one showed
//  the wrong key and chips (tracking Lockport's pitcher under "Pitch Key:
//  Hadley Sprin..."). So every pitcher starts on No Key - at the start of a
//  game and whenever the pitching changes - with a reminder that offers the
//  pitcher's own key. With No Key the chips are every pitch type (plus
//  Unknown in Track Game, to guess the other team's pitch), no code shows
//  and no spot is greyed out.
//
//  Plain rules, kept out of PitchTrackerView so they can be tested.
//

import Foundation
import SwiftUI

enum TrackerKeyRules {
    /// The chips with No Key: every pitch type - Call Pitches keeps its
    /// Catcher chip first, Track Game adds Unknown last (PitchEntryFlow).
    static func noKeyChips(mode: TrackingMode) -> [String] {
        PitchEntryFlow.chipOptions(allPitches, mode: mode)
    }

    /// Whether picking this pitcher resets the key: in a game, whenever the
    /// pitcher actually changes (not re-selecting the same one).
    static func resetsKey(isGame: Bool, previousPitcherId: String?, newPitcherId: String?) -> Bool {
        guard isGame, let newPitcherId, !newPitcherId.isEmpty else { return false }
        return previousPitcherId != newPitcherId
    }

    /// Whether applying a key ends No Key. A key the coach picks does; an
    /// automatic restore (the game's last key, put back whenever templates
    /// or pitchers finish loading) never does on the coach's own game - it
    /// used to undo "Keep No Key" a moment later. A live partner follows the
    /// coach's key.
    static func applyingKeyEndsNoKey(pickedByUser: Bool, isGame: Bool, isOwner: Bool) -> Bool {
        pickedByUser || !(isGame && isOwner)
    }

    // MARK: Each pitcher's key, remembered per game (2026-11-22)

    /// A pitcher's key choice: No Key, or a key by id. Kept per game so the
    /// pop-up doesn't come back every half inning - switching sides puts
    /// the other side's pitcher in, which used to count as a new pitcher.
    enum KeyChoice: Equatable {
        case noKey
        case key(String)

        init?(stored: String?) {
            guard let stored else { return nil }
            if stored == "nokey" { self = .noKey; return }
            guard stored.hasPrefix("key:"), stored.count > 4 else { return nil }
            self = .key(String(stored.dropFirst(4)))
        }

        var stored: String {
            switch self {
            case .noKey: return "nokey"
            case .key(let id): return "key:\(id)"
            }
        }
    }

    enum PitcherInPlan: Equatable {
        /// Put their remembered choice back - no pop-up.
        case restore(KeyChoice)
        /// No choice yet: No Key and the pop-up.
        case ask
        /// The same pitcher again: change nothing.
        case keep
    }

    /// What happens when a pitcher comes in. A remembered key that no
    /// longer exists counts as no choice.
    static func planForPitcher(previousPitcherId: String?, newPitcherId: String,
                               remembered: KeyChoice?, rememberedKeyExists: Bool) -> PitcherInPlan {
        if previousPitcherId == newPitcherId { return .keep }
        switch remembered {
        case .noKey?: return .restore(.noKey)
        case .key(let id)? where rememberedKeyExists: return .restore(.key(id))
        default: return .ask
        }
    }

    /// The pitcher whose choice is forgotten: one replaced by another on the
    /// same side. A side switch replaces no one.
    static func replacedPitcher(previousPitcherId: String?, newPitcherId: String, sameSide: Bool) -> String? {
        guard let previousPitcherId, previousPitcherId != newPitcherId, sameSide else { return nil }
        return previousPitcherId
    }

    /// Track Game never uses a key (2026-11-21, user's call): no code is
    /// sent, the other team's pitcher may throw anything, and a key's
    /// greyed spots would block recording where a pitch really went. The
    /// coach's key (or No Key) is kept for Call Pitches.
    static func keyIsOff(noKey: Bool, mode: TrackingMode) -> Bool {
        noKey || mode == .scout
    }

    /// The "No key for this pitcher" reminder is for calling pitches.
    static func showsKeyReminder(mode: TrackingMode) -> Bool {
        mode == .coach
    }

    /// Whether entering a game starts on No Key: the coach does; a live
    /// partner follows the coach's key.
    static func gameStartsOnNoKey(isOwner: Bool) -> Bool {
        isOwner
    }

    /// The reminder after a reset: its title, and the key it can switch to -
    /// the pitcher's own linked key, if they have one.
    struct Reminder: Equatable {
        var title: String
        var message: String
        var ownKeyId: String?
        var ownKeyName: String?
    }

    static func reminder(pitcherName: String, ownKey: (id: String, name: String)?) -> Reminder {
        let name = pitcherName.isEmpty ? "this pitcher" : pitcherName
        return Reminder(
            title: "No key for \(name)",
            message: "Each pitcher starts with No Key, so another pitcher's key never carries over. "
                + (ownKey.map { "Use \($0.name) to call pitches, or keep No Key to track." }
                    ?? "Choose a key to call pitches, or keep No Key to track."),
            ownKeyId: ownKey?.id,
            ownKeyName: ownKey?.name
        )
    }
}

/// The reminder after a pitcher change put the key on No Key. A modifier
/// struct that reads only `ui`, so the tracker's body stays small (CLAUDE.md
/// stack notes). "Use {key}" goes back through `ui.requestedKeyId`; "Choose
/// a Key" opens the key sheet.
struct KeyReminderPresenter: ViewModifier {
    @ObservedObject var ui: TrackerUIState
    @State private var isPresented = false

    func body(content: Content) -> some View {
        let reminder = ui.keyReminder
        return content
            .onChange(of: ui.keyReminder) { _, new in
                if new != nil { isPresented = true }
            }
            .appConfirmationDialog(
                isPresented: $isPresented,
                title: reminder?.title ?? "No key",
                message: reminder?.message ?? "",
                primaryTitle: reminder?.ownKeyName.map { "Use \($0)" } ?? "Choose a Key",
                primaryAction: {
                    if let id = reminder?.ownKeyId {
                        ui.requestedKeyId = id
                    } else {
                        ui.showGridKeySheet = true
                    }
                    ui.keyReminder = nil
                },
                secondaryTitle: "Keep No Key",
                secondaryAction: {
                    ui.keyReminder = nil
                    ui.noKeyChosenCount += 1
                }
            )
    }
}
