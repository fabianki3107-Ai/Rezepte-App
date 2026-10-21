import UIKit

/// Bildaufbereitung für Speicherung: kompakte Hero-Bilder und kleine Thumbnails für Listen.
enum ImageProcessing {
    static let heroMaxPixel: CGFloat = 1600
    static let thumbnailMaxPixel: CGFloat = 400

    /// JPEG-komprimiertes Hero-Bild (max. 1600 px Kante), um den Store klein zu halten.
    static func heroData(from image: UIImage) -> Data? {
        resized(image, maxPixel: heroMaxPixel)?.jpegData(compressionQuality: 0.82)
    }

    /// Kleines Thumbnail für die Bibliothek – wird in der Liste statt des großen Bildes dekodiert.
    static func thumbnailData(from imageData: Data) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }
        return resized(image, maxPixel: thumbnailMaxPixel)?.jpegData(compressionQuality: 0.75)
    }

    static func resized(_ image: UIImage, maxPixel: CGFloat) -> UIImage? {
        let size = image.size
        let scale = image.scale
        let longest = max(size.width, size.height) * scale
        guard longest > 0 else { return nil }
        if longest <= maxPixel {
            return image.normalizedOrientation()
        }
        let factor = maxPixel / longest
        let target = CGSize(width: (size.width * scale * factor).rounded(), height: (size.height * scale * factor).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

extension UIImage {
    /// Zeichnet das Bild in `.up`-Orientierung neu, damit EXIF-Rotation nicht verloren geht.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
