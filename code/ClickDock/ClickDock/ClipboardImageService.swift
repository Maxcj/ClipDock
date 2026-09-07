//
//  ClipboardImageService.swift
//  ClipDock
//

import AppKit
import ImageIO

final class ClipboardImageService {
    static let imageFileExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp", "avif", "icns"
    ]

    func saveImageAssets(from image: NSImage) -> SavedImageAssets? {
        let folderURL = Self.assetFolderURL()
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            guard let originalData = image.pngData() else { return nil }

            let originalURL = folderURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
            try originalData.write(to: originalURL, options: .atomic)

            let thumbnailURL = folderURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("thumb.png")
            let thumbnailData = Self.thumbnailData(from: originalData, maxPixelSize: 420)
            if let thumbnailData {
                try thumbnailData.write(to: thumbnailURL, options: .atomic)
            } else {
                try originalData.write(to: thumbnailURL, options: .atomic)
            }

            return SavedImageAssets(original: originalURL, thumbnail: thumbnailURL, originalData: originalData, thumbnailData: thumbnailData)
        } catch {
            NSLog("Failed to save clipboard image: \(error.localizedDescription)")
            return nil
        }
    }

    private static func assetFolderURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let bundleName = Bundle.main.bundleIdentifier ?? "ClipDock"
        return base.appendingPathComponent(bundleName, isDirectory: true).appendingPathComponent("ClipboardImages", isDirectory: true)
    }

    private static func thumbnailData(from imageData: Data, maxPixelSize: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}
