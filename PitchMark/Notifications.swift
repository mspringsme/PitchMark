import Foundation

extension Notification.Name {
    // Fired when a pitch color override is saved in the color picker
    static let pitchColorDidChange = Notification.Name("pitchColorDidChange")

    // Fired when the jersey order (lineup) changes via drag/drop or move actions
    static let jerseyOrderChanged = Notification.Name("jerseyOrderChanged")

    // Fired when a game or practice session is chosen from a sheet
    static let gameOrSessionChosen = Notification.Name("gameOrSessionChosen")

    // Fired when a game or practice session is deleted
    static let gameOrSessionDeleted = Notification.Name("gameOrSessionDeleted")

    // Fired to request that practice progress be reset for a given session (or general)
    static let practiceProgressReset = Notification.Name("practiceProgressReset")
}
