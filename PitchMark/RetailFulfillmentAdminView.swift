import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import UIKit

private enum FulfillmentStatus: String, CaseIterable, Identifiable {
    case new
    case queued
    case printed
    case shipped
    case canceled
    case paymentFailed = "payment_failed"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .new: return "New"
        case .queued: return "Queued"
        case .printed: return "Printed"
        case .shipped: return "Shipped"
        case .canceled: return "Canceled"
        case .paymentFailed: return "Payment Failed"
        }
    }
}

private struct FulfillmentOrder: Identifiable {
    let id: String
    let title: String
    let customerEmail: String
    let amountText: String
    let createdAtText: String
    let paymentStatus: String
    var fulfillmentStatus: FulfillmentStatus
    var shippingCarrier: String
    var trackingNumber: String
    let shippingName: String
    let shippingAddressLine1: String
    let shippingAddressLine2: String
    let shippingCity: String
    let shippingState: String
    let shippingPostalCode: String
    let shippingCountry: String
    let orderedTemplateSnapshotJson: String
    let retailProductId: String
    let archivedAt: Date?

    var shippingAddressBlock: String {
        let parts = [
            shippingName,
            shippingAddressLine1,
            shippingAddressLine2,
            [shippingCity, shippingState, shippingPostalCode].filter { !$0.isEmpty }.joined(separator: ", "),
            shippingCountry
        ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return parts.joined(separator: "\n")
    }

    var isArchived: Bool {
        archivedAt != nil
    }
}

@MainActor
private final class RetailFulfillmentAdminViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String? = nil
    @Published private(set) var allOrders: [FulfillmentOrder] = []
    @Published var selectedFilter: FulfillmentStatus? = .new
    @Published var showArchivedOrders = false

