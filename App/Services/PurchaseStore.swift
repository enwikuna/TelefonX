import StoreKit
import Observation
import TelefonDomain

enum SubscriptionCatalog {
    static let monthlyProductID = "de.enwikuna.telefonx.pro.monthly"
    static let annualProductID = "de.enwikuna.telefonx.pro.annual"
    static let productIDs = [annualProductID, monthlyProductID]
    static let productIDSet = Set(productIDs)
}

enum ProEntitlementPolicy {
    static func access(internalEvaluation: Bool, activeProductIDs: Set<String>) -> FeatureAccess {
        let hasSubscription = !activeProductIDs.isDisjoint(with: SubscriptionCatalog.productIDSet)
        return FeatureAccess(
            internalEvaluation: internalEvaluation,
            unlocked: hasSubscription ? Set(PaidFeature.allCases) : []
        )
    }
}

@MainActor @Observable final class PurchaseStore {
    private(set) var products: [Product] = []
    private(set) var access: FeatureAccess {
        didSet { if oldValue != access { onAccessChange?() } }
    }
    @ObservationIgnored var onAccessChange: (@MainActor () -> Void)?
    private(set) var activeProductID: String?
    private(set) var currentPeriodEnd: Date?
    private(set) var isLoading = false
    private(set) var isRestoring = false
    private(set) var loadError: String?
    let internalEvaluation: Bool

    @ObservationIgnored private let productIDs: Set<String>
    @ObservationIgnored private let syncPurchases: @MainActor () async throws -> Void
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var expirationRefresh: Task<Void, Never>?

    init(internalEvaluation: Bool, productIDs: Set<String> = SubscriptionCatalog.productIDSet,
         syncPurchases: @escaping @MainActor () async throws -> Void = { try await AppStore.sync() }) {
        self.internalEvaluation = internalEvaluation
        self.productIDs = productIDs
        self.syncPurchases = syncPurchases
        access = ProEntitlementPolicy.access(internalEvaluation: internalEvaluation, activeProductIDs: [])
    }

    var isConfiguredForSales: Bool { !productIDs.isEmpty }
    var hasActiveSubscription: Bool { activeProductID != nil }
    var hasProAccess: Bool { internalEvaluation || hasActiveSubscription }

    func start() async {
        guard isConfiguredForSales else { return }
        if updates == nil {
            updates = Task { [weak self] in
                for await result in Transaction.updates {
                    guard !Task.isCancelled, let self else { break }
                    guard case .verified(let transaction) = result,
                          self.productIDs.contains(transaction.productID) else { continue }
                    await self.refreshEntitlements()
                    await transaction.finish()
                }
            }
        }
        await reloadProducts()
    }

    func reloadProducts() async {
        guard isConfiguredForSales, !isLoading else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        // Restore verified cached access before waiting on the network catalog.
        await refreshEntitlements()
        do {
            let loaded = try await Product.products(for: productIDs)
            products = loaded.sorted { lhs, rhs in
                let left = SubscriptionCatalog.productIDs.firstIndex(of: lhs.id) ?? .max
                let right = SubscriptionCatalog.productIDs.firstIndex(of: rhs.id) ?? .max
                return left < right
            }
            if products.count != productIDs.count {
                loadError = L10n.text("Subscriptions are currently unavailable. Please try again later.")
            }
            await refreshEntitlements()
        } catch {
            loadError = L10n.error(error)
            await refreshEntitlements()
        }
    }

    func refreshEntitlements() async {
        var activeTransactions: [Transaction] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded,
                  transaction.expirationDate.map({ $0 > Date() }) ?? true else { continue }
            activeTransactions.append(transaction)
        }
        let active = activeTransactions.max {
            ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture)
        }
        activeProductID = active?.productID
        currentPeriodEnd = active?.expirationDate
        access = ProEntitlementPolicy.access(
            internalEvaluation: internalEvaluation,
            activeProductIDs: Set(activeTransactions.map(\.productID))
        )
        scheduleExpirationRefresh()
    }

    func handlePurchaseCompletion(_ result: Result<Product.PurchaseResult, Error>) async {
        switch result {
        case .success(.success(let verification)):
            guard case .verified(let transaction) = verification else {
                loadError = PurchaseError.unverified.localizedDescription
                return
            }
            await refreshEntitlements()
            await transaction.finish()
        case .success(.pending), .success(.userCancelled):
            break
        case .failure(let error):
            loadError = L10n.error(error)
        @unknown default:
            break
        }
    }

    func restore() async {
        guard isConfiguredForSales else {
            loadError = PurchaseError.notConfigured.localizedDescription
            return
        }
        guard !isRestoring else { return }
        isRestoring = true
        loadError = nil
        defer { isRestoring = false }
        do {
            try await syncPurchases()
            await refreshEntitlements()
        } catch StoreKitError.userCancelled {
            // Cancelling authentication is a normal exit, not a failed restore.
        } catch let error as SKError where error.code == .paymentCancelled {
        } catch is CancellationError {
        } catch {
            loadError = L10n.error(error)
        }
    }

    func stop() {
        updates?.cancel()
        updates = nil
        expirationRefresh?.cancel()
        expirationRefresh = nil
    }

    private func scheduleExpirationRefresh() {
        expirationRefresh?.cancel()
        expirationRefresh = nil
        guard let currentPeriodEnd else { return }
        expirationRefresh = Task { [weak self] in
            let seconds = max(0, currentPeriodEnd.timeIntervalSinceNow)
            do { try await Task.sleep(for: .seconds(seconds)) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            await self.refreshEntitlements()
        }
    }
}

enum PurchaseError: LocalizedError {
    case notConfigured, unverified

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            L10n.text("Purchases are not configured in this internal test build.")
        case .unverified:
            L10n.text("The App Store purchase could not be verified. No features were unlocked.")
        }
    }
}
