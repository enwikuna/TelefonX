import StoreKit
import SwiftUI

struct ProView: View {
    @Environment(PhoneModel.self) private var model

    private let privacyPolicy = URL(string: "https://www.enwikuna.de/datenschutz/telefonx")!
    private let termsOfService = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if model.purchases.products.count == SubscriptionCatalog.productIDs.count {
                    subscriptionStore
                } else if model.purchases.isLoading {
                    ProgressView("Loading subscriptions …")
                } else {
                    ContentUnavailableView(
                        "Subscriptions Unavailable",
                        systemImage: "cart.badge.questionmark",
                        description: Text(model.purchases.loadError
                                          ?? L10n.text("Subscriptions are currently unavailable. Please try again later."))
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: 400, height: 600)
        .hiddenWindowToolbarBackgroundOnMacOS27()
        .task { await model.purchases.start() }
    }

    private var subscriptionStore: some View {
        SubscriptionStoreView(subscriptions: model.purchases.products) {
            marketingContent
        }
        .environment(\.locale, Locale(identifier: Bundle.main.preferredLocalizations.first ?? Locale.current.identifier))
        .subscriptionStoreControlStyle(.prominentPicker)
        .subscriptionStoreButtonLabel(.multiline)
        .storeButton(.hidden, for: .restorePurchases, .cancellation)
        .subscriptionStorePolicyDestination(url: termsOfService, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: privacyPolicy, for: .privacyPolicy)
        .onInAppPurchaseCompletion { _, result in
            await model.purchases.handlePurchaseCompletion(result)
        }
    }

    private var marketingContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.tint)
            Text("TelefonX Pro")
                .font(.title2.bold())
            Text(L10n.text("More lines, planned callbacks, contact import and export, dialing rules, business name lookup, and custom hold music and ringtones."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if model.purchases.hasActiveSubscription {
                Label("TelefonX Pro is active.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if model.purchases.products.count == SubscriptionCatalog.productIDs.count,
               let error = model.purchases.loadError {
                Text(error).font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footerActions
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(.bar)
    }

    private var footerActions: some View {
        VStack(spacing: 12) {
            Button {
                Task { await model.purchases.restore() }
            } label: {
                Text("Restore Purchases")
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .telefonButtonStyle()
            .disabled(model.purchases.isLoading || model.purchases.isRestoring)
            if model.purchases.hasActiveSubscription {
                Link("Manage Subscription …", destination: manageSubscriptions)
            }
            if model.purchases.products.count != SubscriptionCatalog.productIDs.count,
               !model.purchases.isLoading {
                Button("Try Again") {
                    Task { await model.purchases.reloadProducts() }
                }
            }
        }
        .controlSize(.regular)
    }
}

struct ProCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let hasActiveSubscription: Bool

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button {
                openWindow(id: "pro")
            } label: {
                Label(
                    hasActiveSubscription ? "Manage TelefonX Pro …" : "TelefonX Pro …",
                    systemImage: "sparkles"
                )
            }
        }
    }
}

struct ProAccessButton: View {
    @Environment(\.openWindow) private var openWindow
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey = "View TelefonX Pro …") {
        self.title = title
    }

    var body: some View {
        Button {
            openWindow(id: "pro")
        } label: {
            Label(title, systemImage: "sparkles")
        }
    }
}

struct ProFeatureNotice: View {
    let message: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Label(message, systemImage: "lock.fill")
                .foregroundStyle(.secondary)
            Spacer()
            ProAccessButton()
        }
    }
}
