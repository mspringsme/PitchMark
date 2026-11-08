//
//  LaunchHomeGate.swift
//  PitchMark
//
//  When the app may send the coach back to Home on its own at launch.
//
//  Bug (2026-10-31): tapping a game right after launch loaded the tracker
//  and then flashed back to Home. The launch decision ("been away 15+
//  minutes, start on Home") was *made* immediately but *applied* in the
//  completion of the primary-session Firestore read - and after a fresh
//  install or an Xcode run that first read is slow enough for the coach to
//  have opened a game already. A relaunch hid it: the read was fast and the
//  idle clock had been reset by the backgrounding.
//
//  The rule now: the launch decision is applied at once, and anything that
//  finishes later (the session read, the boot loaders) may only send the
//  coach to Home if they haven't opened a game since launch.
//
//  Pure Foundation so it can be unit tested.
//

import Foundation

struct LaunchHomeGate: Equatable {
    /// Away this long and the app starts on Home.
    static let idleLimit: TimeInterval = 15 * 60

    /// Whether launch should land on Home: the one-shot "force on next
    /// launch" flag, or a long enough time since the app was last in the
    /// background. `lastBackgroundAt` of 0 means never recorded.
    static func shouldForceHomeOnLaunch(forceFlag: Bool, lastBackgroundAt: TimeInterval, now: TimeInterval) -> Bool {
        forceFlag || isIdleTooLong(lastBackgroundAt: lastBackgroundAt, now: now)
    }

    static func isIdleTooLong(lastBackgroundAt: TimeInterval, now: TimeInterval) -> Bool {
        lastBackgroundAt > 0 && now - lastBackgroundAt >= idleLimit
    }

    /// Set once the coach opens a game in this process.
    private(set) var coachOpenedGame = false

    /// Set by the first appearance of the tracker in this process.
    private(set) var didFirstAppear = false

    /// True only the first time it's asked. The tracker's `.onAppear` fires
    /// on *every* return to the Game tab, and running the launch flow there
    /// re-applied "away 15+ minutes, start on Home" - `lastBackgroundAt`
    /// isn't reset while the app is open, so after 15 minutes in the app
    /// every trip back to Game bounced straight to Home (2026-11-02).
    /// Sign-in changes rerun the flow on their own, not through here.
    mutating func claimFirstAppear() -> Bool {
        guard !didFirstAppear else { return false }
        didFirstAppear = true
        return true
    }

    mutating func noteGameOpened() {
        coachOpenedGame = true
    }

    /// May work that finishes after launch (network reads, loaders) still
    /// move the coach to Home? Only if they haven't opened a game since -
    /// otherwise it yanks them out of the game they just picked.
    var allowsLateHome: Bool { !coachOpenedGame }

    /// The boot sequence's late decision, after the session read: go to Home
    /// when launch asked for it or Home was the last screen - unless the
    /// coach has opened a game in the meantime.
    func shouldGoHomeAfterBoot(forceHomeOnLaunch: Bool, lastView: String?) -> Bool {
        allowsLateHome && (forceHomeOnLaunch || lastView == "settings")
    }
}
