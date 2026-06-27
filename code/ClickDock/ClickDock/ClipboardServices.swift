//
//  ClipboardServices.swift
//  ClipDock
//

import AppKit
import Combine
import CoreData
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

final class ClipboardMonitor: ObservableObject {
    private enum CaptureOutcome {
        case snapshot(ClipboardSnapshot)
        case dropped(reason: String)
    }

    private let context: NSManagedObjectContext
    private let linkMetadataManager: LinkMetadataManager
    private let processingQueue = DispatchQueue(label: "cn.maxcj.ClipDock.clipboard.processing", qos: .userInitiated)
    private var timer: Timer?
    private var cleanupTimer: Timer?
    private var lastChangeCount: Int = -1
    private var lastRecordedHash: String?
    private var suppressionChangeCount: Int?
    private var isProcessingSnapshot = false

    init(context: NSManagedObjectContext) {
        self.context = context
        self.linkMetadataManager = LinkMetadataManager(context: context)
    }

    func start() {
        guard timer == nil else { return }
        lastRecordedHash = fetchLatestHash()
        lastChangeCount = NSPasteboard.general.changeCount

        timer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer!, forMode: .common)

        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.pruneExpiredRecords()
        }
        if let cleanupTimer {
            RunLoop.main.add(cleanupTimer, forMode: .common)
        }
        pruneExpiredRecords()
        linkMetadataManager.refreshMissingMetadata()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }

    func copy(_ record: ClipboardRecord) {
        guard let kind = ClipboardContentKind(rawValue: record.contentTypeRaw ?? "") else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch kind {
        case .text, .code, .colors, .unknown:
            pasteboard.setString(record.fullText ?? record.displayText ?? "", forType: .string)
        case .link:
            let value = record.fullText ?? record.displayText ?? ""
            pasteboard.setString(value, forType: .string)
            if let url = URL(string: value) {
                pasteboard.writeObjects([url as NSURL])
            }
        case .files:
            let fileURLs = record.fileReferenceSet.preferredURLsForPasteboard
            if !fileURLs.isEmpty {
                pasteboard.writeObjects(fileURLs.map { $0 as NSURL })
            } else if let text = record.fullText ?? record.displayText {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let imagePath = record.imagePath, let image = ClipboardImageCache.shared.image(at: imagePath) {
                pasteboard.writeObjects([image])
            }
        }

        markSuppression(changeCount: pasteboard.changeCount)
    }

    private func poll() {
        guard !isProcessingSnapshot else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        isProcessingSnapshot = true

        processingQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let outcome = self.captureSnapshot(from: pasteboard)

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    defer { self.isProcessingSnapshot = false }

                    switch outcome {
                    case .dropped(let reason):
                        self.logClipboardDrop(reason)
                        return
                    case .snapshot(let snapshot):
                        if let suppressionChangeCount,
                           pasteboard.changeCount == suppressionChangeCount {
                            self.suppressionChangeCount = nil
                            self.logClipboardDrop("suppressed self-copy")
                            return
                        }

                        if snapshot.hash == lastRecordedHash {
                            self.logClipboardDrop("duplicate content")
                            return
                        }

                        self.insert(snapshot: snapshot)
                        self.lastRecordedHash = snapshot.hash
                    }
                }
            }
        }
    }

    private func captureSnapshot(from pasteboard: NSPasteboard) -> CaptureOutcome {
        let appName = currentFrontmostApplicationName()
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        if ClipboardPrivacyRules.isExcluded(bundleIdentifier: bundleId) {
            return .dropped(reason: "excluded app \(bundleId ?? "-")")
        }

        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !fileURLs.isEmpty {
            let names = fileURLs.map { $0.lastPathComponent }
            let fullText = fileURLs.map(\.path).joined(separator: "\n")
            let isSingleImageFile = fileURLs.count == 1 && Self.imageFileExtensions.contains(fileURLs[0].pathExtension.lowercased())

            if let reason = ClipboardPrivacyRules.shouldIgnoreCapturedFileURLs(fileURLs) {
                return .dropped(reason: "ignored file URLs: \(reason.description)")
            }

            if let reason = ClipboardPrivacyRules.shouldIgnoreCapturedText(fullText, contentKind: .files) {
                return .dropped(reason: "ignored file text: \(reason.description)")
            }

            if isSingleImageFile {
                guard keepsImageHistory else { return .dropped(reason: "image history disabled") }

                if let imageData = try? Data(contentsOf: fileURLs[0]), let image = NSImage(data: imageData) ?? NSImage(contentsOf: fileURLs[0]), let assets = saveImageAssets(from: image) {
                    return .snapshot(ClipboardSnapshot(
                        kind: .image,
                        displayText: "Image",
                        fullText: assets.original.path,
                        imagePath: assets.original.path,
                        assetPath: nil,
                        thumbnailPath: assets.thumbnail.path,
                        sourceAppName: appName,
                        sourceBundleId: bundleId,
                        hash: Self.hash(kind: .image, data: imageData)
                    ))
                }

                return .dropped(reason: "failed to save image assets")
            }

            guard keepsFileHistory else { return .dropped(reason: "file history disabled") }

            return .snapshot(ClipboardSnapshot(
                kind: .files,
                displayText: names.joined(separator: ", "),
                fullText: fullText,
                imagePath: nil,
                assetPath: nil,
                thumbnailPath: nil,
                sourceAppName: appName,
                sourceBundleId: bundleId,
                hash: Self.hash(kind: .files, text: fullText)
            ))
        }

        if let image = NSImage(pasteboard: pasteboard), let assets = saveImageAssets(from: image) {
            return .snapshot(ClipboardSnapshot(
                kind: .image,
                displayText: "Image",
                fullText: assets.original.path,
                imagePath: assets.original.path,
                assetPath: nil,
                thumbnailPath: assets.thumbnail.path,
                sourceAppName: appName,
                sourceBundleId: bundleId,
                hash: Self.hash(kind: .image, data: assets.originalData)
            ))
        }

        let urlType = NSPasteboard.PasteboardType(UTType.url.identifier)
        if let urlText = pasteboard.string(forType: urlType),
           ClipboardRecord.webURL(from: urlText) != nil {
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
                sourceAppName: appName,
                sourceBundleId: bundleId,
                hash: Self.hash(kind: .link, text: urlText)
            ))
        }

        if let text = capturedPlainText(from: pasteboard), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let detectedColor = ClipboardColorDetector.detect(from: trimmed)
            let kind: ClipboardContentKind
            if ClipboardRecord.webURL(from: trimmed) != nil {
                kind = .link
            } else if detectedColor != nil {
                kind = .colors
            } else if isLikelyCode(trimmed) || ClipboardCodeLanguageDetector.detect(from: trimmed) != .plain {
                kind = .code
            } else {
                kind = .text
            }

            if let reason = ClipboardPrivacyRules.shouldIgnoreCapturedText(trimmed, contentKind: kind) {
                return .dropped(reason: "ignored captured text: \(reason.description)")
            }

            if kind == .colors, let color = detectedColor {
                return .snapshot(ClipboardSnapshot(
                    kind: kind,
                    displayText: color.displayText,
                    fullText: color.sourceText,
                    imagePath: nil,
                    assetPath: nil,
                    thumbnailPath: nil,
                    sourceAppName: appName,
                    sourceBundleId: bundleId,
                    hash: Self.hash(kind: kind, text: color.sourceText)
                ))
            }

            return .snapshot(ClipboardSnapshot(
                kind: kind,
                displayText: previewText(from: trimmed),
                fullText: trimmed,
                imagePath: nil,
                assetPath: nil,
                thumbnailPath: nil,
                sourceAppName: appName,
                sourceBundleId: bundleId,
                hash: Self.hash(kind: kind, text: trimmed)
            ))
        }

        return .dropped(reason: "no supported clipboard content")
    }

    private func capturedPlainText(from pasteboard: NSPasteboard) -> String? {
        let candidateTypes: [NSPasteboard.PasteboardType] = [
            .string,
            NSPasteboard.PasteboardType(UTType.utf8PlainText.identifier),
            NSPasteboard.PasteboardType(UTType.plainText.identifier),
            NSPasteboard.PasteboardType(UTType.rtf.identifier),
            NSPasteboard.PasteboardType(UTType.html.identifier)
        ]

        for type in candidateTypes {
            if let text = pasteboard.string(forType: type),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }

        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.rtf.identifier)),
           let attributed = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            let text = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return attributed.string
            }
        }

        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.html.identifier)),
           let attributed = try? NSAttributedString(
               data: data,
               options: [
                   .documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue
               ],
               documentAttributes: nil
           ) {
            let text = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return attributed.string
            }
        }

        return nil
    }

    private var keepsImageHistory: Bool {
        UserDefaults.standard.object(forKey: "clipboard.keepImages") as? Bool ?? true
    }

    private var keepsFileHistory: Bool {
        UserDefaults.standard.object(forKey: "clipboard.keepFiles") as? Bool ?? false
    }

    private func insert(snapshot: ClipboardSnapshot) {
        context.perform {
            do {
                let existingRecords = try self.fetchMatchingRecords(for: snapshot)
                let record: ClipboardRecord

                if let canonicalRecord = existingRecords.sorted(by: Self.preferredDuplicateOrder).first {
                    record = canonicalRecord
                    self.update(record, with: snapshot)

                    for duplicate in existingRecords where duplicate.objectID != canonicalRecord.objectID {
                        removeCachedAssets(for: duplicate)
                        self.context.delete(duplicate)
                    }
                } else {
                    record = ClipboardRecord(context: self.context)
                    record.id = UUID()
                    record.createdAt = Date()
                    record.lastUsedAt = nil
                    record.isPinned = false
                    record.isIgnored = false
                    record.usageCount = 0
                    self.update(record, with: snapshot)
                }

                try self.context.save()
                self.pruneExpiredRecordsLocked()
                if snapshot.kind == .link,
                   let url = ClipboardRecord.webURL(from: snapshot.fullText ?? snapshot.displayText),
                   record.linkMetadataCheckedAtValue == nil {
                    self.linkMetadataManager.scheduleMetadataFetch(for: record.objectID, url: url)
                }
            } catch {
                NSLog("Failed to save clipboard record: \(error.localizedDescription)")
            }
        }
    }

    private func logClipboardDrop(_ reason: String) {
        let appName = currentFrontmostApplicationName() ?? "-"
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-"
        NSLog("Clipboard not recorded: \(reason) | app=\(appName) | bundle=\(bundleId)")
    }

    private func fetchMatchingRecords(for snapshot: ClipboardSnapshot) throws -> [ClipboardRecord] {
        let request = NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")

        switch snapshot.kind {
        case .image, .files:
            request.predicate = NSPredicate(format: "contentHash == %@", snapshot.hash)
        case .text, .link, .code, .colors, .unknown:
            let predicates: [NSPredicate] = [
                NSPredicate(format: "fullText == %@", snapshot.fullText ?? snapshot.displayText),
                NSPredicate(format: "contentHash == %@", snapshot.hash)
            ]
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        }

        request.fetchBatchSize = 32
        return try context.fetch(request)
    }

    private static func preferredDuplicateOrder(_ lhs: ClipboardRecord, _ rhs: ClipboardRecord) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }

        let lhsDate = lhs.createdAt ?? lhs.updatedAt ?? .distantPast
        let rhsDate = rhs.createdAt ?? rhs.updatedAt ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }

        return lhs.objectID.uriRepresentation().absoluteString < rhs.objectID.uriRepresentation().absoluteString
    }

    private func update(_ record: ClipboardRecord, with snapshot: ClipboardSnapshot) {
        let previousKind = record.kind

        record.updatedAt = Date()
        record.contentTypeRaw = snapshot.kind.rawValue
        record.displayText = snapshot.displayText
        record.fullText = snapshot.fullText
        record.imagePath = snapshot.imagePath
        if let assetPath = snapshot.assetPath {
            record.setValue(assetPath, forKey: "assetPath")
        }
        if let thumbnailPath = snapshot.thumbnailPath {
            record.setValue(thumbnailPath, forKey: "thumbnailPath")
        }
        record.sourceAppName = snapshot.sourceAppName
        record.sourceBundleId = snapshot.sourceBundleId
        record.contentHash = snapshot.hash

        if snapshot.kind == .link,
           let url = ClipboardRecord.webURL(from: snapshot.fullText ?? snapshot.displayText) {
            record.linkHostValue = url.host?.trimmingCharacters(in: .whitespacesAndNewlines)
            if previousKind != .link {
                record.linkTitleValue = nil
                record.linkIconDataValue = nil
                record.linkMetadataCheckedAtValue = nil
            }
        } else {
            record.linkHostValue = nil
            record.linkTitleValue = nil
            record.linkIconDataValue = nil
            record.linkMetadataCheckedAtValue = nil
        }
    }

    private func pruneExpiredRecords() {
        context.perform { [weak self] in
            self?.pruneExpiredRecordsLocked()
        }
    }

    private func pruneExpiredRecordsLocked() {
        let retention = RetentionRule.current()
        guard retention.isEnabled, let cutoff = retention.cutoffDate else { return }

        let request = NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "isPinned == NO"),
            NSPredicate(format: "createdAt < %@", cutoff as NSDate)
        ])

        do {
            let expiredRecords = try self.context.fetch(request)
            expiredRecords.forEach { record in
                removeCachedAssets(for: record)
                self.context.delete(record)
            }
            if self.context.hasChanges {
                try self.context.save()
            }
        } catch {
            NSLog("Failed to prune clipboard history: \(error.localizedDescription)")
        }
    }

    private func saveImageAssets(from image: NSImage) -> SavedImageAssets? {
        let folderURL = Self.assetFolderURL()
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            guard let originalData = image.pngData() else { return nil }

            let originalURL = folderURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
            try originalData.write(to: originalURL, options: .atomic)

            let thumbnailURL = folderURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("thumb.png")
            if let thumbnailData = Self.thumbnailData(from: originalData, maxPixelSize: 420) {
                try thumbnailData.write(to: thumbnailURL, options: .atomic)
            } else {
                try originalData.write(to: thumbnailURL, options: .atomic)
            }

            return SavedImageAssets(original: originalURL, thumbnail: thumbnailURL, originalData: originalData)
        } catch {
            NSLog("Failed to save clipboard image: \(error.localizedDescription)")
            return nil
        }
    }

    private func currentFrontmostApplicationName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    private func fetchLatestHash() -> String? {
        let request = NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = 1
        do {
            return try context.fetch(request).first?.contentHash
        } catch {
            return nil
        }
    }

    private func markSuppression(changeCount: Int) {
        suppressionChangeCount = changeCount
    }

    private static func hash(kind: ClipboardContentKind, text: String) -> String {
        switch kind {
        case .image, .files:
            return hash(kind: kind, data: Data(text.utf8))
        case .text, .link, .code, .colors, .unknown:
            return text
        }
    }

    private static func thumbnailData(from imageData: Data, maxPixelSize: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }

    private static func hash(kind: ClipboardContentKind, data: Data) -> String {
        let digest = SHA256.hash(data: Data(kind.rawValue.utf8) + data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func isLikelyCode(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
        guard !lines.isEmpty else { return false }

        let codeKeywords = [
            "func ", "class ", "struct ", "enum ", "protocol ", "extension ",
            "import ", "let ", "var ", "const ", "public ", "private ",
            "if ", "for ", "while ", "switch ", "case ", "return ",
            "def ", "from ", "export ", "interface ", "typealias "
        ]
        let codeSymbols = ["{", "}", ";", "=>", "->", "==", "!=", "&&", "||", "<-", ":</", "</", "</", "(", ")", "[", "]"]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if lines.count >= 2 {
            if lines.contains(where: { $0.hasPrefix("    ") || $0.hasPrefix("\t") }) {
                return true
            }

            if lines.contains(where: { $0.contains("{") || $0.contains("}") || $0.contains(";") }) {
                return true
            }
        }

        let lowercased = trimmed.lowercased()
        if codeKeywords.contains(where: { lowercased.contains($0) }) {
            return true
        }

        let symbolHits = codeSymbols.reduce(0) { count, symbol in
            count + (trimmed.contains(symbol) ? 1 : 0)
        }
        if symbolHits >= 2 {
            return true
        }

        if trimmed.contains("```") || trimmed.contains("    ") {
            return true
        }

        return false
    }

    private func previewText(from text: String) -> String {
        let limit = 120
        guard text.count > limit else { return text }
        let index = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<index]) + "…"
    }

    private static func assetFolderURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let bundleName = Bundle.main.bundleIdentifier ?? "ClipDock"
        return base.appendingPathComponent(bundleName, isDirectory: true)
            .appendingPathComponent("ClipboardImages", isDirectory: true)
    }
}

