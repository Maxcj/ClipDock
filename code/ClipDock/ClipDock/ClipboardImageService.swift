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

    func saveImageAssets(fromFileAt fileURL: URL) -> SavedImageAssets? {
        let folderURL = Self.assetFolderURL()
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            guard let previewData = Self.thumbnailData(fromFileAt: fileURL, maxPixelSize: 1_600) else { return nil }

            let originalURL = folderURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
            try previewData.write(to: originalURL, options: .atomic)

            let thumbnailURL = folderURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("thumb.png")
            let thumbnailData = Self.thumbnailData(fromFileAt: fileURL, maxPixelSize: 420)
            if let thumbnailData {
                try thumbnailData.write(to: thumbnailURL, options: .atomic)
            } else {
                try previewData.write(to: thumbnailURL, options: .atomic)
            }

            return SavedImageAssets(original: originalURL, thumbnail: thumbnailURL, originalData: previewData, thumbnailData: thumbnailData)
        } catch {
            NSLog("Failed to save clipboard image file preview: \(error.localizedDescription)")
            return nil
        }
    }

    func fingerprintData(forFileAt fileURL: URL) -> Data {
        var pieces = [fileURL.standardizedFileURL.path]
        if let values = try? fileURL.resourceValues(forKeys: [.fileResourceIdentifierKey, .contentModificationDateKey, .fileSizeKey]) {
            if let fileResourceIdentifier = values.fileResourceIdentifier {
                pieces.append(String(describing: fileResourceIdentifier))
            }
            if let contentModificationDate = values.contentModificationDate {
                pieces.append(contentModificationDate.timeIntervalSince1970.description)
            }
            if let fileSize = values.fileSize {
                pieces.append(String(fileSize))
            }
        }
        return Data(pieces.joined(separator: "|").utf8)
    }

    private static func assetFolderURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let bundleName = Bundle.main.bundleIdentifier ?? "ClipDock"
        return base.appendingPathComponent(bundleName, isDirectory: true).appendingPathComponent("ClipboardImages", isDirectory: true)
    }

    private static func thumbnailData(from imageData: Data, maxPixelSize: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        return thumbnailData(from: source, maxPixelSize: maxPixelSize)
    }

    private static func thumbnailData(fromFileAt fileURL: URL, maxPixelSize: CGFloat) -> Data? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, options) else { return nil }
        return thumbnailData(from: source, maxPixelSize: maxPixelSize)
    }

    private static func thumbnailData(from source: CGImageSource, maxPixelSize: CGFloat) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}
