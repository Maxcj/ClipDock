//
//  ClipboardCaptureService.swift
//  ClipDock
//

import AppKit
import UniformTypeIdentifiers

enum ClipboardCaptureOutcome {
    case snapshot(ClipboardSnapshot)
    case dropped(reason: String)
}

final class ClipboardCaptureService {
    private let classifier: ClipboardClassifier
    private let imageService: ClipboardImageService

    init(classifier: ClipboardClassifier = ClipboardClassifier(), imageService: ClipboardImageService = ClipboardImageService()) {
        self.classifier = classifier
        self.imageService = imageService
    }

    func captureSnapshot(from pasteboard: NSPasteboard) -> ClipboardCaptureOutcome {
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        if ClipboardPrivacyRules.isExcluded(bundleIdentifier: bundleId) {
            return .dropped(reason: "excluded app \(bundleId ?? "-")")
        }

        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !fileURLs.isEmpty {
            return captureFileURLs(fileURLs, appName: appName, bundleId: bundleId)
        }

        if let image = NSImage(pasteboard: pasteboard) {
            return captureImage(image, appName: appName, bundleId: bundleId)
        }

        let urlType = NSPasteboard.PasteboardType(UTType.url.identifier)
        if let urlText = pasteboard.string(forType: urlType), ClipboardRecord.webURL(from: urlText) != nil {
            return captureURLText(urlText, appName: appName, bundleId: bundleId)
        }

        if let text = capturedPlainText(from: pasteboard), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return captureText(text, appName: appName, bundleId: bundleId)
        }

