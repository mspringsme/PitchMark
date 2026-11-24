//
//  CaptureGuardrails.swift
//  PitchMark
//
//  Cost and safety guardrails for cloud clips, game feeds and full-game
//  video (brief "Clip Feed, Game Feeds + Full-Game Video", sections 5 and
//  8b). The server twin is functions/src/guardrails.ts - keep the limits and
//  the flag rules identical.
//
//  - `AppFeatureFlags`: what's switched on. Read from `appConfig/flags`,
//    which no app can write. Every cloud feature defaults OFF, and the four
//    behind the release gate stay off in code whatever the doc says.
//  - `CaptureGate`: may this account start a cloud capture right now?
//    Approved team member, team has done real baseball, inside a game's
//    window, feature on. Nothing calls it with a cloud path yet.
//
//  PitchMark only - not in the Display target.
//

import Foundation
import Combine
import FirebaseFirestore

enum AppFeature: String, CaseIterable {
    case cloudClips
    case fullGameVideo
    case viewerPass
    case contentSafety
    case gameFeeds
    case interimClipSharing
    case followAlerts

    /// Built now, never enabled for a user until legal review, the Android
    /// app and a known-team beta are all done (brief section 11).
    var isBehindReleaseGate: Bool {
        switch self {
        case .cloudClips, .fullGameVideo, .viewerPass, .contentSafety: return true
        case .gameFeeds, .interimClipSharing, .followAlerts: return false
        }
    }
}

struct AppFeatureFlags: Equatable {
    /// Flip to true only when the release gate is passed - in code, so a
    /// console edit can't turn on cloud video. Matches `releaseGateCleared`
    /// in guardrails.ts.
    static let releaseGateCleared = false

    /// nil = no flags doc read (offline, missing, denied).
    var raw: [String: Any]? = nil

    static func == (lhs: AppFeatureFlags, rhs: AppFeatureFlags) -> Bool {
        AppFeature.allCases.allSatisfy { lhs.isOn($0) == rhs.isOn($0) }
            && lhs.killSwitchTripped == rhs.killSwitchTripped
    }

    var killSwitchTripped: Bool { raw?["killSwitch"] as? Bool == true }

    /// Interim sharing is on-device (no cloud bill), so it's on unless the
    /// doc turns it off, and it survives the kill switch. Everything else
    /// needs an explicit true.
    func isOn(_ feature: AppFeature) -> Bool {
        guard let raw, !killSwitchTripped else {
            return feature == .interimClipSharing && raw?["interimClipSharing"] as? Bool != false
        }
        if feature.isBehindReleaseGate && !Self.releaseGateCleared { return false }
        if feature == .interimClipSharing { return raw["interimClipSharing"] as? Bool != false }
        return raw[feature.rawValue] as? Bool == true
    }
}

/// Listens to `appConfig/flags`. Start once signed in; a failure leaves
/// the defaults (cloud features off).
@MainActor
final class AppFeatureFlagStore: ObservableObject {
    static let shared = AppFeatureFlagStore()
    @Published private(set) var flags = AppFeatureFlags()
    private var listener: ListenerRegistration?

    func start() {
        guard listener == nil else { return }
        listener = Firestore.firestore().collection("appConfig").document("flags")
            .addSnapshotListener { [weak self] snapshot, _ in
                let data = snapshot?.data()
                Task { @MainActor in self?.flags = AppFeatureFlags(raw: data) }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
        flags = AppFeatureFlags()
    }
}

/// The limits, identical to guardrails.ts.
enum CaptureLimits {
    static let maxClipSeconds: Double = 60
    static let targetClipSeconds: Double = 30
    static let perPersonPerGameClips = 25
    static let perPersonPerGameSeconds: Double = 10 * 60
    /// Capture only from 30 minutes before a game to 4 hours after it starts.
    static let windowBefore: TimeInterval = 30 * 60
    static let windowAfter: TimeInterval = 4 * 60 * 60
    /// A new account waits this long before it may upload or stream.
    static let probationDays = 7
}

/// Why a cloud capture was refused, in words the app can show.
enum CaptureRefusal: Equatable {
    case featureOff
    case notApprovedMember
    case teamNotUnlocked
    case accountInProbation
    case noGameNow
    case quotaReached

    var message: String {
        switch self {
        case .featureOff: return "Sharing clips to the team isn't available yet."
        case .notApprovedMember: return "A coach needs to approve you on this team first."
        case .teamNotUnlocked: return "Team video unlocks after the team scores its first game with a lineup."
        case .accountInProbation: return "New accounts can share to the team after their first week."
        case .noGameNow: return "Clips can be shared to the team during a scheduled game."
        case .quotaReached: return "You've reached this game's clip limit."
        }
    }
}

enum CaptureGate {
    /// A team unlocks cloud video after real baseball: at least one tracked
    /// game with a lineup and a pitch scored (brief 8b).
    static func teamIsUnlocked(scoredGamesWithLineup: Int) -> Bool {
        scoredGamesWithLineup >= 1
    }

    static func accountPastProbation(createdAt: Date?, now: Date) -> Bool {
        guard let createdAt else { return false }
        return now.timeIntervalSince(createdAt) >= Double(CaptureLimits.probationDays) * 86_400
    }

    /// Is `now` inside any game's capture window? Canceled games don't count.
    static func gameInWindow(starts: [Date], now: Date) -> Date? {
        starts.filter { start in
            now >= start.addingTimeInterval(-CaptureLimits.windowBefore)
                && now <= start.addingTimeInterval(CaptureLimits.windowAfter)
        }.min(by: { abs($0.timeIntervalSince(now)) < abs($1.timeIntervalSince(now)) })
    }

    struct Context {
        var feature: AppFeature
        var flags: AppFeatureFlags
        /// Holds an approved membership on the team (any role but a pending one).
        var isApprovedMember: Bool
        var scoredGamesWithLineup: Int
        var accountCreatedAt: Date?
        /// Start times of the team's non-canceled games around now.
        var gameStarts: [Date]
        var clipsThisGame: Int
        var secondsThisGame: Double
        var now: Date
    }

    /// The first rule that refuses, in the order a user would fix them.
    static func check(_ c: Context) -> CaptureRefusal? {
        guard c.flags.isOn(c.feature) else { return .featureOff }
        guard c.isApprovedMember else { return .notApprovedMember }
        guard teamIsUnlocked(scoredGamesWithLineup: c.scoredGamesWithLineup) else { return .teamNotUnlocked }
        guard accountPastProbation(createdAt: c.accountCreatedAt, now: c.now) else { return .accountInProbation }
        guard gameInWindow(starts: c.gameStarts, now: c.now) != nil else { return .noGameNow }
        if c.clipsThisGame >= CaptureLimits.perPersonPerGameClips
            || c.secondsThisGame >= CaptureLimits.perPersonPerGameSeconds { return .quotaReached }
        return nil
    }
}
