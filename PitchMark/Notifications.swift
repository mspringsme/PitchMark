import Foundation

extension Notification.Name {
    // Fired when a pitch color override is saved in the color picker
    static let pitchColorDidChange = Notification.Name("pitchColorDidChange")

    // Fired when the jersey order (lineup) changes via drag/drop or move actions
    static let jerseyOrderChanged = Notification.Name("jerseyOrderChanged")

    // Fired when a game session is chosen from a sheet
    static let gameOrSessionChosen = Notification.Name("gameOrSessionChosen")

    // Fired when a game session is deleted
    static let gameOrSessionDeleted = Notification.Name("gameOrSessionDeleted")

    // Fired to request that progress be reset for a given session (or general)
    static let practiceProgressReset = Notification.Name("practiceProgressReset")

    // Fired when the selected template changes (e.g., from SettingsView)
    static let templateSelectionDidChange = Notification.Name("templateSelectionDidChange")

    // Fired when pitcher sharing/ownership updates should refresh UI
    static let pitcherSharedUpdated = Notification.Name("pitcherSharedUpdated")

    // Fired when a local pitcher portrait is saved or removed
    static let pitcherPortraitDidChange = Notification.Name("pitcherPortraitDidChange")

    // Fired to close the display-only window
    static let displayOnlyExitRequested = Notification.Name("displayOnlyExitRequested")

    // Fired to present the display-only full-screen view
    static let displayOnlyPresentRequested = Notification.Name("displayOnlyPresentRequested")

    // Fired after Stripe returns from a successful retail checkout
    static let retailCheckoutSucceeded = Notification.Name("retailCheckoutSucceeded")
}
