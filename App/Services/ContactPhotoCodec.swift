import Foundation
import ImageIO
import UniformTypeIdentifiers
import TelefonDomain

enum ContactPhotoCodec {
    static let maximumImportBytes = 20_000_000

    static func importFile(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= maximumImportBytes else { throw PhotoError.invalidImage }
        return try thumbnail(from: Data(contentsOf: url))
    }

    /// ImageIO downsamples before decoding. Only pixels are exported, never source EXIF/GPS metadata.
    static func thumbnail(from data: Data) throws -> Data {
        guard data.count <= maximumImportBytes, let image = decode(data) else { throw PhotoError.invalidImage }
        let side = min(image.width, image.height)
        guard let square = image.cropping(to: CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2,
                                                     width: side, height: side)) else { throw PhotoError.invalidImage }
        guard let canvas = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw PhotoError.invalidImage }
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        canvas.setFillColor(CGColor(gray: 1, alpha: 1)); canvas.fill(bounds)
        canvas.draw(square, in: bounds)
        guard let opaque = canvas.makeImage() else { throw PhotoError.invalidImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw PhotoError.invalidImage }
        CGImageDestinationAddImage(destination, opaque, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= PhoneContact.maximumPhotoBytes else { throw PhotoError.invalidImage }
        return output as Data
    }

    static func decode(_ data: Data) -> CGImage? {
        guard !data.isEmpty, data.count <= maximumImportBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0, height > 0, width <= 100_000, height <= 100_000,
              Int64(width) * Int64(height) <= 100_000_000 else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    enum PhotoError: LocalizedError {
        case invalidImage
        var errorDescription: String? { L10n.text("This image cannot be used. Choose an image up to 20 MB and 100 megapixels, such as JPEG, PNG, or HEIC.") }
    }
}

@MainActor enum ContactPhotoCache {
    private static let images: NSCache<NSData, CGImage> = {
        let cache = NSCache<NSData, CGImage>()
        cache.totalCostLimit = 8_000_000
        cache.countLimit = 64
        return cache
    }()

    static func image(for data: Data?) -> CGImage? {
        guard let data, data.count <= PhoneContact.maximumPhotoBytes else { return nil }
        let key = data as NSData
        if let image = images.object(forKey: key) { return image }
        guard let image = ContactPhotoCodec.decode(data) else { return nil }
        images.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
}
