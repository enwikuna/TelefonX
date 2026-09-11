#if DEBUG
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Synthetic pixel fixture for round cropping, never a real person's photo.
enum PreviewContactPhoto {
    static func make() -> Data? {
        guard let context = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0.18, green: 0.48, blue: 0.60, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        context.setFillColor(CGColor(red: 0.92, green: 0.75, blue: 0.40, alpha: 1))
        context.fillEllipse(in: CGRect(x: 78, y: 124, width: 100, height: 100))
        context.fillEllipse(in: CGRect(x: 28, y: -78, width: 200, height: 200))
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return try? ContactPhotoCodec.thumbnail(from: data as Data)
    }
}
#endif
