import SwiftUI
import UIKit

struct CodeDisplayOverlayView: View {
    let colorName: String
    let code: String
    var showsCloseButton: Bool = true
    let onClose: () -> Void

    private var backgroundColor: Color {
        templatePaletteColor(colorName)
    }

    private var foregroundColor: Color {
        switch colorName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "black", "blue", "red":
            return .white
        default:
            return .black
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                backgroundColor
                    .ignoresSafeArea()

                let inset: CGFloat = 16
                let availableWidth = max(120.0, proxy.size.width - (inset * 2))
                let availableHeight = max(120.0, proxy.size.height - (inset * 2))
                let characterCount = max(code.count, 1)

                let maxWidth = availableWidth * 0.98
                let maxHeight = availableHeight * 0.95
                let spacingRatio: CGFloat = 0.28
                let fitted = fitDisplayMetrics(
                    maxWidth: maxWidth,
                    maxHeight: maxHeight,
                    characterCount: characterCount,
                    spacingRatio: spacingRatio
                )

                HStack(spacing: fitted.spacing) {
                    ForEach(Array(code).map(String.init), id: \.self) { character in
                        Text(character)
                            .font(.system(size: fitted.fontSize, weight: .black, design: .monospaced))
                            .foregroundStyle(foregroundColor)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: availableWidth, maxHeight: availableHeight)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                if showsCloseButton {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(foregroundColor)
                            .padding(12)
                            .background(
                                Circle()
                                    .fill(foregroundColor.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(20)
                }
            }
        }
    }

    private struct DisplayMetrics {
        let fontSize: CGFloat
        let spacing: CGFloat
    }

    private func fitDisplayMetrics(
        maxWidth: CGFloat,
        maxHeight: CGFloat,
        characterCount: Int,
        spacingRatio: CGFloat
    ) -> DisplayMetrics {
        let count = max(characterCount, 1)
        var fontSize = maxHeight
        var spacing = max(8.0, fontSize * spacingRatio)

        let font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .black)
        let sampleWidth = "0".size(withAttributes: [.font: font]).width
        let totalWidth = (sampleWidth * CGFloat(count)) + (spacing * CGFloat(max(count - 1, 0)))

        if totalWidth > maxWidth, totalWidth > 0 {
            let scale = maxWidth / totalWidth
            fontSize = max(28.0, fontSize * scale)
            spacing = max(8.0, fontSize * spacingRatio)
        }

        return DisplayMetrics(fontSize: fontSize, spacing: spacing)
    }
}
