import Foundation
import Testing
import ImageIO
import UniformTypeIdentifiers
import Contacts
import TelefonDomain
import TelefonData
@testable import TelefonX

@Suite struct ContactAvatarTests {
    @Test func namesUseApplesAbbreviatedFormatter() {
        let locale = Locale(identifier: "de_DE")
        #expect(ContactAvatarPresentation.monogram(name: "Peter Gmelin", locale: locale) == "PG")
        #expect(ContactAvatarPresentation.monogram(name: "Zuhause", locale: locale) == "Z")
        #expect(ContactAvatarPresentation.monogram(name: "  Élodie Müller  ", locale: locale) == "ÉM")
        #expect(ContactAvatarPresentation.monogram(name: "Nord Büro", company: "Nord Büro", locale: locale) == "N")
        for name in ["李小明", "김민수", "Jean-Pierre Dupont", "Dr. Max Mustermann", "Evi ❤️"] {
            let initials = ContactAvatarPresentation.monogram(name: name, locale: locale)
            #expect(initials != nil)
            #expect((initials?.count ?? 0) <= 3)
        }
    }

    @Test(arguments: ["", "  ", "+49 711 123456", "101", "sip:alex@example.com", "Unknown", "anonymous", "❤️"])
    func noInventedInitialsForMissingNames(_ name: String) {
        #expect(ContactAvatarPresentation.monogram(name: name) == nil)
    }

    @Test func contactIdentityIsStableAcrossEncodingAndEditing() throws {
        let original = PhoneContact(name: "Alex Beispiel", numbers: ["101"])
        var decoded = try JSONDecoder().decode(PhoneContact.self, from: JSONEncoder().encode(original))
        #expect(ContactAvatarPresentation.colorComponents(for: original.id) == ContactAvatarPresentation.colorComponents(for: decoded.id))
        decoded.name = "Alex Neuer Name"
        #expect(ContactAvatarPresentation.colorComponents(for: original.id) == ContactAvatarPresentation.colorComponents(for: decoded.id))
        let color = ContactAvatarPresentation.colorComponents(for: original.id)
        #expect((0...1).contains(color.red))
        #expect((0...1).contains(color.green))
        #expect((0...1).contains(color.blue))
    }

    @Test func differentContactIdentitiesDoNotCollapseOntoASmallPalette() {
        let identities = (1...24).map { value in
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
        }
        let colors = identities.map(ContactAvatarPresentation.colorComponents)
        #expect(Set(colors).count >= 22)
    }

