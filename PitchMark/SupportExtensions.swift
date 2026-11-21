import Foundation
import SwiftUI

// MARK: - Sheets (2026-11-20)

/// How a sheet is made easy to close. Every sheet in the app goes through
/// `appSheet` (a source-reading test refuses a plain `.sheet(`):
/// - `.closeButton` (default): a visible drag handle, a top margin, and a
///   44 pt ✕ at the top right - for sheets with no navigation bar.
/// - `.handle`: drag handle + top margin only - for sheets whose content
///   has its own navigation bar (its Cancel/Close stays the button), or
///   that manage closing themselves (the Pro paywall).
/// - `.none`: untouched - Apple's own share sheet and pickers (they have
///   their own Cancel), and sheets that must not be swiped away
///   (`interactiveDismissDisabled`, e.g. the review sheet, whose Save is
///   placed at an exact screen height - a margin would move it).
enum AppSheetChromeStyle {
    case closeButton
    case handle
    case none
}

enum AppSheetChromeMetrics {
    /// Space above the content, under the drag handle.
    static let topMargin: CGFloat = 14
    /// The close button's tap area. 48, not Apple's 44 minimum: iOS draws
    /// partial-height sheets slightly scaled down (measured 0.96 on an
    /// iPhone 17), which took a 44 pt button to 42 on screen.
    static let closeTapSize: CGFloat = 48
}

struct AppSheetChrome: ViewModifier {
    let style: AppSheetChromeStyle
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        switch style {
        case .none:
            content
        case .handle:
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: AppSheetChromeMetrics.topMargin)
                }
                .presentationDragIndicator(.visible)
        case .closeButton:
            // The ✕ floats in the top-right corner instead of taking a row:
            // many sheets are a fixed height (fraction detents), and a row
            // pushed their content up past the top edge.
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: AppSheetChromeMetrics.topMargin)
                }
                .overlay(alignment: .topTrailing) {
                    AppSheetCloseButton { dismiss() }
                        .padding(.top, 2)
                        .padding(.trailing, 6)
                }
                .presentationDragIndicator(.visible)
        }
    }
}

/// The ✕ every bare sheet gets: a 30 pt circle in a 48 pt tap area.
struct AppSheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color(.tertiarySystemFill)))
                .frame(width: AppSheetChromeMetrics.closeTapSize, height: AppSheetChromeMetrics.closeTapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .accessibilityIdentifier("sheet.close")
    }
}

extension View {
    /// `.sheet(isPresented:)` with the app's close chrome.
    func appSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        chrome: AppSheetChromeStyle = .closeButton,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            content().modifier(AppSheetChrome(style: chrome))
        }
    }

    /// `.sheet(item:)` with the app's close chrome.
    func appSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        chrome: AppSheetChromeStyle = .closeButton,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { item in
            content(item).modifier(AppSheetChrome(style: chrome))
        }
    }
}

extension View {
    func fixedAppDynamicType() -> some View {
        dynamicTypeSize(.medium)
    }

    /// The rounded-rectangle "card" look shared by Moment grid cells and
    /// Folder/Bucket tiles - a thin border around the whole tile
    /// (thumbnail + text together), not just the thumbnail's own corners.
    func momentCardStyle() -> some View {
        background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
    }

    func appConfirmationDialog(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        primaryTitle: String,
        primaryRole: AppConfirmationDialogRole = .primary,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String,
        secondaryAction: (() -> Void)? = nil,
        alternateTitle: String? = nil,
        alternateRole: AppConfirmationDialogRole = .primary,
        alternateAction: (() -> Void)? = nil
    ) -> some View {
        modifier(
            AppConfirmationDialogModifier(
                isPresented: isPresented,
                title: title,
                message: message,
                primaryTitle: primaryTitle,
                primaryRole: primaryRole,
                primaryAction: primaryAction,
                secondaryTitle: secondaryTitle,
                secondaryAction: secondaryAction,
                alternateTitle: alternateTitle,
                alternateRole: alternateRole,
                alternateAction: alternateAction
            )
        )
    }
}

enum AppConfirmationDialogRole {
    case primary
    case destructive
}

