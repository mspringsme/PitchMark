import SwiftUI
import Combine
import FirebaseFirestore

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
}

@MainActor
private final class RetailFulfillmentAdminViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String? = nil
    @Published private(set) var allOrders: [FulfillmentOrder] = []
    @Published var selectedFilter: FulfillmentStatus? = .new

    var filteredOrders: [FulfillmentOrder] {
        guard let selectedFilter else { return allOrders }
        return allOrders.filter { $0.fulfillmentStatus == selectedFilter }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
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
                    trackingNumber: data["trackingNumber"] as? String ?? ""
                )
            }
        } catch {
            errorMessage = "Could not load fulfillment queue. \(error.localizedDescription)"
        }
    }

    func update(order: FulfillmentOrder) async {
        do {
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
}

struct RetailFulfillmentAdminView: View {
    @StateObject private var viewModel = RetailFulfillmentAdminViewModel()

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
        }
    }
}

private struct RetailFulfillmentOrderRow: View {
    @State var order: FulfillmentOrder
    let onSave: (FulfillmentOrder) -> Void

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
        }
        .padding(.vertical, 4)
    }
}
