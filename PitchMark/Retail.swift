//
//  Retail.swift
//  PitchMark
//
//  Created by Mark Springer on 12/20/25.
//
import SwiftUI

@ViewBuilder
var Storefront: some View {
    NavigationStack {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pitcher Wristband Inserts")
                        .font(.largeTitle.bold())
                    Text("Browse and purchase printable template card inserts designed for pitcher wristbands.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section(header: Text("Templates")) {
                ForEach(sampleTemplates) { template in
                    NavigationLink(value: template) {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.gray.opacity(0.15))
                                .frame(width: 56, height: 56)
                                .overlay(
                                    Image(systemName: template.icon)
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name)
                                    .font(.headline)
                                Text(template.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(template.price, format: .currency(code: "USD"))
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Store")
        .navigationDestination(for: StoreTemplate.self) { template in
            TemplateDetailView(template: template)
        }
    }
}

// MARK: - Models used by Storefront
private struct StoreTemplate: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let subtitle: String
    let icon: String
    let price: Decimal
}

private let sampleTemplates: [StoreTemplate] = [
    .init(name: "Classic 3-Column", subtitle: "Balanced pitch call layout", icon: "square.grid.3x2", price: 2.99),
    .init(name: "Quick Call Compact", subtitle: "High-density compact format", icon: "rectangle.split.3x1", price: 1.99),
    .init(name: "Big Type", subtitle: "Large type for easy reading", icon: "textformat.size", price: 2.49)
]

// MARK: - Detail View

private struct TemplateDetailView: View {
    let template: StoreTemplate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.gray.opacity(0.12))
                    .frame(height: 180)
                    .overlay(
                        Image(systemName: template.icon)
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    )

                Text(template.name)
                    .font(.title.bold())
                Text(template.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                Text("What you get")
                    .font(.headline)
                Text("• Printable PDF template\n• Standard and large wristband sizes\n• Usage guide and tips")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    // TODO: Hook up to StoreKit product purchase
                } label: {
                    Label("Buy for \(template.price, format: .currency(code: "USD"))", systemImage: "cart")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

