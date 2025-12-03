import Foundation

// Global notifications used across the app
extension Notification.Name {
    static let jerseyOrderChanged = Notification.Name("jerseyOrderChanged")
    static let pitchColorDidChange = Notification.Name("pitchColorDidChange")
}

// Make UUID identifiable for use in SwiftUI lists/ForEach
extension UUID: Identifiable {
    public var id: UUID { self }
}
