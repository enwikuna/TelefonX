import StoreKit
import TelefonDomain
import Testing
@testable import TelefonX

@Suite struct PurchaseStoreTests {
    @Test @MainActor func cancelledRestoreClearsOldErrorWithoutUnlockingFeatures() async {
        for error: any Error in [StoreKitError.userCancelled, SKError(.paymentCancelled), CancellationError()] {
            let store = PurchaseStore(internalEvaluation: false, syncPurchases: { throw error })
            await store.handlePurchaseCompletion(.failure(URLError(.notConnectedToInternet)))
            #expect(store.loadError != nil)
            await store.restore()
            #expect(store.loadError == nil)
            #expect(!store.isRestoring)
            #expect(!store.hasProAccess)
        }
    }

    @Test func catalogMatchesAppStoreConnectIdentifiers() {
        #expect(SubscriptionCatalog.productIDSet == [
            "de.enwikuna.telefonx.pro.monthly",
            "de.enwikuna.telefonx.pro.annual"
        ])
    }

    @Test func eitherSubscriptionUnlocksEveryProFeature() {
        for productID in SubscriptionCatalog.productIDs {
            let access = ProEntitlementPolicy.access(
                internalEvaluation: false,
                activeProductIDs: [productID]
            )
            #expect(PaidFeature.allCases.allSatisfy(access.permits))
        }
    }

    @Test func unknownOrMissingEntitlementsDoNotUnlockProFeatures() {
        let none = ProEntitlementPolicy.access(internalEvaluation: false, activeProductIDs: [])
        let unknown = ProEntitlementPolicy.access(
            internalEvaluation: false,
            activeProductIDs: ["de.enwikuna.telefonx.unknown"]
        )
        #expect(PaidFeature.allCases.allSatisfy { !none.permits($0) })
        #expect(PaidFeature.allCases.allSatisfy { !unknown.permits($0) })
    }

    @Test func internalEvaluationRemainsExplicitlyUnlocked() {
        let access = ProEntitlementPolicy.access(internalEvaluation: true, activeProductIDs: [])
        #expect(PaidFeature.allCases.allSatisfy(access.permits))
    }
}
