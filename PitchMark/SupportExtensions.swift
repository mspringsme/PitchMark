import Foundation

// Make UUID identifiable for use in SwiftUI lists/ForEach
extension UUID: Identifiable {
    public var id: UUID { self }
}
