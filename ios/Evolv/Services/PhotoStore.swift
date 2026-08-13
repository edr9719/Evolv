import Foundation
import UIKit
import OSLog

/// Applies the user's explicit backup preference to Evolv's app-owned
/// Documents and Application Support directories. Apple backup remains allowed
/// unless local-only mode is deliberately enabled. The preference is mirrored
/// in UserDefaults so detached photo writes can enforce it without UI state.
enum DeviceBackupPolicy {
    static let preferenceKey = "evolv.localOnlyStorageEnabled"

    static func isLocalOnly(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: preferenceKey)
    }

    static func setLocalOnly(
        _ enabled: Bool,
        defaults: UserDefaults = .standard,
        documentsURL: URL? = nil
    ) throws {
        let urls = storageURLs(override: documentsURL)
        for url in urls {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try apply(excludeFromBackup: enabled, to: url)
        }
        defaults.set(enabled, forKey: preferenceKey)
    }

    static func applyStoredPreference(
        defaults: UserDefaults = .standard,
        documentsURL: URL? = nil
    ) throws {
        let enabled = isLocalOnly(defaults: defaults)
        for url in storageURLs(override: documentsURL) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try apply(excludeFromBackup: enabled, to: url)
        }
    }

    static func apply(excludeFromBackup: Bool, to url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = excludeFromBackup
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    static func isExcludedFromBackup(at url: URL) -> Bool? {
        try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
    }

    private static func storageURLs(override: URL?) -> [URL] {
        if let override { return [override] }
        let manager = FileManager.default
        return [
            manager.urls(for: .documentDirectory, in: .userDomainMask).first!,
            manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        ]
    }
}

/// Persists captured pose images to the app's Documents directory and loads them back.
enum PhotoStore {
    static let protectedWriteOptions: Data.WritingOptions = [.atomic, .completeFileProtection]

    struct PreparedPhoto {
        let image: UIImage
        let pixelSize: NormalizedPixelSize
    }

    enum StoreError: LocalizedError {
        case couldNotCreateDirectory
        case couldNotEncode
        case couldNotWrite

        var errorDescription: String? {
            switch self {
            case .couldNotCreateDirectory: return "Evolv couldn't prepare local photo storage."
            case .couldNotEncode: return "Evolv couldn't process this photo."
            case .couldNotWrite: return "Evolv couldn't save the photo to this device."
            }
        }
    }

    private static let logger = Logger(subsystem: "com.app.evolv", category: "PhotoStore")

    private static func folder() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        try? DeviceBackupPolicy.applyStoredPreference(documentsURL: docs)
        let url = docs.appendingPathComponent("scans", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                throw StoreError.couldNotCreateDirectory
            }
        }
        try? applyCompleteProtection(to: url)
        return url
    }

    private static func applyCompleteProtection(to url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    /// Renders UIImage orientation into upright pixels and caps the long edge so
    /// Vision, previews, and persistence all consume the same representation.
    static func prepare(_ image: UIImage, maxLongEdge: CGFloat = 2048) -> PreparedPhoto {
        let rawPixelSize: CGSize = image.cgImage.map {
            CGSize(width: $0.width, height: $0.height)
        } ?? CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let logicalSize: CGSize
        switch image.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            logicalSize = CGSize(width: rawPixelSize.height, height: rawPixelSize.width)
        default:
            logicalSize = rawPixelSize
        }
        let longest = max(logicalSize.width, logicalSize.height)
        let resizeScale = longest > maxLongEdge ? maxLongEdge / longest : 1
        let targetSize = CGSize(
            width: max(1, (logicalSize.width * resizeScale).rounded()),
            height: max(1, (logicalSize.height * resizeScale).rounded())
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let upright = UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return PreparedPhoto(
            image: upright,
            pixelSize: NormalizedPixelSize(width: Int(targetSize.width), height: Int(targetSize.height))
        )
    }

    /// JPEG encoding and atomic disk I/O run away from the main actor.
    @discardableResult
    static func save(_ image: UIImage, filename: String? = nil) async throws -> String {
        let name = filename ?? "\(UUID().uuidString).jpg"
        let started = ContinuousClock.now
        return try await Task.detached(priority: .utility) {
            guard let data = image.jpegData(compressionQuality: 0.90) else {
                logger.error("photo_save_failed reason=encode")
                throw StoreError.couldNotEncode
            }
            let directory = try folder()
            let url = directory.appendingPathComponent(name)
            do {
                try data.write(to: url, options: protectedWriteOptions)
                // Explicitly upgrade the finished destination as well. Atomic
                // writes replace the destination inode, so this closes a gap
                // on systems that do not carry directory protection forward.
                try? applyCompleteProtection(to: url)
                let elapsed = started.duration(to: .now)
                logger.info("photo_save_succeeded duration=\(String(describing: elapsed), privacy: .public)")
                return name
            } catch {
                logger.error("photo_save_failed reason=write")
                throw StoreError.couldNotWrite
            }
        }.value
    }

    /// Testable variant used to verify atomic-write failures without changing app storage.
    static func save(_ image: UIImage, filename: String, in directory: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            guard let data = image.jpegData(compressionQuality: 0.90) else {
                throw StoreError.couldNotEncode
            }
            let url = directory.appendingPathComponent(filename)
            do {
                try data.write(to: url, options: .atomic)
                return filename
            } catch {
                throw StoreError.couldNotWrite
            }
        }.value
    }

    static func loadImage(named name: String) -> UIImage? {
        guard let directory = try? folder() else { return nil }
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func delete(named name: String) {
        guard let directory = try? folder() else { return }
        let url = directory.appendingPathComponent(name)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            if (error as NSError).code != NSFileNoSuchFileError {
                logger.error("photo_delete_failed reason=file_io")
            }
        }
    }

    static func delete<S: Sequence>(named names: S) where S.Element == String {
        names.forEach { delete(named: $0) }
    }

    /// Upgrades photos created by earlier builds without re-encoding them.
    static func protectExistingFiles() {
        guard let directory = try? folder(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
              ) else { return }
        try? applyCompleteProtection(to: directory)
        for file in files where file.pathExtension.lowercased() == "jpg" {
            try? applyCompleteProtection(to: file)
        }
    }

    static func fileProtection(for name: String) -> FileProtectionType? {
        guard let directory = try? folder(),
              let attributes = try? FileManager.default.attributesOfItem(
                atPath: directory.appendingPathComponent(name).path
              ) else { return nil }
        return attributes[.protectionKey] as? FileProtectionType
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
