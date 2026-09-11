import SwiftUI
import TelefonDomain

/// Identity content, not an interactive glass surface. Shared by contacts, history and calls.
struct ContactAvatar: View {
    let contact: PhoneContact?
    var size: CGFloat = 36

    var body: some View {
        let monogram = contact.flatMap { ContactAvatarPresentation.monogram(name: $0.name, company: $0.company) }
        let color = contact.map { contact in
            let components = ContactAvatarPresentation.colorComponents(for: contact.id)
            return Color(red: components.red, green: components.green, blue: components.blue)
        } ?? Color(red: 0.40, green: 0.38, blue: 0.47)
        ZStack {
            if let photo = ContactPhotoCache.image(for: contact?.photoData) {
                Image(decorative: photo, scale: 1).resizable().scaledToFill()
            } else {
                Circle().fill((monogram == nil ? Color(red: 0.40, green: 0.38, blue: 0.47) : color).gradient)
                if let monogram {
                    Text(monogram).font(.system(size: size * 0.39, weight: .medium, design: .rounded))
                        .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 3)
                } else {
                    Image(systemName: "person.fill").resizable().scaledToFit()
                        .foregroundStyle(.white).frame(width: size * 0.78, height: size * 0.78).offset(y: size * 0.13)
                }
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .accessibilityHidden(true)
    }
}
