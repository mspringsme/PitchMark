import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// NOTE: We intentionally avoid `brandBackground` here because Xcode generates that symbol
// from the asset catalog (GeneratedAssetSymbols.swift). Use `appBrandBackground` throughout
// the app to prevent symbol collisions while still falling back gracefully if the asset
// isn't available at runtime.
extension Color {
    /// App brand background color loaded from the asset catalog as "BrandBackground".
    /// Falls back to a soft system color if the asset isn't found.
    static var appBrandBackground: Color {
        #if canImport(UIKit)
        if let uiColor = UIColor(named: "BrandBackground") {
            return Color(uiColor)
        }
        return Color(.secondarySystemBackground)
        #else
        return Color("BrandBackground")
        #endif
    }
}
