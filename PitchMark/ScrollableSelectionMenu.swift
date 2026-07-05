import SwiftUI
import UIKit

struct SelectionSheetAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String?
    let role: ButtonRole?
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }
}

struct ScrollableSelectionMenuButton<Item: Identifiable, Label: View>: View {
    let title: String
    let items: [Item]
    let topActions: [SelectionSheetAction]
    let itemTitle: (Item) -> String
    let isSelected: (Item) -> Bool
    let onSelect: (Item) -> Void
    let label: () -> Label

    @State private var isPresented = false

    init(
        title: String,
        items: [Item],
        topActions: [SelectionSheetAction] = [],
        itemTitle: @escaping (Item) -> String,
        isSelected: @escaping (Item) -> Bool,
        onSelect: @escaping (Item) -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.title = title
        self.items = items
        self.topActions = topActions
        self.itemTitle = itemTitle
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.label = label
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label()
        }
        .sheet(isPresented: $isPresented) {
            ScrollableSelectionSheet(
                title: title,
                items: items,
                topActions: topActions,
                itemTitle: itemTitle,
                isSelected: isSelected,
                onSelect: onSelect
            )
        }
    }
}

private struct ScrollableSelectionSheet<Item: Identifiable>: View {
    let title: String
    let items: [Item]
    let topActions: [SelectionSheetAction]
    let itemTitle: (Item) -> String
    let isSelected: (Item) -> Bool
    let onSelect: (Item) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !topActions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(topActions) { action in
                                Button(role: action.role) {
                                    action.action()
                                    dismiss()
                                } label: {
                                    selectionRow(
                                        title: action.title,
                                        systemImage: action.systemImage,
                                        isSelected: false
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if items.isEmpty {
                        Text("No options available.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(items) { item in
                                Button {
                                    onSelect(item)
                                    dismiss()
                                } label: {
                                    selectionRow(
                                        title: itemTitle(item),
                                        systemImage: isSelected(item) ? "checkmark" : nil,
                                        isSelected: isSelected(item)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func selectionRow(title: String, systemImage: String?, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}
