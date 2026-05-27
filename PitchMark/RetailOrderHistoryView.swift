import SwiftUI
import Combine
import FirebaseFirestore

private struct RetailOrderHistoryItem: Identifiable {
    let id: String
    let sessionId: String
    let storeTemplateName: String
    let templateName: String
    let retailProductId: String
    let amountTotalCents: Int?
    let currency: String
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
                return RetailOrderHistoryItem(
                    id: document.documentID,
                    sessionId: data["sessionId"] as? String ?? document.documentID,
                    storeTemplateName: data["storeTemplateName"] as? String ?? "",
                    templateName: data["templateName"] as? String ?? "",
                    retailProductId: data["retailProductId"] as? String ?? "",
                    amountTotalCents: data["amountTotal"] as? Int,
                    currency: data["currency"] as? String ?? "usd",
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
}

struct RetailOrderHistoryView: View {
    let uid: String

    @StateObject private var viewModel = RetailOrderHistoryViewModel()

    var body: some View {
        List {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading orders…")
                    Spacer()
                }
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else if viewModel.orders.isEmpty {
                Text("No retail orders yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.orders) { order in
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
        }
        .navigationTitle("Order History")
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
            await viewModel.refresh(uid: uid)
        }
    }

    private func readableFulfillmentLabel(_ raw: String) -> String {
        switch raw {
        case "new":
            return "new"
        case "queued":
            return "queued"
        case "printed":
            return "printed"
        case "shipped":
            return "shipped"
        case "canceled":
            return "canceled"
        case "payment_failed":
            return "payment failed"
        default:
            return raw.isEmpty ? "-" : raw
        }
    }
}