final class LinkMetadataManager {
    private let context: NSManagedObjectContext
    private var inFlightRecordIDs: Set<String> = []

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func refreshMissingMetadata() {
        context.performAndWait {
            let request = NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")
            request.predicate = NSPredicate(
                format: "contentTypeRaw == %@ AND (linkTitle == nil OR linkIconData == nil OR linkMetadataCheckedAt == nil)",
                ClipboardContentKind.link.rawValue
            )
            request.fetchBatchSize = 25

            guard let records = try? self.context.fetch(request) else { return }
            for record in records {
                guard let url = record.linkURL else { continue }
                self.scheduleMetadataFetch(for: record.objectID, url: url)
            }
        }
    }

    func scheduleMetadataFetch(for recordID: NSManagedObjectID, url: URL) {
        let key = recordID.uriRepresentation().absoluteString
        guard inFlightRecordIDs.insert(key).inserted else { return }

        Task.detached(priority: .utility) { [weak self] in
            let metadata = await LinkMetadataFetcher.fetch(from: url)
            guard let self else { return }
            self.apply(metadata: metadata, for: recordID, url: url)
            self.inFlightRecordIDs.remove(key)
        }
    }

    private func apply(metadata: LinkMetadata?, for recordID: NSManagedObjectID, url: URL) {
        context.perform {
            guard let record = try? self.context.existingObject(with: recordID) as? ClipboardRecord,
                  record.kind == .link else {
                return
            }

            if let normalizedHost = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
               !normalizedHost.isEmpty {
                record.linkHostValue = normalizedHost
            }

            if let metadata {
                if let title = metadata.title, !title.isEmpty {
                    record.linkTitleValue = title
                }

                if let host = metadata.host, !host.isEmpty {
                    record.linkHostValue = host
                }

                if let iconData = metadata.iconData, !iconData.isEmpty {
                    record.linkIconDataValue = iconData
                }
            }

            record.linkMetadataCheckedAtValue = Date()

            do {
                try self.context.save()
            } catch {
                NSLog("Failed to save link metadata: \(error.localizedDescription)")
            }
        }
    }
}