private struct AppConfirmationDialogModifier: ViewModifier {
    @Binding var isPresented: Bool

    let title: String
    let message: String
    let primaryTitle: String
    let primaryRole: AppConfirmationDialogRole
    let primaryAction: () -> Void
    let secondaryTitle: String
    let secondaryAction: (() -> Void)?
    /// Optional second choice, drawn between primary and cancel - for
    /// dialogs that need two ways to proceed (e.g. archive keeping stats
    /// vs. archive removing them).
    let alternateTitle: String?
    let alternateRole: AppConfirmationDialogRole
    let alternateAction: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    ZStack {
                        Color.black.opacity(0.28)
                            .ignoresSafeArea()
                            .onTapGesture {
                                dismissSecondary()
                            }

                        VStack(alignment: .leading, spacing: 18) {
                            Text(title)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.primary)

                            Text(message)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            VStack(spacing: 10) {
                                Button {
                                    isPresented = false
                                    primaryAction()
                                } label: {
                                    Text(primaryTitle)
                                        .font(.headline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(primaryRole == .destructive ? .red : .primary)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                                if let alternateTitle {
                                    Button {
                                        isPresented = false
                                        alternateAction?()
                                    } label: {
                                        Text(alternateTitle)
                                            .font(.headline.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(alternateRole == .destructive ? .red : .primary)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }

                                Button {
                                    dismissSecondary()
                                } label: {
                                    Text(secondaryTitle)
                                        .font(.headline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.primary)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 340)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Color.white.opacity(0.45), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
                        .padding(.horizontal, 24)
                    }
                    // Fill the full screen regardless of the view this overlay is attached to,
                    // so the dialog isn't squeezed when hosted on a small view (e.g. a Button)
                    // or when the keyboard is visible and reduces the sheet's available height.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .fixedAppDynamicType()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(1000)
                }
            }
            .animation(.easeInOut(duration: 0.16), value: isPresented)
    }

    private func dismissSecondary() {
        isPresented = false
        secondaryAction?()
    }
}

extension Color {
    /// The app's neutral "active/selected" color for controls that would
    /// otherwise default to the system blue link/accent color - e.g. the
    /// capsule selectors and the Moments record button. Use this instead of
    /// `Color.accentColor` / `.blue` for new UI unless specifically told to
    /// use the accent color.
    static let pitchMarkActiveGray = Color(white: 0.3)
}

/// A compact alternative to `.pickerStyle(.segmented)` that hugs its content
/// instead of stretching to the container width, for spots where the default
/// segmented look reads as visually bland against the rest of the screen.
struct CapsuleSegmentedControl<Value: Hashable>: View {
    let options: [(title: String, value: Value)]
    @Binding var selection: Value
    var segmentMinWidth: CGFloat = 84

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: segmentMinWidth)
                        .padding(.vertical, 6)
                        .foregroundStyle(selection == option.value ? Color.white : Color.primary)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selection == option.value ? Color.pitchMarkActiveGray : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule(style: .continuous).fill(Color(.systemGray5)))
        .overlay(Capsule(style: .continuous).stroke(Color(.systemGray4), lineWidth: 1))
    }
}

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

/// `error.localizedDescription` alone is often just a generic wrapper
/// string ("The operation could not be completed.") for AVFoundation
/// failures - the actual cause usually sits one level down, in the
/// NSError's own `domain`/`code` or an `NSUnderlyingErrorKey` chain that
/// `localizedDescription` doesn't surface. Use this in a `debugLog` call
/// at any export/composition failure site instead of just the bare
/// error, so a future report ("export failed, red error") comes with
/// something more actionable in the console than the same generic text
/// already shown on screen.
func debugErrorDetail(_ error: Error) -> String {
    let nsError = error as NSError
    var parts = ["\(nsError.domain) #\(nsError.code): \(nsError.localizedDescription)"]
    var underlying: Error? = nsError.userInfo[NSUnderlyingErrorKey] as? Error
    while let current = underlying as NSError? {
        parts.append("<- \(current.domain) #\(current.code): \(current.localizedDescription)")
        underlying = current.userInfo[NSUnderlyingErrorKey] as? Error
    }
    return parts.joined(separator: " ")
}
