//
//  HomeAreaTabBar.swift
//  PitchMark
//
//  Originally Phase 2, step 2 of the Coach/Parent/Family direction
//  (2026-09-24): a persistent bottom bar for jumping between
//  Home/Games/Moments/Family, paired with a sheet-chaining hack, so as not
//  to touch PitchTrackerView's root/boot logic. Superseded (2026-10-09) by
//  making Home/Games/Moments/Family real TabView siblings in
//  PitchTrackerView's body - the HomeAreaTabBar view and the
//  ComingSoonSheetView placeholder it powered are gone; this enum is the
//  one piece that's still load-bearing (TabView's selection tag and every
//  onSwitchToArea callback). Deliberately kept out of the Pitchmark Display
//  target's membershipExceptions; Display has no use for this.
//

import SwiftUI

enum HomeArea: Identifiable {
    case games
    case home
    case moments

    var id: Self { self }

    var title: String {
        switch self {
        // Singular: the tab shows the ONE game currently open in the
        // tracker, not a list of games - that list lives in Home's Games
        // section. The plural read as a second browser and sent people
        // looking for the game chooser here.
        case .games: return "Game"
        case .home: return "Home"
        case .moments: return "Moments"
        }
    }

    var systemImage: String {
        switch self {
        case .games: return "figure.baseball"
        case .home: return "house.fill"
        case .moments: return "video.fill"
        }
    }
}
