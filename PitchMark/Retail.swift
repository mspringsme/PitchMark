//
//  Retail.swift
//  PitchMark
//
//  Created by Mark Springer on 12/20/25.
//
import SwiftUI
import UIKit
import StoreKit

struct StorefrontView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    private var annualPrice: String {
        subscriptionManager.annualProduct?.displayPrice ?? "$19.99"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pitcher Grid Key Inserts")
                            .font(.largeTitle.bold())
                        Text("Purchase template card inserts designed for pitcher wristbands.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section(header: Text("PitchMark Pro")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Annual Access")
                            .font(.headline)
                        Text("Unlock full grid keys, live participant connection, and the display app.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Price: \(annualPrice)/year")
                            .font(.subheadline.weight(.semibold))

                        if subscriptionManager.isPro {
                            Text("Active subscription")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Button {
                                Task { await subscriptionManager.purchaseAnnual() }
                            } label: {
                                Label("Start Pro Annual", systemImage: "crown.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Restore Purchases") {
                                Task { await subscriptionManager.restorePurchases() }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 6)
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
        .task {
            await subscriptionManager.refresh()
        }
    }
}

@ViewBuilder
var Storefront: some View {
    StorefrontView()
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
    @State private var animatePreviewWatermark: Bool = false
    private let previewHeight: CGFloat = 220

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
            ballsRows: ballsRows,
            pitchFirstColors: template.pitchFirstColors,
            locationFirstColors: template.locationFirstColors
        )
        let targetSize = CGSize(width: 900, height: 480)
        if let img = printable.renderAsPNG(size: targetSize, scale: 2.0, alignment: .top) {
            self.renderedPreview = img
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white)
                    .frame(height: previewHeight)
                    .overlay(
                        Group {
                            if let preview = renderedPreview {
                                Image(uiImage: preview)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(4)
                            } else {
                                Image(systemName: template.icon)
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    )
                    .overlay {
                        GeometryReader { proxy in
                            Text("🌧️Long Lasting💪")
                                .font(.system(size: 60, weight: .bold, design: .rounded))
                                .foregroundStyle(.black)
                                .rotationEffect(.degrees(-10))
                                .offset(
                                    x: animatePreviewWatermark ? proxy.size.width * 0.18 : -proxy.size.width * 0.18,
                                    y: animatePreviewWatermark ? -8 : 10
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                .allowsHitTesting(false)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))

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

                Text("Choose template to ship")
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
                    guard selectedTemplate != nil else { return }
                    // TODO: Hook up to StoreKit purchase using selectedTemplate info
                    // e.g., await purchase(templateId: selectedTemplate.id.uuidString)
                } label: {
                    Label("Buy for \(template.price, format: .currency(code: "USD"))", systemImage: "cart")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .padding(.top, 16)
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
            .onAppear {
                guard !animatePreviewWatermark else { return }
                withAnimation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true)) {
                    animatePreviewWatermark = true
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