private struct LinkMetadata {
    let title: String?
    let host: String?
    let iconData: Data?
}

private enum LinkMetadataFetcher {
    static func fetch(from url: URL) async -> LinkMetadata? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...399).contains(httpResponse.statusCode) else {
                return LinkMetadata(title: nil, host: response.url?.host, iconData: nil)
            }

            let resolvedURL = response.url ?? url
            let html = string(from: data)
            let title = extractTitle(from: html)
            let iconURL = extractIconURL(from: html, baseURL: resolvedURL)

            var iconData: Data?
            if let iconURL {
                iconData = try? await fetchIconData(from: iconURL)
            }

            if iconData == nil {
                iconData = try? await fetchIconData(from: rootFaviconURL(for: resolvedURL))
            }

            return LinkMetadata(
                title: title,
                host: resolvedURL.host?.trimmingCharacters(in: .whitespacesAndNewlines),
                iconData: iconData
            )
        } catch {
            return LinkMetadata(title: nil, host: url.host?.trimmingCharacters(in: .whitespacesAndNewlines), iconData: nil)
        }
    }

    private static func fetchIconData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...399).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func string(from data: Data) -> String {
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        if let string = String(data: data, encoding: .isoLatin1) {
            return string
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func extractTitle(from html: String) -> String? {
        let patterns = [
            #"(?is)<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["'][^>]*>"#,
            #"(?is)<meta[^>]+name=["']twitter:title["'][^>]+content=["']([^"']+)["'][^>]*>"#,
            #"(?is)<title[^>]*>(.*?)</title>"#
        ]

        for pattern in patterns {
            if let match = firstMatch(pattern: pattern, in: html) {
                let normalized = normalizeTitle(match)
                if !normalized.isEmpty {
                    return normalized
                }
            }
        }

        return nil
    }

    private static func extractIconURL(from html: String, baseURL: URL) -> URL? {
        let linkPattern = #"(?is)<link\b[^>]*>"#
        guard let tags = regexMatches(pattern: linkPattern, in: html), !tags.isEmpty else {
            return rootFaviconURL(for: baseURL)
        }

        let priorityTokens = ["apple-touch-icon", "shortcut icon", "icon"]
        for token in priorityTokens {
            for tag in tags {
                guard let rel = attribute(named: "rel", in: tag)?.lowercased(),
                      rel.contains(token),
                      let href = attribute(named: "href", in: tag),
                      !href.isEmpty,
                      let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else {
                    continue
                }
                return url
            }
        }

        return rootFaviconURL(for: baseURL)
    }

    private static func attribute(named name: String, in tag: String) -> String? {
        let pattern = #"(?is)\#(name)\s*=\s*["']([^"']+)["']"#
        return firstMatch(pattern: pattern, in: tag)
    }

    private static func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    private static func regexMatches(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return nil }
        return matches.compactMap { match in
            guard let captureRange = Range(match.range, in: text) else { return nil }
            return String(text[captureRange])
        }
    }

    private static func normalizeTitle(_ raw: String) -> String {
        let stripped = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !stripped.isEmpty else { return "" }

        if let data = stripped.data(using: .utf8),
           let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
           ) {
            return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return stripped
    }

    private static func rootFaviconURL(for url: URL) -> URL {
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.path = "/favicon.ico"
            components.query = nil
            components.fragment = nil
            return components.url ?? url
        }

        return url.deletingLastPathComponent().appendingPathComponent("favicon.ico")
    }
}

extension Notification.Name {
    static let clipDockTogglePanelRequested = Notification.Name("clipDockTogglePanelRequested")
    static let clipDockHidePanelRequested = Notification.Name("clipDockHidePanelRequested")
}

extension ClipboardMonitor {
    static let imageFileExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp", "avif", "icns"
    ]
}
