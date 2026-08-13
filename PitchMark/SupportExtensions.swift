import Foundation
import SwiftUI

extension View {
    func fixedAppDynamicType() -> some View {
        dynamicTypeSize(.medium)
    }

    func appConfirmationDialog(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        primaryTitle: String,
        primaryRole: AppConfirmationDialogRole = .primary,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String,
        secondaryAction: (() -> Void)? = nil
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
                secondaryAction: secondaryAction
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