        return .dropped(reason: "no supported clipboard content")
    }

    private func captureFileURLs(_ fileURLs: [URL], appName: String?, bundleId: String?) -> ClipboardCaptureOutcome {
        let names = fileURLs.map { $0.lastPathComponent }
        let fullText = fileURLs.map(\.path).joined(separator: "\n")
        let isSingleImageFile = fileURLs.count == 1 && ClipboardImageService.imageFileExtensions.contains(fileURLs[0].pathExtension.lowercased())

        if let reason = ClipboardPrivacyRules.shouldIgnoreCapturedFileURLs(fileURLs) {
            return .dropped(reason: "ignored file URLs: \(reason.description)")
        }

        if let reason = ClipboardPrivacyRules.shouldIgnoreCapturedText(fullText, contentKind: .files) {
            return .dropped(reason: "ignored file text: \(reason.description)")
        }

        if isSingleImageFile {
            guard keepsImageHistory else { return .dropped(reason: "image history disabled") }
            guard let imageData = try? Data(contentsOf: fileURLs[0]),
                  let image = NSImage(data: imageData) ?? NSImage(contentsOf: fileURLs[0]),
                  let assets = imageService.saveImageAssets(from: image) else {
                return .dropped(reason: "failed to save image assets")
            }

            return .snapshot(ClipboardSnapshot(
                kind: .image,
                displayText: "Image",
                fullText: assets.original.path,
                imagePath: assets.original.path,
                assetPath: nil,
                thumbnailPath: assets.thumbnail.path,
                cachedSizeBytes: assets.cachedSizeBytes,
                sourceAppName: appName,
                sourceBundleId: bundleId,
                hash: classifier.hash(kind: .image, data: imageData),
                fileURLs: nil
            ))
        }

        guard keepsFileHistory else { return .dropped(reason: "file history disabled") }

        return .snapshot(ClipboardSnapshot(
            kind: .files,
            displayText: names.joined(separator: ", "),
            fullText: fullText,
            imagePath: nil,
            assetPath: nil,
            thumbnailPath: nil,
            cachedSizeBytes: 0,
            sourceAppName: appName,
            sourceBundleId: bundleId,
            hash: classifier.hash(kind: .files, text: fullText),
            fileURLs: fileHistoryCopyStrategy == .saveCopy ? fileURLs : nil
        ))
    }

    private func captureImage(_ image: NSImage, appName: String?, bundleId: String?) -> ClipboardCaptureOutcome {
        guard keepsImageHistory else { return .dropped(reason: "image history disabled") }
        guard let assets = imageService.saveImageAssets(from: image) else {
            return .dropped(reason: "failed to save image assets")
        }

        return .snapshot(ClipboardSnapshot(
            kind: .image,
            displayText: "Image",
            fullText: assets.original.path,
            imagePath: assets.original.path,
            assetPath: nil,
            thumbnailPath: assets.thumbnail.path,
            cachedSizeBytes: assets.cachedSizeBytes,
            sourceAppName: appName,
            sourceBundleId: bundleId,
            hash: classifier.hash(kind: .image, data: assets.originalData),
            fileURLs: nil
        ))
    }

    private func captureURLText(_ urlText: String, appName: String?, bundleId: String?) -> ClipboardCaptureOutcome {
        if let reason = ClipboardPrivacyRules.shouldIgnoreCapturedText(urlText, contentKind: .link) {
            return .dropped(reason: "ignored url text: \(reason.description)")
        }

        return .snapshot(ClipboardSnapshot(
            kind: .link,
            displayText: urlText,
            fullText: urlText,
            imagePath: nil,
            assetPath: nil,
            thumbnailPath: nil,
            cachedSizeBytes: 0,
            sourceAppName: appName,
            sourceBundleId: bundleId,
            hash: classifier.hash(kind: .link, text: urlText),
            fileURLs: nil
        ))
    }

    private func captureText(_ text: String, appName: String?, bundleId: String?) -> ClipboardCaptureOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let classification = classifier.classify(text: trimmed)

        if let reason = ClipboardPrivacyRules.shouldIgnoreCapturedText(trimmed, contentKind: classification.kind) {
            return .dropped(reason: "ignored captured text: \(reason.description)")
        }

        let displayText = classification.color?.displayText ?? classifier.previewText(from: trimmed)
        let fullText = classification.color?.sourceText ?? trimmed

        return .snapshot(ClipboardSnapshot(
            kind: classification.kind,
            displayText: displayText,
            fullText: fullText,
            imagePath: nil,
            assetPath: nil,
            thumbnailPath: nil,
            cachedSizeBytes: 0,
            sourceAppName: appName,
            sourceBundleId: bundleId,
            hash: classifier.hash(kind: classification.kind, text: fullText),
            fileURLs: nil
        ))
    }

    private func capturedPlainText(from pasteboard: NSPasteboard) -> String? {
        let plainTextTypes: [NSPasteboard.PasteboardType] = [
            .string,
            NSPasteboard.PasteboardType(UTType.utf8PlainText.identifier),
            NSPasteboard.PasteboardType(UTType.plainText.identifier)
        ]

        for type in plainTextTypes {
            if let text = pasteboard.string(forType: type), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }

        if let rtfText = attributedPlainText(from: pasteboard, type: NSPasteboard.PasteboardType(UTType.rtf.identifier), documentType: .rtf) {
            return rtfText
        }

        if let htmlText = attributedPlainText(from: pasteboard, type: NSPasteboard.PasteboardType(UTType.html.identifier), documentType: .html) {
            return htmlText
        }

        for type in [NSPasteboard.PasteboardType(UTType.html.identifier), NSPasteboard.PasteboardType(UTType.rtf.identifier)] {
            if let text = pasteboard.string(forType: type), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }

        return nil
    }

    private func attributedPlainText(from pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType, documentType: NSAttributedString.DocumentType) -> String? {
        guard let data = pasteboard.data(forType: type) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any]
        if documentType == .html {
            options = [.documentType: documentType, .characterEncoding: String.Encoding.utf8.rawValue]
        } else {
            options = [.documentType: documentType]
        }

        guard let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else { return nil }
        let text = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : attributed.string
    }

    private var keepsImageHistory: Bool {
        UserDefaults.standard.object(forKey: "clipboard.keepImages") as? Bool ?? true
    }

    private var keepsFileHistory: Bool {
        UserDefaults.standard.object(forKey: "clipboard.keepFiles") as? Bool ?? false
    }

    private var fileHistoryCopyStrategy: FileHistoryCopyStrategy {
        let rawValue = UserDefaults.standard.object(forKey: "clipboard.fileHistoryCopyStrategy") as? Int ?? FileHistoryCopyStrategy.pathOnly.rawValue
        return FileHistoryCopyStrategy(rawValue: rawValue) ?? .pathOnly
    }
}
