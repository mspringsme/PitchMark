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

    enum DebugSubscriptionOverride: String, CaseIterable, Identifiable {
        case off
        case forceInactive
        case forceActive

        var id: String { rawValue }

        var label: String {
            switch self {
            case .off: return "Off"
            case .forceInactive: return "Force Inactive"
            case .forceActive: return "Force Active"
            }
        }
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro: Bool = false
    @Published private(set) var status: Status = .loading
    @Published private(set) var forcePaywallForSandboxTesting: Bool = false
    @Published private(set) var debugSubscriptionOverride: DebugSubscriptionOverride = .off
    @Published var lastErrorMessage: String? = nil
    private var transactionUpdatesTask: Task<Void, Never>? = nil
    private var isRefreshingEntitlements = false
    private var pendingEntitlementRefresh = false
    private static let forcePaywallTestingKey = "forcePaywallForSandboxSubscriptionTesting"
    private static let debugSubscriptionOverrideKey = "debugSubscriptionOverride"

    var annualProduct: Product? {
        products.first(where: { $0.id == Self.annualProductId })
    }

    init() {
        log("init")
        forcePaywallForSandboxTesting = Self.sandboxTestingOverrideAvailable &&
            UserDefaults.standard.bool(forKey: Self.forcePaywallTestingKey)
        if let persistedOverride = UserDefaults.standard.string(forKey: Self.debugSubscriptionOverrideKey),
           let override = DebugSubscriptionOverride(rawValue: persistedOverride) {
            debugSubscriptionOverride = override
        }
        transactionUpdatesTask = Task { [weak self] in
            await self?.observeTransactions()
        }
        Task {
            await refresh(reason: "init")
        }
    }

    var isSandboxTestingOverrideAvailable: Bool {
        Self.sandboxTestingOverrideAvailable
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func refresh(reason: String = "manual") async {
        log("refresh start reason=\(reason)")
        await loadProducts()
        await refreshEntitlements(reason: reason)
        log("refresh complete reason=\(reason) isPro=\(isPro) status=\(statusLabel)")
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: [Self.annualProductId])
            log("loadProducts success count=\(products.count) annualFound=\(annualProduct != nil)")
        } catch {
            lastErrorMessage = "Unable to load products."
            log("loadProducts failed error=\(error.localizedDescription)")
        }
    }

    func refreshEntitlements(reason: String = "manual") async {
        guard !isRefreshingEntitlements else {
            pendingEntitlementRefresh = true
            log("refreshEntitlements queued reason=\(reason) (already refreshing)")
            return
        }

        isRefreshingEntitlements = true
        log("refreshEntitlements start reason=\(reason)")
        var hasActive = false
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                log(
                    "entitlement verified product=\(transaction.productID) " +
                    "revoked=\(transaction.revocationDate != nil) " +
                    "expires=\(transaction.expirationDate?.description ?? "nil")"
                )
                guard transaction.productID == Self.annualProductId else { continue }
                if transaction.revocationDate == nil {
                    hasActive = true
                }
            case .unverified(_, let error):
                log("entitlement unverified error=\(error.localizedDescription)")
            }
        }
        let previous = isPro
        applyEntitlementState(hasActive, reason: reason)
        log("refreshEntitlements complete reason=\(reason) isPro \(previous) -> \(isPro) status=\(statusLabel)")
        isRefreshingEntitlements = false

        if pendingEntitlementRefresh {
            pendingEntitlementRefresh = false
            log("refreshEntitlements draining queued refresh")
            await refreshEntitlements(reason: "queued")
        }
    }

    func purchaseAnnual() async {
        lastErrorMessage = nil
        log("purchase start")

        if annualProduct == nil {
            await loadProducts()
        }
        guard let product = annualProduct else {
            lastErrorMessage = "Product not available."
            log("purchase aborted product unavailable")
            return
        }

        do {
            let result = try await product.purchase()
            log("purchase returned result=\(String(describing: result))")
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    log("purchase verified product=\(transaction.productID) txnId=\(transaction.id)")
                    if transaction.productID == Self.annualProductId {
                        if forcePaywallForSandboxTesting {
                            setForcePaywallForSandboxTesting(false)
                        }
                        applyEntitlementState(true, reason: "purchase-verified")
                    }
                    await transaction.finish()
                    log("purchase transaction finished txnId=\(transaction.id)")
                    await refreshEntitlements(reason: "purchase-success")
                case .unverified:
                    lastErrorMessage = "Purchase could not be verified."
                    log("purchase unverified")
                }
            case .userCancelled:
                log("purchase cancelled by user")
            case .pending:
                lastErrorMessage = "Purchase pending approval."
                log("purchase pending")
            @unknown default:
                log("purchase unknown result")
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            log("purchase failed error=\(error.localizedDescription)")
        }
    }

    func restorePurchases() async {
        lastErrorMessage = nil
        log("restore start")
        do {
            try await AppStore.sync()
            log("restore sync complete")
            await refreshEntitlements(reason: "restore")
        } catch {
            lastErrorMessage = error.localizedDescription
            log("restore failed error=\(error.localizedDescription)")
        }
    }

    private func observeTransactions() async {
        log("transaction listener started")
        for await result in Transaction.updates {
            if Task.isCancelled {
                log("transaction listener cancelled")
                return
            }
            switch result {
            case .verified(let transaction):
                log("transaction update verified product=\(transaction.productID) txnId=\(transaction.id)")
                if transaction.productID == Self.annualProductId {
                    await refreshEntitlements(reason: "transaction-update")
                }
                await transaction.finish()
                log("transaction update finished txnId=\(transaction.id)")
            case .unverified(_, let error):
                log("transaction update unverified error=\(error.localizedDescription)")
            }
        }
        log("transaction listener exited")
    }

    func refreshForAuthStateChange(isSignedIn: Bool) async {
        log("auth state changed isSignedIn=\(isSignedIn)")
        await refreshEntitlements(reason: isSignedIn ? "auth-sign-in" : "auth-sign-out")
    }

    func setForcePaywallForSandboxTesting(_ isEnabled: Bool) {
        guard isSandboxTestingOverrideAvailable else { return }
        forcePaywallForSandboxTesting = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.forcePaywallTestingKey)
        log("sandbox force paywall testing set=\(isEnabled)")
        if isEnabled {
            let previous = isPro
            isPro = false
            status = .inactive
            log("isPro forced \(previous) -> \(isPro) for sandbox testing")
        } else {
            Task {
                await refreshEntitlements(reason: "sandbox-test-override-disabled")
            }
        }
    }

    func setDebugSubscriptionOverride(_ override: DebugSubscriptionOverride) {
        guard isSandboxTestingOverrideAvailable else { return }
        debugSubscriptionOverride = override
        UserDefaults.standard.set(override.rawValue, forKey: Self.debugSubscriptionOverrideKey)
        log("debug subscription override set=\(override.rawValue)")
        switch override {
        case .off:
            Task {
                await refreshEntitlements(reason: "debug-override-off")
            }
        case .forceInactive:
            applyEntitlementState(false, reason: "debug-force-inactive")
        case .forceActive:
            applyEntitlementState(true, reason: "debug-force-active")
        }
    }

    private func applyEntitlementState(_ hasActiveEntitlement: Bool, reason: String) {
        let previous = isPro
        var effectiveIsPro = hasActiveEntitlement && !forcePaywallForSandboxTesting
        switch debugSubscriptionOverride {
        case .off:
            break
        case .forceInactive:
            effectiveIsPro = false
        case .forceActive:
            effectiveIsPro = true
        }
        isPro = effectiveIsPro
        status = effectiveIsPro ? .active : .inactive
        if forcePaywallForSandboxTesting, hasActiveEntitlement {
            log("active entitlement masked for sandbox testing reason=\(reason)")
        }
        if debugSubscriptionOverride != .off {
            log("active entitlement overridden by debug mode=\(debugSubscriptionOverride.rawValue) reason=\(reason)")
        }
        log("applyEntitlementState reason=\(reason) isPro \(previous) -> \(isPro)")
    }

    private var statusLabel: String {
        switch status {
        case .loading: return "loading"
        case .active: return "active"
        case .inactive: return "inactive"
        }
    }

    private func log(_ message: String) {
        print("💳 [SubscriptionManager] \(message)")
    }

    private static var sandboxTestingOverrideAvailable: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
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
