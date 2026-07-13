import SwiftUI
import Combine
import FirebaseFirestore
import UIKit

private struct RetailOrderHistoryItem: Identifiable {
    let id: String
    let sessionId: String
    let storeTemplateName: String
    let templateName: String
    let retailProductId: String
    let amountTotalCents: Int?
    let currency: String
    let customerEmail: String
    let shippingName: String
    let shippingAddressLine1: String
    let shippingAddressLine2: String
    let shippingCity: String
    let shippingState: String
    let shippingPostalCode: String
    let shippingCountry: String
    let paymentStatus: String
    let fulfillmentStatus: String
    let createdAt: Date?

    var amountText: String {
        guard let amountTotalCents else { return "Amount unavailable" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased().isEmpty ? "USD" : currency.uppercased()
        return formatter.string(from: NSNumber(value: Double(amountTotalCents) / 100.0)) ?? "$\(Double(amountTotalCents) / 100.0)"
    }

    var titleText: String {
        if !storeTemplateName.isEmpty { return storeTemplateName }
        if !templateName.isEmpty { return templateName }
        return retailProductId.isEmpty ? "Order" : retailProductId
    }

    var dateText: String {
        guard let createdAt else { return "Date unavailable" }
        return createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    var shippingAddressBlock: String {
        let cityLine = [shippingCity, shippingState, shippingPostalCode]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return [
            shippingName,
            shippingAddressLine1,
            shippingAddressLine2,
            cityLine,
            shippingCountry
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }
}

@MainActor
private final class RetailOrderHistoryViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var orders: [RetailOrderHistoryItem] = []
    @Published private(set) var errorMessage: String? = nil

    func refresh(uid: String) async {
        guard !uid.isEmpty else {
            orders = []
            errorMessage = "Sign in to view order history."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snapshot = try await Firestore.firestore()
                .collection("retailOrders")
                .whereField("firebaseUid", isEqualTo: uid)
                .getDocuments()

            let mapped = snapshot.documents.compactMap { document -> RetailOrderHistoryItem? in
                let data = document.data()
                let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                let shippingAddress = data["shippingAddress"] as? [String: Any]
                return RetailOrderHistoryItem(
                    id: document.documentID,
                    sessionId: data["sessionId"] as? String ?? document.documentID,
                    storeTemplateName: data["storeTemplateName"] as? String ?? "",
                    templateName: data["templateName"] as? String ?? "",
                    retailProductId: data["retailProductId"] as? String ?? "",
                    amountTotalCents: centsValue(from: data["amountTotal"]),
                    currency: data["currency"] as? String ?? "usd",
                    customerEmail: data["customerEmail"] as? String ?? "",
                    shippingName: data["shippingName"] as? String ?? "",
                    shippingAddressLine1: shippingAddress?["line1"] as? String ?? "",
                    shippingAddressLine2: shippingAddress?["line2"] as? String ?? "",
                    shippingCity: shippingAddress?["city"] as? String ?? "",
                    shippingState: shippingAddress?["state"] as? String ?? "",
                    shippingPostalCode: shippingAddress?["postal_code"] as? String ?? "",
                    shippingCountry: shippingAddress?["country"] as? String ?? "",
                    paymentStatus: data["paymentStatus"] as? String ?? "",
                    fulfillmentStatus: data["fulfillmentStatus"] as? String ?? (data["fulfillmentState"] as? String ?? ""),
                    createdAt: createdAt
                )
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.createdAt ?? .distantPast
                let rhsDate = rhs.createdAt ?? .distantPast
                return lhsDate > rhsDate
            }

            orders = mapped
        } catch {
            errorMessage = "Could not load orders. \(error.localizedDescription)"
        }
    }

    func refreshUntilOrderAppears(uid: String) async {
        for attempt in 0..<6 {
            await refresh(uid: uid)
            if !orders.isEmpty || uid.isEmpty { return }
            if attempt < 5 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
}

struct RetailOrderHistoryView: View {
    let uid: String
    let showReceiptOnLoad: Bool

    @StateObject private var viewModel = RetailOrderHistoryViewModel()

    init(uid: String, showReceiptOnLoad: Bool = false) {
        self.uid = uid
        self.showReceiptOnLoad = showReceiptOnLoad
    }

    var body: some View {
        Group {
            if showReceiptOnLoad {
                latestReceiptContent
            } else {
                historyContent
            }
        }
        .navigationTitle(showReceiptOnLoad ? "Receipt" : "Order History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refresh(uid: uid) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            if showReceiptOnLoad {
                await viewModel.refreshUntilOrderAppears(uid: uid)
            } else {
                await viewModel.refresh(uid: uid)
            }
        }
    }

    private var historyContent: some View {
        List {
            if viewModel.isLoading {
                loadingRow("Loading orders…")
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else if viewModel.orders.isEmpty {
                Text("No retail orders yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.orders) { order in
                    NavigationLink {
                        RetailReceiptView(order: order)
                    } label: {
                        RetailOrderSummaryRow(order: order)
                    }
                }
            }
        }
    }

    private var latestReceiptContent: some View {
        Group {
            if let order = viewModel.orders.first {
                RetailReceiptView(order: order)
            } else {
                List {
                    if viewModel.isLoading {
                        loadingRow("Loading receipt…")
                    } else if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    } else {
                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Order received", systemImage: "checkmark.circle.fill")
                                    .font(.headline)
                                    .foregroundStyle(.green)
                                Text("Stripe has finished checkout. Receipt details will appear here as soon as payment confirmation reaches PitchMark.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Button {
                                    Task { await viewModel.refresh(uid: uid) }
                                } label: {
                                    Label("Check Again", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }

    private func loadingRow(_ title: String) -> some View {
        HStack {
            Spacer()
            ProgressView(title)
            Spacer()
        }
    }
}

private struct RetailOrderSummaryRow: View {
    let order: RetailOrderHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(order.titleText)
                .font(.headline)
            Text(order.amountText)
                .font(.subheadline.weight(.semibold))
            Text(order.dateText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !order.paymentStatus.isEmpty || !order.fulfillmentStatus.isEmpty {
                Text("Payment: \(order.paymentStatus.isEmpty ? "-" : order.paymentStatus) • Fulfillment: \(readableFulfillmentLabel(order.fulfillmentStatus))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("Order ID: \(order.sessionId)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct RetailReceiptView: View {
    let order: RetailOrderHistoryItem

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Order received", systemImage: "checkmark.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(order.titleText)
                        .font(.headline)
                    Text(order.amountText)
                        .font(.title3.weight(.bold))
                    Text("Ordered \(order.dateText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Receipt Details") {
                receiptRow("Order ID", order.sessionId)
                receiptRow("Payment", readablePaymentLabel(order.paymentStatus))
                receiptRow("Fulfillment", readableFulfillmentLabel(order.fulfillmentStatus))
                if !order.customerEmail.isEmpty {
                    receiptRow("Email", order.customerEmail)
                }
            }

            if !order.shippingAddressBlock.isEmpty {
                Section("Shipping") {
                    Text(order.shippingAddressBlock)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
            }

            Section("Next Steps") {
                Label("PitchMark will prepare the printed materials from the grid key selected at checkout.", systemImage: "printer")
                Label("You can return to Order History to check fulfillment status.", systemImage: "clock.arrow.circlepath")
                Label("If shipping is used, tracking details will be added after fulfillment.", systemImage: "shippingbox")
            }
            .font(.subheadline)

            Section {
                Button {
                    printReceipt()
                } label: {
                    Label("Print Receipt", systemImage: "printer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Receipt")
    }

    private func receiptRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value.isEmpty ? "-" : value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }

    private func printReceipt() {
        let controller = UIPrintInteractionController.shared
        let formatter = UIMarkupTextPrintFormatter(markupText: receiptHTML)
        controller.printFormatter = formatter
        controller.printInfo = {
            let info = UIPrintInfo(dictionary: nil)
            info.outputType = .general
            info.jobName = "PitchMark Receipt \(order.sessionId)"
            return info
        }()
        controller.present(animated: true)
    }

    private var receiptHTML: String {
        let shippingHTML = order.shippingAddressBlock.isEmpty
            ? ""
            : """
            <h2>Shipping</h2>
            <p>\(escapeHTML(order.shippingAddressBlock).replacingOccurrences(of: "\n", with: "<br>"))</p>
            """
        return """
        <html>
        <head>
        <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 28px; color: #111; }
        h1 { font-size: 24px; margin-bottom: 4px; }
        h2 { font-size: 16px; margin-top: 24px; border-bottom: 1px solid #ddd; padding-bottom: 6px; }
        table { width: 100%; border-collapse: collapse; }
        td { padding: 8px 0; border-bottom: 1px solid #eee; vertical-align: top; }
        td:first-child { color: #555; width: 34%; }
        </style>
        </head>
        <body>
        <h1>PitchMark Receipt</h1>
        <p>Order received \(escapeHTML(order.dateText))</p>
        <h2>Order</h2>
        <table>
        <tr><td>Item</td><td>\(escapeHTML(order.titleText))</td></tr>
        <tr><td>Total</td><td>\(escapeHTML(order.amountText))</td></tr>
        <tr><td>Order ID</td><td>\(escapeHTML(order.sessionId))</td></tr>
        <tr><td>Payment</td><td>\(escapeHTML(readablePaymentLabel(order.paymentStatus)))</td></tr>
        <tr><td>Fulfillment</td><td>\(escapeHTML(readableFulfillmentLabel(order.fulfillmentStatus)))</td></tr>
        <tr><td>Email</td><td>\(escapeHTML(order.customerEmail.isEmpty ? "-" : order.customerEmail))</td></tr>
        </table>
        \(shippingHTML)
        <h2>Next Steps</h2>
        <p>PitchMark will prepare the printed materials from the grid key selected at checkout. Return to Order History to check fulfillment status.</p>
        </body>
        </html>
        """
    }
}

private func readablePaymentLabel(_ raw: String) -> String {
    switch raw {
    case "paid":
        return "Paid"
    case "unpaid":
        return "Unpaid"
    case "no_payment_required":
        return "No payment required"
    default:
        return raw.isEmpty ? "-" : raw
    }
}

private func readableFulfillmentLabel(_ raw: String) -> String {
        switch raw {
        case "new":
            return "New"
        case "queued":
            return "Queued"
        case "printed":
            return "Printed"
        case "shipped":
            return "Shipped"
        case "canceled":
            return "Canceled"
        case "payment_failed":
            return "Payment failed"
        default:
            return raw.isEmpty ? "-" : raw
        }
    }

private func escapeHTML(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

private func centsValue(from rawValue: Any?) -> Int? {
    switch rawValue {
    case let value as Int:
        return value
    case let value as Int64:
        return Int(value)
    case let value as NSNumber:
        return value.intValue
    default:
        return nil
    }
}