    @Test func oldContactPayloadAndPhotoBackupRoundtrip() throws {
        let original = PhoneContact(name: "Alex", numbers: ["101"])
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "photoData")
        let old = try JSONDecoder().decode(PhoneContact.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old == original)
        var snapshot = AppSnapshot()
        var withPhoto = original
        withPhoto.photoData = try ContactPhotoCodec.thumbnail(from: sourceImage())
        snapshot.contacts = [withPhoto]
        #expect(try BackupCodec.decode(BackupCodec.encode(snapshot)) == snapshot)
        // CSV deliberately remains text-only.
        #expect(try ContactsCSV.decode(ContactsCSV.encode(snapshot.contacts)).first?.photoData == nil)
        snapshot.contacts[0].photoData = Data(repeating: 0, count: PhoneContact.maximumPhotoBytes + 1)
        #expect(throws: ValidationError.invalidBackup) { try snapshot.validate() }
    }

    @Test func photoIsBoundedSquareAndStripsSourceMetadata() throws {
        let original = try sourceImage()
        let thumbnail = try ContactPhotoCodec.thumbnail(from: original)
        #expect(thumbnail.count <= PhoneContact.maximumPhotoBytes)
        let source = try #require(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        #expect(properties[kCGImagePropertyPixelWidth as String] as? Int == 128)
        #expect(properties[kCGImagePropertyPixelHeight as String] as? Int == 128)
        #expect(properties[kCGImagePropertyGPSDictionary as String] == nil)
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal as String] == nil)
        #expect(exif?[kCGImagePropertyExifUserComment as String] == nil)
        #expect(properties[kCGImagePropertyTIFFDictionary as String] == nil)
        #expect(ContactPhotoCodec.decode(Data("not an image".utf8)) == nil)
        #expect(throws: (any Error).self) { try ContactPhotoCodec.thumbnail(from: Data()) }
        #expect(throws: (any Error).self) { try ContactPhotoCodec.thumbnail(from: Data(repeating: 0, count: ContactPhotoCodec.maximumImportBytes + 1)) }
    }

    @Test func photoHonorsOrientationAndFlattensTransparencyOnWhite() throws {
        let context = try #require(CGContext(data: nil, width: 100, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: 100, height: 50))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 50, y: 0, width: 50, height: 50))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let oriented = try #require(ContactPhotoCodec.decode(data as Data))
        #expect(oriented.width == 50 && oriented.height == 100)
        let image = try #require(ContactPhotoCodec.decode(ContactPhotoCodec.thumbnail(from: data as Data)))
        #expect(image.width == 50 && image.height == 50)
        var pixels = [UInt8](repeating: 0, count: 50 * 50 * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let canvas = try #require(CGContext(data: bytes.baseAddress, width: 50, height: 50, bitsPerComponent: 8, bytesPerRow: 200,
                                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            canvas.draw(image, in: CGRect(x: 0, y: 0, width: 50, height: 50))
        }
        let offsets = stride(from: 0, to: pixels.count, by: 4)
        #expect(offsets.contains { pixels[$0] > 240 && pixels[$0 + 1] > 240 && pixels[$0 + 2] > 240 })
        #expect(offsets.contains { pixels[$0] > 200 && pixels[$0 + 1] < 40 && pixels[$0 + 2] < 40 })
    }

    @Test @MainActor func photoPersistsEditsAndRemovalWithoutTouchingSource() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TelefonX-photo-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "test-image.jpg"), original = try sourceImage()
        try original.write(to: source)
        let photo = try ContactPhotoCodec.importFile(source)
        #expect(try Data(contentsOf: source) == original)
        var snapshot = AppSnapshot()
        snapshot.contacts = [PhoneContact(name: "Alex", numbers: ["101"], photoData: photo)]
        let storeURL = folder.appending(path: "store")
        do { let repo = try SwiftDataRepository(url: storeURL); try repo.save(snapshot) }
        let repo = try SwiftDataRepository(url: storeURL)
        #expect(try repo.load() == snapshot)
        snapshot.contacts[0].notes = "Bearbeitet"; try repo.save(snapshot)
        #expect(try repo.load().contacts[0].photoData == photo)
        snapshot.contacts[0].photoData = nil; try repo.save(snapshot)
        #expect(try repo.load().contacts[0].photoData == nil)
        #expect(try Data(contentsOf: source) == original)
        #expect(ContactPhotoCache.image(for: photo) != nil)
        #expect(ContactPhotoCache.image(for: Data("invalid".utf8)) == nil)
    }

    @Test func appleContactMappingCopiesPhotoWithoutAddressBookAccess() throws {
        let source = CNMutableContact()
        source.givenName = "Alex"; source.familyName = "Beispiel"
        source.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "101"))]
        source.imageData = try sourceImage()
        // CNMutableContact does not synthesize thumbnailImageData until stored.
        // Supply the same data boundary that fetch() gets from the contact store.
        let apple = try #require(SystemAppleContactsProvider.convert(source, thumbnail: source.imageData))
        #expect(apple.name.contains("Alex"))
        #expect(apple.numbers == ["101"])
        #expect(apple.phoneNumbers == [ContactPhoneNumber(value: "101", label: .mobile)])
        #expect(apple.photoData != nil)
        #expect(apple.photoData != source.imageData)
        let local = apple.localCopy()
        #expect(local.id != apple.presentationContact.id)
        #expect(local.phoneNumbers == apple.phoneNumbers)
        source.phoneNumbers = []
        #expect(SystemAppleContactsProvider.convert(source) == nil)
    }

    #if DEBUG
    @Test @MainActor func sameContactImageResolvesForAllItsNumbers() throws {
        let model = PreviewFixtures.makeModel()
        let contact = PhoneContact(name: "Alex", numbers: ["0711 1234567", "102"], photoData: try ContactPhotoCodec.thumbnail(from: sourceImage()))
        model.snapshot.contacts = [contact]
        #expect(model.contact(for: "+497111234567") == contact)
        #expect(model.contact(for: "102") == contact)
        #expect(model.contact(for: "103") == nil)
        #expect(model.contact(for: "anonymous") == nil)
        #expect(model.displayName("anonymous") == "Unknown")
    }
    #endif

    private func sourceImage() throws -> Data {
        let context = try #require(CGContext(data: nil, width: 512, height: 256, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 512, height: 256))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 1.0],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:01:01 12:00:00", kCGImagePropertyExifUserComment: "Private source note"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "Synthetic test"]] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
