import Foundation

// Make UUID identifiable for use in SwiftUI lists/ForEach
extension UUID: Identifiable {
    public var id: UUID { self }
}

@inline(__always)
func debugLog(_ items: Any..., separator: String = " ", terminator: String = "\n") {
#if DEBUG
    Swift.print(items.map { String(describing: $0) }.joined(separator: separator), terminator: terminator)
#endif
}
