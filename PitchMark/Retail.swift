//
//  Retail.swift
//  PitchMark
//
//  Created by Mark Springer on 12/20/25.
//
import SwiftUI
import UIKit

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
    .init(name: "5 x 3 in.", subtitle: "4 inserts; 2 thicknesses (8 cards), Waterproof", icon: "squareshape.split.3x3", price: 12),
    .init(name: "3.5 x 2.75 in.", subtitle: "4 inserts; 2 thicknesses (8 cards)", icon: "squareshape.split.3x3", price: 12),
    .init(name: "Custom", subtitle: "4 inserts; 2 thicknesses (8 cards)", icon: "squareshape.split.3x3", price: 14)
]

// MARK: - Detail View

private struct TemplateDetailView: View {
    let template: StoreTemplate
    
    @EnvironmentObject var authManager: AuthManager
    @State private var availablePitchTemplates: [PitchTemplate] = []
    @State private var selectedTemplate: PitchTemplate? = nil
    @State private var showTemplatePicker: Bool = false

    @State private var renderedPreview: UIImage? = nil

    private func generatePreviewImage(for template: PitchTemplate) {
        // Build a printable view of the encrypted grids using the chosen template
        // Note: We assume PitchTemplate provides the necessary data to build the grid.
        // If your app requires fetching or computing the grid from the template, do that here.
        // For now, we call into a shared rendering utility if available, or reconstruct similarly to TemplateEditorView.

        // If your project has a utility to get headers/grid from a PitchTemplate, replace the placeholders below.
        let strikeTop = template.strikeTopRow
        let strikeRows = template.strikeRows
        let ballsTop = template.ballsTopRow
        let ballsRows = template.ballsRows
        let grid = template.pitchGridValues

        let printable = PrintableEncryptedGridsView(
            grid: grid,
            strikeTopRow: strikeTop,
            strikeRows: strikeRows,
            ballsTopRow: ballsTop,
            ballsRows: ballsRows
        )
        let targetSize = CGSize(width: 612, height: 792)
        if let img = printable.renderAsPNG(size: targetSize, scale: 2.0) {
            self.renderedPreview = img
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.gray.opacity(0.12))
                    .frame(height: 180)
                    .overlay(
                        Group {
                            if let preview = renderedPreview {
                                Image(uiImage: preview)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(8)
                            } else {
                                Image(systemName: template.icon)
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    )

                Text(template.name)
                    .font(.title.bold())
                Text(template.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                Text("What you get")
                    .font(.headline)
                Text("• 8 waterproof templates")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Choose template to encrypt")
                    .font(.headline)

                Menu {
                    ForEach(availablePitchTemplates) { pt in
                        Button {
                            selectedTemplate = pt
                            generatePreviewImage(for: pt)
                        } label: {
                            HStack {
                                Text(pt.name)
                                if selectedTemplate?.id == pt.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    if !availablePitchTemplates.isEmpty {
                        Divider()
                    }
                    Button("Manage in Settings…") { showTemplatePicker = true }
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text(selectedTemplate?.name ?? "Select template")
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                Button {
                    // Ensure a PitchTemplate is selected before purchase
                    guard let chosenTemplate = selectedTemplate else { return }
                    // TODO: Hook up to StoreKit purchase using chosenTemplate info
                    // e.g., await purchase(templateId: chosenTemplate.id.uuidString)
                } label: {
                    Label("Buy for \(template.price, format: .currency(code: "USD"))", systemImage: "cart")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .task {
                // Load user templates once when entering detail
                authManager.loadTemplates { templates in
                    DispatchQueue.main.async {
                        self.availablePitchTemplates = templates
                        if self.selectedTemplate == nil, let first = templates.first {
                            self.selectedTemplate = first
                            self.generatePreviewImage(for: first)
                        } else if let current = self.selectedTemplate {
                            self.generatePreviewImage(for: current)
                        }
                    }
                }
            }
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTemplatePicker) {
            NavigationView {
                List(availablePitchTemplates) { pt in
                    Button(pt.name) { selectedTemplate = pt; generatePreviewImage(for: pt); showTemplatePicker = false }
                }
                .navigationTitle("Select Template")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showTemplatePicker = false } } }
            }
            .presentationDetents([.medium])
        }
    }
}

