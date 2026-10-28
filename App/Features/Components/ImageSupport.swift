import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// UIKit-free image helpers (ImageIO) so the code also works on macOS.
enum ImageSupport {
    /// Downscales and JPEG-compresses image data (screenshots can be huge).
    static func compressedJPEG(from data: Data, maxPixel: Int = 1800, quality: CGFloat = 0.8) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return output as Data
    }

    static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

struct DataImage: View {
    let data: Data?
    var contentMode: ContentMode = .fill

    var body: some View {
        if let data, let cg = ImageSupport.cgImage(from: data) {
            Image(decorative: cg, scale: 1)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            Rectangle().fill(.quaternary)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }
}