    var filteredOrders: [FulfillmentOrder] {
        let source = showArchivedOrders ? allOrders : allOrders.filter { !$0.isArchived }
        guard let selectedFilter else { return source }
        return source.filter { $0.fulfillmentStatus == selectedFilter }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await verifyRetailAdminAccess()
            let snapshot = try await Firestore.firestore()
                .collection("retailOrders")
                .order(by: "stripeCreatedAtMs", descending: true)
                .getDocuments()

            allOrders = snapshot.documents.compactMap { document in
                let data = document.data()
                let amountTotal = data["amountTotal"] as? Int
                let currency = (data["currency"] as? String ?? "usd").uppercased()
                let formatter = NumberFormatter()
                formatter.numberStyle = .currency
                formatter.currencyCode = currency
                let amountText = amountTotal.map { formatter.string(from: NSNumber(value: Double($0) / 100.0)) ?? "$\(Double($0) / 100.0)" } ?? "Amount unavailable"

                let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                let createdAtText = createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "Date unavailable"

                let status = FulfillmentStatus(rawValue: data["fulfillmentStatus"] as? String ?? "") ?? .new
                let templateName = (data["storeTemplateName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let fallback = (data["retailProductId"] as? String) ?? document.documentID

                return FulfillmentOrder(
                    id: document.documentID,
                    title: templateName.isEmpty ? fallback : templateName,
                    customerEmail: data["customerEmail"] as? String ?? "",
                    amountText: amountText,
                    createdAtText: createdAtText,
                    paymentStatus: data["paymentStatus"] as? String ?? "-",
                    fulfillmentStatus: status,
                    shippingCarrier: data["shippingCarrier"] as? String ?? "",
                    trackingNumber: data["trackingNumber"] as? String ?? "",
                    shippingName: data["shippingName"] as? String ?? "",
                    shippingAddressLine1: (data["shippingAddress"] as? [String: Any])?["line1"] as? String ?? "",
                    shippingAddressLine2: (data["shippingAddress"] as? [String: Any])?["line2"] as? String ?? "",
                    shippingCity: (data["shippingAddress"] as? [String: Any])?["city"] as? String ?? "",
                    shippingState: (data["shippingAddress"] as? [String: Any])?["state"] as? String ?? "",
                    shippingPostalCode: (data["shippingAddress"] as? [String: Any])?["postal_code"] as? String ?? "",
                    shippingCountry: (data["shippingAddress"] as? [String: Any])?["country"] as? String ?? "",
                    orderedTemplateSnapshotJson: data["orderedTemplateSnapshotJson"] as? String ?? "",
                    retailProductId: data["retailProductId"] as? String ?? "",
                    archivedAt: (data["archivedAt"] as? Timestamp)?.dateValue()
                )
            }
        } catch {
            errorMessage = "Could not load fulfillment queue. \(error.localizedDescription)"
        }
    }

    func update(order: FulfillmentOrder) async {
        do {
            try await verifyRetailAdminAccess()
            try await Firestore.firestore().collection("retailOrders").document(order.id).setData([
                "fulfillmentStatus": order.fulfillmentStatus.rawValue,
                "shippingCarrier": order.shippingCarrier.trimmingCharacters(in: .whitespacesAndNewlines),
                "trackingNumber": order.trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                "shippedAt": order.fulfillmentStatus == .shipped ? FieldValue.serverTimestamp() : FieldValue.delete(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            errorMessage = "Could not update order \(order.id). \(error.localizedDescription)"
        }
    }

    func archive(order: FulfillmentOrder) async {
        do {
            try await verifyRetailAdminAccess()
            try await Firestore.firestore().collection("retailOrders").document(order.id).setData([
                "archivedAt": FieldValue.serverTimestamp(),
                "archivedBy": "retail-admin",
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            await refresh()
        } catch {
            errorMessage = "Could not archive order \(order.id). \(error.localizedDescription)"
        }
    }

    func unarchive(order: FulfillmentOrder) async {
        do {
            try await verifyRetailAdminAccess()
            try await Firestore.firestore().collection("retailOrders").document(order.id).setData([
                "archivedAt": FieldValue.delete(),
                "archivedBy": FieldValue.delete(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            await refresh()
        } catch {
            errorMessage = "Could not unarchive order \(order.id). \(error.localizedDescription)"
        }
    }

    private func verifyRetailAdminAccess() async throws {
        guard let user = Auth.auth().currentUser else {
            throw RetailFulfillmentAdminError.notSignedIn
        }

        let tokenResult = try await user.getIDTokenResult(forcingRefresh: true)
        guard (tokenResult.claims["admin"] as? Bool) == true else {
            throw RetailFulfillmentAdminError.missingAdminClaim
        }
    }
}

private enum RetailFulfillmentAdminError: LocalizedError {
    case notSignedIn
    case missingAdminClaim

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in with the retail admin account."
        case .missingAdminClaim:
            return "This account is missing the retail admin claim. Sign out and back in after the claim is set."
        }
    }
}

struct RetailFulfillmentAdminView: View {
    @StateObject private var viewModel = RetailFulfillmentAdminViewModel()
    @State private var exportPayload: ExportPayload? = nil

    var body: some View {
        List {
            filterSection

            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading orders…")
                    Spacer()
                }
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            } else if viewModel.filteredOrders.isEmpty {
                Text("No orders for this filter.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.filteredOrders) { order in
                    RetailFulfillmentOrderRow(order: order) { updated in
                        Task { await viewModel.update(order: updated) }
                    } onExport: { exportOrder in
                        let url = makeOrderPacketFile(for: exportOrder)
                        exportPayload = ExportPayload(url: url)
                    } onGeneratePrintPDF: { exportOrder in
                        if let url = makeOrderPrintPDF(for: exportOrder) {
                            exportPayload = ExportPayload(url: url)
                        }
                    } onArchive: { archiveOrder in
                        Task { await viewModel.archive(order: archiveOrder) }
                    } onUnarchive: { unarchiveOrder in
                        Task { await viewModel.unarchive(order: unarchiveOrder) }
                    }
                }
            }
        }
        .navigationTitle("Fulfillment Queue")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task { await viewModel.refresh() }
        .sheet(item: $exportPayload) { payload in
            ShareSheet(items: [payload.url])
        }
    }

    private var filterSection: some View {
        Section("Filter") {
            Picker("Status", selection: $viewModel.selectedFilter) {
                Text("All").tag(Optional<FulfillmentStatus>.none)
                ForEach(FulfillmentStatus.allCases) { status in
                    Text(status.label).tag(Optional(status))
                }
            }
            .pickerStyle(.menu)

            Toggle("Show Archived", isOn: $viewModel.showArchivedOrders)
        }
    }

    private func makeOrderPacketFile(for order: FulfillmentOrder) -> URL {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let safeId = order.id.replacingOccurrences(of: "/", with: "_")
        let fileName = "order_packet_\(safeId).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let packet = """
        PitchMark Order Packet
        Generated: \(timestamp)

        Order ID: \(order.id)
        Item: \(order.title)
        Amount: \(order.amountText)
        Order Date: \(order.createdAtText)
        Customer Email: \(order.customerEmail)
        Payment Status: \(order.paymentStatus)
        Fulfillment Status: \(order.fulfillmentStatus.rawValue)
        Shipping Carrier: \(order.shippingCarrier)
        Tracking Number: \(order.trackingNumber)

        Shipping Address:
        \(order.shippingAddressBlock.isEmpty ? "Unavailable" : order.shippingAddressBlock)

        Ordered Template Snapshot JSON:
        \(order.orderedTemplateSnapshotJson.isEmpty ? "Unavailable" : order.orderedTemplateSnapshotJson)
        """

        do {
            try packet.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            debugLog("❌ Failed to write order packet file:", error.localizedDescription)
        }
        return url
    }

    private func makeOrderPrintPDF(for order: FulfillmentOrder) -> URL? {
        guard !order.orderedTemplateSnapshotJson.isEmpty else { return nil }
        guard let data = order.orderedTemplateSnapshotJson.data(using: .utf8) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(PitchTemplate.self, from: data) else { return nil }

        if order.retailProductId == "sheet_8_5x11" {
            return makePrintableSheetPDF(for: snapshot, orderId: order.id)
        }
        return makeGridKeyPDF(for: snapshot, orderId: order.id, retailProductId: order.retailProductId)
    }

    private func makeGridKeyPDF(for template: PitchTemplate, orderId: String, retailProductId: String) -> URL? {
        let sizeInches: CGSize
        switch retailProductId {
        case "grid_3_5x2_75":
            sizeInches = CGSize(width: 3.5, height: 2.75)
        case "grid_custom":
            sizeInches = CGSize(width: 5.0, height: 3.0)
        default:
            sizeInches = CGSize(width: 5.0, height: 3.0)
        }

        let pointsPerInch: CGFloat = 72
        let targetSize = CGSize(width: sizeInches.width * pointsPerInch, height: sizeInches.height * pointsPerInch)
        let baseContentSize = PrintableEncryptedGridsView.baseContentSize(for: template.pitchGridValues)
        let outerPadding: CGFloat = 24
        let contentSize = CGSize(
            width: baseContentSize.width + (outerPadding * 2),
            height: baseContentSize.height + (outerPadding * 2)
        )
        let scaleFactor = min(targetSize.width / max(contentSize.width, 1), targetSize.height / max(contentSize.height, 1))

        let printableView = PrintableEncryptedGridsView(
            grid: template.pitchGridValues,
            pitchHeaders: template.pitchGridHeaders,
            strikeTopRow: template.strikeTopRow,
            strikeRows: template.strikeRows,
            ballsTopRow: template.ballsTopRow,
            ballsRows: template.ballsRows,
            pitchFirstColors: template.pitchFirstColors,
            locationFirstColors: template.locationFirstColors,
            outerPadding: outerPadding,
            scale: scaleFactor,
            textScale: 1.5
        )

        guard let image = printableView.renderAsPNG(size: targetSize, scale: 3.0, alignment: .center) else {
            return nil
        }

        let safeId = orderId.replacingOccurrences(of: "/", with: "_")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("order_print_\(safeId).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: targetSize))

        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                image.draw(in: CGRect(origin: .zero, size: targetSize))
                let guideRect = CGRect(origin: .zero, size: targetSize).insetBy(dx: 8, dy: 8)
                let guidePath = UIBezierPath(roundedRect: guideRect, cornerRadius: 6)
                UIColor.black.withAlphaComponent(0.16).setStroke()
                guidePath.setLineDash([5, 4], count: 2, phase: 0)
                guidePath.lineWidth = 1
                guidePath.stroke()
            }
            return url
        } catch {
            debugLog("❌ Failed to generate grid print PDF:", error.localizedDescription)
            return nil
        }
    }

    private func makePrintableSheetPDF(for template: PitchTemplate, orderId: String) -> URL? {
        let letterSize = CGSize(width: 612, height: 792)
        let strikesView = PrintableLocationSheetView(template: template, title: "Strikes", locations: strikePrintableLocations)
        let ballsView = PrintableLocationSheetView(template: template, title: "Balls", locations: ballPrintableLocations)

        guard let strikesImage = strikesView.renderAsPNG(size: letterSize, scale: 2.0, alignment: .center),
              let ballsImage = ballsView.renderAsPNG(size: letterSize, scale: 2.0, alignment: .center) else {
            return nil
        }

        let safeId = orderId.replacingOccurrences(of: "/", with: "_")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("order_print_\(safeId).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: letterSize))

        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                strikesImage.draw(in: CGRect(origin: .zero, size: letterSize))
                context.beginPage()
                ballsImage.draw(in: CGRect(origin: .zero, size: letterSize))
            }
            return url
        } catch {
            debugLog("❌ Failed to generate printable sheet PDF:", error.localizedDescription)
            return nil
        }
    }
}

private struct ExportPayload: Identifiable {
    let id = UUID()
    let url: URL
}

private struct RetailFulfillmentOrderRow: View {
    @State var order: FulfillmentOrder
    let onSave: (FulfillmentOrder) -> Void
    let onExport: (FulfillmentOrder) -> Void
    let onGeneratePrintPDF: (FulfillmentOrder) -> Void
    let onArchive: (FulfillmentOrder) -> Void
    let onUnarchive: (FulfillmentOrder) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(order.title)
                .font(.headline)
            Text(order.amountText)
                .font(.subheadline.weight(.semibold))
            Text(order.createdAtText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !order.customerEmail.isEmpty {
                Text(order.customerEmail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("Payment: \(order.paymentStatus)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !order.shippingAddressBlock.isEmpty {
                Text("Ship To")
                    .font(.subheadline.weight(.semibold))
                Text(order.shippingAddressBlock)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Copy Shipping Address") {
                    UIPasteboard.general.string = order.shippingAddressBlock
                }
                .buttonStyle(.bordered)
            }

            if !order.orderedTemplateSnapshotJson.isEmpty {
                Button("Copy Template Snapshot JSON") {
                    UIPasteboard.general.string = order.orderedTemplateSnapshotJson
                }
                .buttonStyle(.bordered)
            }

            Picker("Fulfillment Status", selection: $order.fulfillmentStatus) {
                ForEach(FulfillmentStatus.allCases) { status in
                    Text(status.label).tag(status)
                }
            }
            .pickerStyle(.menu)

            TextField("Carrier (UPS, USPS, etc.)", text: $order.shippingCarrier)
                .textInputAutocapitalization(.words)
            TextField("Tracking Number", text: $order.trackingNumber)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button("Save Update") {
                onSave(order)
            }
            .buttonStyle(.borderedProminent)

            Button("Export Order Packet") {
                onExport(order)
            }
            .buttonStyle(.bordered)

            Button("Generate Print PDF") {
                onGeneratePrintPDF(order)
            }
            .buttonStyle(.borderedProminent)

            if order.isArchived {
                Button("Unarchive Order") {
                    onUnarchive(order)
                }
                .buttonStyle(.bordered)
            } else if order.fulfillmentStatus == .shipped || order.fulfillmentStatus == .canceled {
                Button("Archive Order") {
                    onArchive(order)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}
