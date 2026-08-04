import Foundation
import UIKit

/// Persists captured pose images to the app's Documents directory and loads them back.
enum PhotoStore {
    private static var folder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("scans", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    @discardableResult
    static func save(_ image: UIImage, filename: String? = nil) -> String? {
        let name = filename ?? "\(UUID().uuidString).jpg"
        let url = folder.appendingPathComponent(name)
        guard let data = image.jpegData(compressionQuality: 0.86) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func loadImage(named name: String) -> UIImage? {
        let url = folder.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func delete(named name: String) {
        let url = folder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Image analysis (local, lightweight)

    /// Returns avg brightness (0–1) and width/height aspect ratio for the supplied image.
    static func analyze(_ image: UIImage) -> (brightness: Double, aspect: Double) {
        let aspect = Double(image.size.width / max(1, image.size.height))
        let brightness = averageBrightness(of: image)
        return (brightness, aspect)
    }

    private static func averageBrightness(of image: UIImage) -> Double {
        // Downscale to a tiny 8×8 sample for speed
        let size = CGSize(width: 8, height: 8)
        UIGraphicsBeginImageContextWithOptions(size, true, 1)
        image.draw(in: CGRect(origin: .zero, size: size))
        let small = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let cgImage = small?.cgImage,
              let provider = cgImage.dataProvider,
              let data = provider.data,
              let bytes = CFDataGetBytePtr(data) else { return 0.5 }

        let count = CFDataGetLength(data)
        guard count >= 4 else { return 0.5 }
        var total = 0.0
        var pixels = 0
        let bpp = cgImage.bitsPerPixel / 8
        var i = 0
        while i + 2 < count {
            let r = Double(bytes[i])
            let g = Double(bytes[i + 1])
            let b = Double(bytes[i + 2])
            // luma
            total += 0.2126 * r + 0.7152 * g + 0.0722 * b
            pixels += 1
            i += bpp
        }
        guard pixels > 0 else { return 0.5 }
        return (total / Double(pixels)) / 255.0
    }
}
