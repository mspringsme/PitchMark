import SwiftUI
import StoreKit
import Combine

@MainActor
final class SubscriptionManager: ObservableObject {
    static let annualProductId = "com.pitchmark.pro.annual"

    enum Status {
        case loading
        case active
        case inactive
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro: Bool = false
    @Published private(set) var status: Status = .loading
    @Published var lastErrorMessage: String? = nil

    var annualProduct: Product? {
        products.first(where: { $0.id == Self.annualProductId })
    }

    init() {
        Task { await refresh() }
        Task { await observeTransactions() }
    }

    func refresh() async {
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: [Self.annualProductId])
        } catch {
            lastErrorMessage = "Unable to load products."
        }
    }

    func refreshEntitlements() async {
        var hasActive = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == Self.annualProductId else { continue }
            if transaction.revocationDate == nil {
                hasActive = true
            }
        }
        isPro = hasActive
        status = hasActive ? .active : .inactive
    }

    func purchaseAnnual() async {
        lastErrorMessage = nil

        if annualProduct == nil {
            await loadProducts()
        }
        guard let product = annualProduct else {
            lastErrorMessage = "Product not available."
            return
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlements()
                case .unverified:
                    lastErrorMessage = "Purchase could not be verified."
                }
            case .userCancelled:
                break
            case .pending:
                lastErrorMessage = "Purchase pending approval."
            @unknown default:
                break
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        lastErrorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func observeTransactions() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.annualProductId {
                await refreshEntitlements()
            }
            await transaction.finish()
        }
    }
}

struct ProPaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let title: String
    let message: String
    var allowsClose: Bool = true

    @State private var isPurchasing = false

    private var priceLabel: String {
        subscriptionManager.annualProduct?.displayPrice ?? "$19.99"
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.title2.bold())

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text("PitchMark Pro includes:")
                    .font(.headline)

                Text("• Add more than 2 pitches to grid keys")
                Text("• Connect a participant during games")
                Text("• Display app access")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.subheadline)

            VStack(spacing: 10) {
                Button {
                    guard !isPurchasing else { return }
                    isPurchasing = true
                    Task {
                        await subscriptionManager.purchaseAnnual()
                        isPurchasing = false
                    }
                } label: {
                    Text("Start Pro Annual — \(priceLabel)/year")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(subscriptionManager.status == .loading)

                Button("Restore Purchases") {
                    Task { await subscriptionManager.restorePurchases() }
                }
                .buttonStyle(.bordered)
            }

            if let errorMessage = subscriptionManager.lastErrorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if allowsClose {
                Button("Not Now") {
                    dismiss()
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .onChange(of: subscriptionManager.isPro) { _, newValue in
            if newValue {
                dismiss()
            }
        }
        .task {
            await subscriptionManager.refresh()
        }
    }
}
