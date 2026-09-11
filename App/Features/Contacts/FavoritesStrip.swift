import SwiftUI
import TelefonDomain

struct FavoritesStrip: View {
    @Environment(PhoneModel.self) private var model
    let showAll: () -> Void
    private var favorites: [PhoneContact] { ContactFavorites.ordered(model.snapshot.contacts) }

    var body: some View {
        if !favorites.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Favorites").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                GeometryReader { geometry in
                    let visibleCount = FavoritesStripLayout.visibleCount(total: favorites.count, width: geometry.size.width)
                    let tileWidth = FavoritesStripLayout.tileWidth(total: favorites.count, width: geometry.size.width)
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(favorites.prefix(visibleCount)) { contact in
                            Button {
                                if let number = ContactFavorites.number(for: contact) {
                                    Task { await model.performListCall(number, preferredAccountID: contact.preferredAccountID) }
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    ContactAvatar(contact: contact, size: 44)
                                    Text(contact.name).font(.caption.weight(.medium)).lineLimit(2).multilineTextAlignment(.center)
                                }.modifier(FavoriteTileSurface(width: tileWidth))
                            }.buttonStyle(.plain).disabled(ContactFavorites.number(for: contact) == nil)
                                .help("\(contact.name) · \(ContactFavorites.number(for: contact) ?? "No Phone Number") · \(listCallActionTitle)")
                                .accessibilityLabel(L10n.format("%@, %@", contact.name,
                                                                listCallActionTitle))
                        }
                        if favorites.count > visibleCount {
                            Button(action: showAll) {
                                VStack(spacing: 6) {
                                    Image(systemName: "ellipsis").font(.title3).frame(width: 44, height: 44).background(.quaternary, in: Circle())
                                    Text("Show All").font(.caption.weight(.medium))
                                }.modifier(FavoriteTileSurface(width: tileWidth))
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(height: 90)
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
        }
    }

    private var listCallActionTitle: String {
        if !model.activeCalls.isEmpty { return L10n.text("Start Consultation") }
        return L10n.text(model.automaticallyStartListCalls ? "Place Call" : "Use Number")
    }
}

/// Equal-width tiles, reserving one slot for Show All on overflow.
enum FavoritesStripLayout {
    static func tileWidth(total: Int, width: CGFloat) -> CGFloat {
        let visible = visibleCount(total: total, width: width)
        let tiles = visible + (total > visible ? 1 : 0)
        guard tiles > 0 else { return 0 }
        return max(0, (width - CGFloat(tiles - 1) * 8) / CGFloat(tiles))
    }

    static func visibleCount(total: Int, width: CGFloat) -> Int {
        let capacity = max(1, Int((max(0, width) + 8) / 84))
        return total <= capacity ? total : max(0, capacity - 1)
    }
}

private struct FavoriteTileSurface: ViewModifier {
    let width: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .frame(width: width, height: 90, alignment: .center)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}
