import AppKit
import Contacts
import CryptoKit
import TelefonDomain

enum AppleContactsAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted

    var description: String {
        switch self {
        case .notDetermined: L10n.text("Access Not Requested Yet")
        case .authorized: L10n.text("Access Allowed")
        case .denied: L10n.text("Access Denied")
        case .restricted: L10n.text("Access Restricted by macOS")
        }
    }
}

struct AppleContact: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let company: String
    let phoneNumbers: [ContactPhoneNumber]
    let photoData: Data?

    var numbers: [String] { phoneNumbers.map(\.value) }

    /// A presentation-only contact with a stable identity. It is never written
    /// to the local repository and therefore cannot mutate Apple Contacts.
    var presentationContact: PhoneContact {
        PhoneContact(id: Self.presentationID(for: id), name: name, company: company,
                     numbers: numbers, photoData: photoData,
                     phoneNumberLabels: phoneNumbers.map(\.label))
    }

    /// Creates an intentionally independent TelefonX contact when the user
    /// explicitly chooses to copy this read-only entry.
    func localCopy() -> PhoneContact {
        PhoneContact(name: name, company: company, numbers: numbers, photoData: photoData,
                     phoneNumberLabels: phoneNumbers.map(\.label))
    }

    private static func presentationID(for identifier: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(identifier.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

protocol AppleContactsProviding: Sendable {
    func authorizationStatus() -> AppleContactsAuthorization
    func requestAccess() async throws -> Bool
    func fetch() async throws -> [AppleContact]
}

struct SystemAppleContactsProvider: AppleContactsProviding {
    func authorizationStatus() -> AppleContactsAuthorization {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }

    func requestAccess() async throws -> Bool {
        try await CNContactStore().requestAccess(for: .contacts)
    }

    func fetch() async throws -> [AppleContact] {
        try await Task.detached(priority: .userInitiated) {
            let keys: [CNKeyDescriptor] = [
                CNContactIdentifierKey as CNKeyDescriptor,
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactThumbnailImageDataKey as CNKeyDescriptor
            ]
            var result: [AppleContact] = []
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.unifyResults = true
            try CNContactStore().enumerateContacts(with: request) { contact, _ in
                guard let mapped = Self.convert(contact) else { return }
                result.append(mapped)
            }
            return result.sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
        }.value
    }

    static func convert(_ contact: CNContact, thumbnail: Data? = nil) -> AppleContact? {
        let numbers = contact.phoneNumbers.compactMap { labeled -> ContactPhoneNumber? in
            guard let value = try? CallDestination(labeled.value.stringValue).value else { return nil }
            return ContactPhoneNumber(value: value, label: phoneLabel(labeled.label))
        }
        guard let fallbackNumber = numbers.first else { return nil }
        let formatted = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        let name = formatted.isEmpty
            ? (contact.organizationName.isEmpty ? fallbackNumber.value : contact.organizationName)
            : formatted
        let photo = (thumbnail ?? contact.thumbnailImageData).flatMap { try? ContactPhotoCodec.thumbnail(from: $0) }
        return AppleContact(id: contact.identifier, name: name, company: contact.organizationName,
                            phoneNumbers: numbers, photoData: photo)
    }

    private static func phoneLabel(_ label: String?) -> ContactPhoneLabel {
        switch label {
        case CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone: .mobile
        case CNLabelHome: .home
        case CNLabelWork: .work
        default: .other
        }
    }

    static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") else { return }
        NSWorkspace.shared.open(url)
    }
}
