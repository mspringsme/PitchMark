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
                            .font(.title.bold())
                        Text("Purchase template card inserts designed for pitcher armbands.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section(header: Text("Grid Keys")) {
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
                            Text("Debug: isPro = true")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Debug: isPro = false")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
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
            }
            .navigationTitle("Store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Store")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
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
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var availablePitchTemplates: [PitchTemplate] = []
    @State private var selectedTemplate: PitchTemplate? = nil
    @State private var showTemplatePicker: Bool = false

    @State private var renderedPreview: UIImage? = nil
    @State private var animatePreviewWatermark: Bool = false
    @State private var customWidthInches: Double = 3.0
    @State private var customHeightInches: Double = 2.0
    private let customWidthRange = 3.0...7.0
    private let customHeightRange = 2.0...5.0

    private var widthOptions: [Double] {
        stride(from: customWidthRange.lowerBound, through: customWidthRange.upperBound, by: 0.25).map { $0 }
    }

    private var heightOptions: [Double] {
        stride(from: customHeightRange.lowerBound, through: customHeightRange.upperBound, by: 0.25).map { $0 }
    }

    private func formatInches(_ value: Double) -> String {
        let rounded = (value * 4).rounded() / 4
        let whole = Int(rounded)
        let fraction = Int((rounded - Double(whole)) * 4)
        switch fraction {
        case 1:
            return "\(whole) 1/4 in"
        case 2:
            return "\(whole) 1/2 in"
        case 3:
            return "\(whole) 3/4 in"
        default:
            return "\(whole) in"
        }
    }

    private func selectedSizeInches(for storeTemplate: StoreTemplate) -> CGSize {
        let name = storeTemplate.name.lowercased()
        if name.contains("5 x 3") {
            return CGSize(width: 5.0, height: 3.0)
        }
        if name.contains("3.5 x 2.75") {
            return CGSize(width: 3.5, height: 2.75)
        }
        if name.contains("custom") {
            return CGSize(width: customWidthInches, height: customHeightInches)
        }
        return CGSize(width: 5.0, height: 3.0)
    }

    private func generatePreviewImage(for template: PitchTemplate, storeTemplate: StoreTemplate) {
        let sizeInches = selectedSizeInches(for: storeTemplate)
        let pointsPerInch: CGFloat = 72
        let targetSize = CGSize(width: sizeInches.width * pointsPerInch,
                                height: sizeInches.height * pointsPerInch)

        let baseContentSize = PrintableEncryptedGridsView.baseContentSize(for: template.pitchGridValues)
        let outerPadding: CGFloat = 24
        let contentSize = CGSize(
            width: baseContentSize.width + (outerPadding * 2),
            height: baseContentSize.height + (outerPadding * 2)
        )
        let scaleFactor = min(targetSize.width / max(contentSize.width, 1),
                              targetSize.height / max(contentSize.height, 1))
        let textScale: CGFloat = 1.5

        let preview = PrintableEncryptedGridsView(
            grid: template.pitchGridValues,
            strikeTopRow: template.strikeTopRow,
            strikeRows: template.strikeRows,
            ballsTopRow: template.ballsTopRow,
            ballsRows: template.ballsRows,
            pitchFirstColors: template.pitchFirstColors,
            locationFirstColors: template.locationFirstColors,
            outerPadding: outerPadding,
            scale: scaleFactor,
            textScale: textScale
        )

        if let img = preview.renderAsPNG(size: targetSize, scale: 2.0, alignment: Alignment.center) {
            self.renderedPreview = img
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let sizeInches = selectedSizeInches(for: template)
                let ratio = max(sizeInches.width, 0.01) / max(sizeInches.height, 0.01)

                RoundedRectangle(cornerRadius: 12)
                    .fill(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.black.opacity(0.18), lineWidth: 1)
                    )
                    .overlay(
                        Group {
                            if let preview = renderedPreview {
                                Image(uiImage: preview)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(5)
                            } else {
                                Image(systemName: template.icon)
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    )
                    // Watermark overlay (disabled for now)
                    /*
                    .overlay {
                        GeometryReader { proxy in
                            Text("🌧️Long Lasting💪")
                                .font(.system(size: 60, weight: .bold))
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
                    */
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .aspectRatio(ratio, contentMode: .fit)
                    .frame(maxWidth: .infinity)

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
                            generatePreviewImage(for: pt, storeTemplate: template)
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
                        Text(selectedTemplate?.name ?? "Select Grid Key")
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                if template.name == "Custom" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom Size (inches)")
                            .font(.headline)

                        HStack(spacing: 12) {
                            Menu {
                                ForEach(widthOptions, id: \.self) { value in
                                    Button(formatInches(value)) {
                                        customWidthInches = value
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("Width")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(formatInches(customWidthInches))
                                        .font(.subheadline)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)

                            Menu {
                                ForEach(heightOptions, id: \.self) { value in
                                    Button(formatInches(value)) {
                                        customHeightInches = value
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("Height")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(formatInches(customHeightInches))
                                        .font(.subheadline)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

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
                            self.generatePreviewImage(for: first, storeTemplate: template)
                        } else if let current = self.selectedTemplate {
                            self.generatePreviewImage(for: current, storeTemplate: template)
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
        .background(Color(.systemGray6))
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTemplatePicker) {
            NavigationView {
                List(availablePitchTemplates) { pt in
                        Button(pt.name) { selectedTemplate = pt; generatePreviewImage(for: pt, storeTemplate: template); showTemplatePicker = false }
                }
                .navigationTitle("Select Grid Key")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showTemplatePicker = false } } }
            }
            .presentationDetents([.medium])
        }
        .onChange(of: customWidthInches) { _, _ in
            guard template.name.lowercased().contains("custom"),
                  let current = selectedTemplate else { return }
            generatePreviewImage(for: current, storeTemplate: template)
        }
        .onChange(of: customHeightInches) { _, _ in
            guard template.name.lowercased().contains("custom"),
                  let current = selectedTemplate else { return }
            generatePreviewImage(for: current, storeTemplate: template)
        }
    }
}
private struct RetailGridStaticPreview: View {
    let template: PitchTemplate
    
    private let cellW: CGFloat = 46
    private let cellH: CGFloat = 30
    private let corner: CGFloat = 6
    
    private var paletteColors: [Color] {
        var colors: [Color] = []
        let pitchColors = template.pitchFirstColors
        let locationColors = template.locationFirstColors
        for i in 0..<2 {
            if pitchColors.indices.contains(i) {
                colors.append(templatePaletteColor(pitchColors[i]))
            } else {
                colors.append(.white)
            }
        }
        for i in 0..<3 {
            if locationColors.indices.contains(i) {
                colors.append(templatePaletteColor(locationColors[i]))
            } else {
                colors.append(.white)
            }
        }
        while colors.count < 5 { colors.append(.white) }
        return colors
    }
    
    private func alnumOnlyUppercased(_ string: String) -> [Character] {
        return string.uppercased().filter { $0.isNumber || ($0.isLetter && $0.isASCII) }
    }

    private func displayText(_ raw: String) -> String {
        let cleaned = String(alnumOnlyUppercased(raw).prefix(3))
        return cleaned.map(String.init).joined(separator: "·")
    }
    
    private func cell(_ text: String, stroke: Color, bold: Bool, useInterpunct: Bool = true) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner)
                .fill(Color.white)
            RoundedRectangle(cornerRadius: corner)
                .stroke(stroke, lineWidth: 1)
            Text(useInterpunct ? displayText(text) : text)
                .font(.system(size: 17, weight: bold ? .bold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(width: cellW, height: cellH)
    }
    
    private func pitchSelectionGrid() -> some View {
        let headerRow = template.pitchGridValues.first ?? [""]
        var trimmedHeader = headerRow
        while trimmedHeader.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            trimmedHeader.removeLast()
        }
        if trimmedHeader.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "+" {
            trimmedHeader.removeLast()
        }
        let pitchCols = max(0, trimmedHeader.count - 1)
        let spacerWidth: CGFloat = 5

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                cell("", stroke: .clear, bold: false)
                Color.clear
                    .frame(width: spacerWidth, height: cellH)
                ForEach(0..<pitchCols, id: \.self) { index in
                    let value = trimmedHeader.indices.contains(index + 1) ? trimmedHeader[index + 1] : ""
                    cell(value, stroke: .black, bold: true, useInterpunct: false)
                }
            }
            ForEach(1..<min(template.pitchGridValues.count, 4), id: \.self) { row in
                HStack(spacing: 0) {
                    cell(template.pitchGridValues[row][0], stroke: .black, bold: true)
                    Color.clear
                        .frame(width: spacerWidth, height: cellH)
                    ForEach(1...pitchCols, id: \.self) { col in
                        let value = template.pitchGridValues[row].indices.contains(col) ? template.pitchGridValues[row][col] : ""
                        cell(value, stroke: .blue, bold: false)
                    }
                }
            }
        }
    }
    
    private func locationGrid(title: String, header: [String], rows: [[String]], stroke: Color) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { c in
                    cell(header.indices.contains(c) ? header[c] : "", stroke: .black, bold: true)
                }
            }
            .padding(.bottom, 5)
            ForEach(1..<4, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { c in
                        let value = rows.indices.contains(r) && rows[r].indices.contains(c) ? rows[r][c] : ""
                        if title == "Balls", r == 2, c == 1 {
                            ZStack {
                                RoundedRectangle(cornerRadius: corner)
                                    .fill(Color.green)
                                RoundedRectangle(cornerRadius: corner)
                                    .stroke(stroke, lineWidth: 1)
                            }
                            .frame(width: cellW, height: cellH)
                        } else {
                            cell(value, stroke: stroke, bold: false)
                        }
                    }
                }
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<5, id: \.self) { index in
                    if index == 2 {
                        Spacer().frame(height: 40)
                    }
                    Circle()
                        .fill(paletteColors[index])
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().stroke(Color.black, lineWidth: 1.5)
                        )
                }
            }
            .padding(.top, 32)
            .frame(width: 60, alignment: .leading)
            
            Spacer(minLength: 8)
            
            VStack(alignment: .trailing, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pitch Selection")
                        .font(.caption)
                        .foregroundColor(.black)
                        .padding(.bottom, -2)
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    pitchSelectionGrid()
                }
                .frame(height: 170)
                
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        VStack {
                            locationGrid(title: "Strikes", header: template.strikeTopRow, rows: template.strikeRows, stroke: .green)
                                .padding(.top, 8)
                            Text("Strikes")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.black)
                                .padding(.top, -2)
                        }
                        VStack {
                            locationGrid(title: "Balls", header: template.ballsTopRow, rows: template.ballsRows, stroke: .red)
                                .padding(.top, 8)
                            Text("Balls")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.black)
                                .padding(.top, -2)
                        }
                    }
                }
            }
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }
    
    static func baseContentSize(for template: PitchTemplate) -> CGSize {
        let cellW: CGFloat = 46
        let cellH: CGFloat = 30
        let paletteWidth: CGFloat = 60
        let spacerWidth: CGFloat = 8
        let trailingPadding: CGFloat = 12
        let topGridHeight: CGFloat = 170
        let strikesGridWidth: CGFloat = cellW * 3
        let strikesGridHeight: CGFloat = (cellH * 4) + 5 + 8 + UIFont.systemFont(ofSize: 15, weight: .semibold).lineHeight - 2
        let bottomBlockHeight = strikesGridHeight + 4
        
        let headerRow = template.pitchGridValues.first ?? [""]
        let lastIsPlus = headerRow.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "+"
        let pitchCols = max(0, headerRow.count - 1 - (lastIsPlus ? 1 : 0))
        let topGridWidth = (cellW * CGFloat(max(1, pitchCols + 1))) + 5
        
        let rightWidth = max(topGridWidth, (strikesGridWidth * 2) + 6)
        let rightHeight = topGridHeight + bottomBlockHeight
        
        let paletteCircleCount: CGFloat = 5
        let paletteCircleSize: CGFloat = 22
        let paletteGapCount: CGFloat = 3
        let paletteGapSize: CGFloat = 12
        let paletteTopPadding: CGFloat = 32
        let paletteMiddleSpacer: CGFloat = 40
        let paletteHeight: CGFloat = paletteTopPadding
            + (paletteCircleSize * paletteCircleCount)
            + (paletteGapSize * paletteGapCount)
            + paletteMiddleSpacer
        let totalWidth = paletteWidth + spacerWidth + rightWidth + trailingPadding
        let totalHeight = max(paletteHeight, rightHeight)
        return CGSize(width: totalWidth, height: totalHeight)
    }
}
