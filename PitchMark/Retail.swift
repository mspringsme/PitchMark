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
                Section(header: Text("Pitcher Grid Key Inserts")) {
                    Text("Armband grid key inserts; Master pitch call sheet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))

                    ForEach(gridKeyTemplates) { template in
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

                    ForEach(printableSheetTemplates) { template in
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
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("PitchMark Store")
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.top, -20)
                }
            }

            .navigationDestination(for: StoreTemplate.self) { template in
                switch template.kind {
                case .gridKey:
                    TemplateDetailView(template: template)
                case .printableSheet:
                    PrintableSheetDetailView(template: template)
                }
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

struct StorefrontView_Previews: PreviewProvider {
    static var previews: some View {
        StorefrontView()
            .environmentObject(SubscriptionManager())
    }
}

// MARK: - Models used by Storefront
private enum StoreItemKind: Hashable {
    case gridKey
    case printableSheet
}

private struct StoreTemplate: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let subtitle: String
    let icon: String
    let price: Decimal
    let kind: StoreItemKind
}

private let gridKeyTemplates: [StoreTemplate] = [
    .init(name: "5 x 3 in.", subtitle: "4 inserts; 2 thicknesses (8 cards), Waterproof", icon: "squareshape.split.3x3", price: 12, kind: .gridKey),
    .init(name: "3.5 x 2.75 in.", subtitle: "4 inserts; 2 thicknesses (8 cards)", icon: "squareshape.split.3x3", price: 12, kind: .gridKey),
    .init(name: "Custom", subtitle: "4 inserts; 2 thicknesses (8 cards)", icon: "squareshape.split.3x3", price: 14, kind: .gridKey)
]

private let printableSheetTemplates: [StoreTemplate] = [
    .init(name: "Printable Sheet (8.5 x 11)", subtitle: "Strikes on one side, Balls on the other (2 copies)", icon: "doc.plaintext", price: 12, kind: .printableSheet)
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

private struct PrintableLocation: Identifiable {
    let id = UUID()
    let title: String
    let assetName: String
    let gridKind: EncryptedGridKind
    let row: Int
    let col: Int
}

private let strikePrintableLocations: [PrintableLocation] = [
    .init(title: "Strike High Left", assetName: "Strike High Left_Inside_Lefty", gridKind: .strikes, row: 0, col: 0),
    .init(title: "Strike High", assetName: "Strike High", gridKind: .strikes, row: 0, col: 1),
    .init(title: "Strike High Right", assetName: "Strike High Right_Outside_Lefty", gridKind: .strikes, row: 0, col: 2),
    .init(title: "Strike Left", assetName: "Strike Left_Inside_Lefty", gridKind: .strikes, row: 1, col: 0),
    .init(title: "Strike Middle", assetName: "Strike Middle", gridKind: .strikes, row: 1, col: 1),
    .init(title: "Strike Right", assetName: "Strike Right_Outside_Lefty", gridKind: .strikes, row: 1, col: 2),
    .init(title: "Strike Low Left", assetName: "Strike Low Left_Inside_Lefty", gridKind: .strikes, row: 2, col: 0),
    .init(title: "Strike Low", assetName: "Strike Low", gridKind: .strikes, row: 2, col: 1),
    .init(title: "Strike Low Right", assetName: "Strike Low Right_Outside_Lefty", gridKind: .strikes, row: 2, col: 2)
]

private let ballPrintableLocations: [PrintableLocation] = [
    .init(title: "Ball High Left", assetName: "Ball High Left_Inside_Lefty", gridKind: .balls, row: 0, col: 0),
    .init(title: "Ball High", assetName: "Ball High", gridKind: .balls, row: 0, col: 1),
    .init(title: "Ball High Right", assetName: "Ball High Right_Outside_Lefty", gridKind: .balls, row: 0, col: 2),
    .init(title: "Ball Left", assetName: "Ball Left_Inside_Lefty", gridKind: .balls, row: 1, col: 0),
    .init(title: "Ball Right", assetName: "Ball Right_Outside_Lefty", gridKind: .balls, row: 1, col: 2),
    .init(title: "Ball Low Left", assetName: "Ball Low Left_Inside_Lefty", gridKind: .balls, row: 2, col: 0),
    .init(title: "Ball Low", assetName: "Ball Low", gridKind: .balls, row: 2, col: 1),
    .init(title: "Ball Low Right", assetName: "Ball Low Right_Outside_Lefty", gridKind: .balls, row: 2, col: 2)
]

private struct PrintableLocationSheetView: View {
    let template: PitchTemplate
    let title: String
    let locations: [PrintableLocation]

    private let pagePadding: CGFloat = 24
    private let blockSpacing: CGFloat = 14
    private let imageTableGap: CGFloat = 4
    private let columnCount = 6
    private let columnSpacing: CGFloat = 12

    private var pitchNames: [String] {
        let fromHeaders = template.pitchGridHeaders
            .map { $0.pitch.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !fromHeaders.isEmpty { return fromHeaders }
        return template.pitches.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private var pitchFirstColors: [Color] {
        let colors = template.pitchFirstColors.map { templatePaletteColor($0) }
        return Array(colors.prefix(2))
    }

    private var locationFirstColors: [Color] {
        let colors = template.locationFirstColors.map { templatePaletteColor($0) }
        return Array(colors.prefix(3))
    }

    private func sanitizeAlnum(_ value: String) -> String {
        return value.uppercased().filter { $0.isNumber || ($0.isLetter && $0.isASCII) }
    }

    private func sanitizedTemplateForCodes(_ template: PitchTemplate) -> PitchTemplate {
        var copy = template
        copy.pitchGridValues = template.pitchGridValues.map { row in
            row.map { sanitizeAlnum($0) }
        }
        copy.strikeTopRow = template.strikeTopRow.map { sanitizeAlnum($0) }
        copy.ballsTopRow = template.ballsTopRow.map { sanitizeAlnum($0) }
        copy.strikeRows = template.strikeRows.map { row in
            row.map { sanitizeAlnum($0) }
        }
        copy.ballsRows = template.ballsRows.map { row in
            row.map { sanitizeAlnum($0) }
        }
        return copy
    }

    private func formatCode(_ code: String) -> String {
        let cleaned = sanitizeAlnum(code)
        let chars = Array(cleaned)
        guard chars.count >= 4 else { return cleaned }
        return String(chars[0...1]) + "·" + String(chars[2...3])
    }

    private func codes(for pitch: String, location: PrintableLocation) -> [String] {
        let cleanTemplate = sanitizedTemplateForCodes(template)
        let allCodes = EncryptedCodeGenerator.generateCalls(
            template: cleanTemplate,
            selectedPitch: pitch,
            gridKind: location.gridKind,
            columnIndex: location.col,
            rowIndex: location.row
        )
        let trimmed = Array(allCodes.prefix(columnCount)).map { formatCode($0) }
        if trimmed.count >= columnCount { return trimmed }
        return trimmed + Array(repeating: "", count: columnCount - trimmed.count)
    }

    var body: some View {
        GeometryReader { proxy in
            let headerHeight: CGFloat = 62
            let availableHeight = proxy.size.height - (pagePadding * 2) - headerHeight
            let columns = locations.chunked(into: 2)
            let leftColumn = columns.first ?? []
            let rightColumn = columns.count > 1 ? columns[1] : []
            let maxRows = max(leftColumn.count, rightColumn.count, 1)
            let blockHeight = (availableHeight - (blockSpacing * CGFloat(maxRows - 1))) / CGFloat(maxRows)
            let columnWidth = (proxy.size.width - (pagePadding * 2) - columnSpacing) / 2
            let imageSize = min(blockHeight * 0.7, columnWidth * 0.14, 40)
            let rawTableWidth = columnWidth - imageSize - imageTableGap
            let tableWidth = max(0, rawTableWidth)
            let pitchColumnWidth: CGFloat = min(52, max(40, tableWidth * 0.18))
            let availableForCodes = max(0, tableWidth - pitchColumnWidth)
            let codeColumnWidth = availableForCodes / CGFloat(columnCount)
            let rowCount = max(pitchNames.count + 1, 2)
            let rowHeight = max(16, blockHeight / CGFloat(rowCount))

            VStack(alignment: .leading, spacing: blockSpacing) {
                HStack(spacing: 12) {
                    Text(template.name)
                        .font(.system(size: 16, weight: .semibold))

                    Spacer(minLength: 0)

                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Image("Pitch Location code Key")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 16)
                    HStack(spacing: 6) {
                        Text("Pitch first:")
                            .font(.system(size: 11, weight: .semibold))
                        ForEach(pitchFirstColors.indices, id: \.self) { index in
                            Circle()
                                .fill(pitchFirstColors[index])
                                .frame(width: 9, height: 9)
                                .overlay(Circle().stroke(Color.black, lineWidth: 0.8))
                        }
                    }
                    HStack(spacing: 6) {
                        Text("Location first:")
                            .font(.system(size: 11, weight: .semibold))
                        ForEach(locationFirstColors.indices, id: \.self) { index in
                            Circle()
                                .fill(locationFirstColors[index])
                                .frame(width: 9, height: 9)
                                .overlay(Circle().stroke(Color.black, lineWidth: 0.8))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 6)

                HStack(alignment: .top, spacing: columnSpacing) {
                    VStack(alignment: .leading, spacing: blockSpacing) {
                        ForEach(leftColumn) { location in
                            locationBlock(
                                location: location,
                                imageSize: imageSize,
                                tableWidth: tableWidth,
                                pitchColumnWidth: pitchColumnWidth,
                                codeColumnWidth: codeColumnWidth,
                                rowHeight: rowHeight
                            )
                        }
                    }
                    VStack(alignment: .leading, spacing: blockSpacing) {
                        ForEach(rightColumn) { location in
                            locationBlock(
                                location: location,
                                imageSize: imageSize,
                                tableWidth: tableWidth,
                                pitchColumnWidth: pitchColumnWidth,
                                codeColumnWidth: codeColumnWidth,
                                rowHeight: rowHeight
                            )
                        }
                    }
                }
            }
            .padding(pagePadding)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(Color.white)
            .foregroundColor(.black)
        }
    }

    private func locationBlock(
        location: PrintableLocation,
        imageSize: CGFloat,
        tableWidth: CGFloat,
        pitchColumnWidth: CGFloat,
        codeColumnWidth: CGFloat,
        rowHeight: CGFloat
    ) -> some View {
        HStack(alignment: .center, spacing: imageTableGap) {
            Image(location.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: imageSize, height: imageSize)

            VStack(spacing: 0) {
                ForEach(pitchNames, id: \.self) { pitch in
                    let codes = codes(for: pitch, location: location)
                    HStack(spacing: 0) {
                        printableCell(text: pitch, width: pitchColumnWidth, height: rowHeight, bold: false)
                        ForEach(0..<columnCount, id: \.self) { index in
                            printableCell(text: codes[index], width: codeColumnWidth, height: rowHeight, bold: false)
                        }
                    }
                }
            }
            .frame(width: tableWidth)
        }
    }

    private func printableCell(text: String, width: CGFloat, height: CGFloat, bold: Bool) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white)
            Rectangle()
                .stroke(Color.black, lineWidth: 1)
            Text(text)
                .font(.system(size: 11, weight: bold ? .semibold : .regular, design: .monospaced))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 2)
        }
        .frame(width: width, height: height)
    }
}

private struct PrintableSheetDetailView: View {
    let template: StoreTemplate

    @EnvironmentObject var authManager: AuthManager
    @State private var availablePitchTemplates: [PitchTemplate] = []
    @State private var selectedTemplate: PitchTemplate? = nil
    @State private var showTemplatePicker = false
    @State private var selectedPageIndex = 0

    @State private var strikesPreview: UIImage? = nil
    @State private var ballsPreview: UIImage? = nil
    @State private var pdfURL: URL? = nil
    @State private var showShareSheet = false

    private let letterSize = CGSize(width: 612, height: 792)

    private func renderPrintableSheet(for template: PitchTemplate) {
        let strikesView = PrintableLocationSheetView(
            template: template,
            title: "Strikes",
            locations: strikePrintableLocations
        )
        let ballsView = PrintableLocationSheetView(
            template: template,
            title: "Balls",
            locations: ballPrintableLocations
        )

        strikesPreview = strikesView.renderAsPNG(size: letterSize, scale: 2.0, alignment: Alignment.center)
        ballsPreview = ballsView.renderAsPNG(size: letterSize, scale: 2.0, alignment: Alignment.center)
    }

    private func buildPDFURL() -> URL? {
        guard let strikesImage = strikesPreview, let ballsImage = ballsPreview else { return nil }
        let filename = "PitchMark_PrintableSheet.pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: letterSize))
        do {
            try renderer.writePDF(to: url, withActions: { context in
                context.beginPage()
                strikesImage.draw(in: CGRect(origin: .zero, size: letterSize))
                context.beginPage()
                ballsImage.draw(in: CGRect(origin: .zero, size: letterSize))
            })
            return url
        } catch {
            return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Page", selection: $selectedPageIndex) {
                    Text("Strikes").tag(0)
                    Text("Balls").tag(1)
                }
                .pickerStyle(.segmented)

                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.black.opacity(0.18), lineWidth: 1)
                    )
                    .overlay(
                        Group {
                            if selectedPageIndex == 0, let preview = strikesPreview {
                                Image(uiImage: preview)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(6)
                            } else if selectedPageIndex == 1, let preview = ballsPreview {
                                Image(uiImage: preview)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(6)
                            } else {
                                ProgressView()
                            }
                        }
                    )
                    .aspectRatio(letterSize.width / letterSize.height, contentMode: .fit)
                    .frame(maxWidth: .infinity)

                Text(template.name)
                    .font(.title.bold())
                Text(template.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                Text("Choose template to ship")
                    .font(.headline)

                Menu {
                    ForEach(availablePitchTemplates) { pt in
                        Button {
                            selectedTemplate = pt
                            renderPrintableSheet(for: pt)
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

                Button {
                    if let current = selectedTemplate {
                        renderPrintableSheet(for: current)
                    }
                    if let url = buildPDFURL() {
                        pdfURL = url
                        showShareSheet = true
                    }
                } label: {
                    Label("Download PDF (Preview)", systemImage: "arrow.down.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    guard selectedTemplate != nil else { return }
                    // TODO: Hook up to StoreKit purchase for printable sheet
                } label: {
                    Label("Buy for \(template.price, format: .currency(code: "USD"))", systemImage: "cart")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .padding(.top, 16)
            .task {
                authManager.loadTemplates { templates in
                    DispatchQueue.main.async {
                        self.availablePitchTemplates = templates
                        if self.selectedTemplate == nil, let first = templates.first {
                            self.selectedTemplate = first
                            self.renderPrintableSheet(for: first)
                        } else if let current = self.selectedTemplate {
                            self.renderPrintableSheet(for: current)
                        }
                    }
                }
            }
        }
        .background(Color(.systemGray6))
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showTemplatePicker) {
            NavigationView {
                List(availablePitchTemplates) { pt in
                    Button(pt.name) {
                        selectedTemplate = pt
                        renderPrintableSheet(for: pt)
                        showTemplatePicker = false
                    }
                }
                .navigationTitle("Select Grid Key")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showTemplatePicker = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

private extension Array {
    func chunked(into columns: Int) -> [[Element]] {
        guard columns > 1 else { return [self] }
        let total = count
        let perColumn = Int(ceil(Double(total) / Double(columns)))
        if perColumn <= 0 { return [self] }
        var result: [[Element]] = []
        var start = 0
        while start < total {
            let end = Swift.min(start + perColumn, total)
            result.append(Array(self[start..<end]))
            start = end
        }
        return result
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
