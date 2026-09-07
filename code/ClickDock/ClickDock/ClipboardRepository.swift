//
//  ClipboardRepository.swift
//  ClipDock
//

import CoreData
import Foundation

final class ClipboardRepository {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func upsert(snapshot: ClipboardSnapshot, deduplicator: ClipboardDeduplicator, fileAssetCopyManager: FileAssetCopyManager, linkMetadataManager: LinkMetadataManager, cleanupService: ClipboardCleanupService) {
        context.perform {
            do {
                let existingRecords = try self.fetchMatchingRecords(for: snapshot)
                let record: ClipboardRecord

                if let canonicalRecord = deduplicator.preferredRecord(from: existingRecords) {
                    record = canonicalRecord
                    self.update(record, with: snapshot, isDuplicateCapture: true)

                    for duplicate in existingRecords where duplicate.objectID != canonicalRecord.objectID {
                        removeCachedAssets(for: duplicate)
                        self.context.delete(duplicate)
                    }
                } else {
                    record = ClipboardRecord(context: self.context)
                    record.id = UUID()
                    let now = Date()
                    record.createdAt = now
                    record.lastUsedAt = now
                    record.isPinned = false
                    record.isIgnored = false
                    record.usageCount = 0
                    self.update(record, with: snapshot, isDuplicateCapture: false)
                }

                try self.context.save()
                if snapshot.kind == .files, snapshot.fileURLs != nil {
                    fileAssetCopyManager.scheduleCopy(for: record.objectID, hash: snapshot.hash, fileURLs: snapshot.fileURLs ?? [])
                }
                cleanupService.pruneExpiredRecordsLocked()
                if snapshot.kind == .link,
                   let url = ClipboardRecord.webURL(from: snapshot.fullText ?? snapshot.displayText),
                   record.linkMetadataCheckedAtValue == nil {
                    linkMetadataManager.scheduleMetadataFetch(for: record.objectID, url: url)
                }
            } catch {
                NSLog("Failed to save clipboard record: \(error.localizedDescription)")
            }
        }
    }

    private func fetchMatchingRecords(for snapshot: ClipboardSnapshot) throws -> [ClipboardRecord] {
        let request = NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")
        switch snapshot.kind {
        case .image, .files:
            request.predicate = NSPredicate(format: "contentHash == %@", snapshot.hash)
        case .text, .link, .code, .colors, .unknown:
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "fullText == %@", snapshot.fullText ?? snapshot.displayText),
                NSPredicate(format: "contentHash == %@", snapshot.hash)
            ])
        }
        request.fetchBatchSize = 32
        return try context.fetch(request)
    }

    private func update(_ record: ClipboardRecord, with snapshot: ClipboardSnapshot, isDuplicateCapture: Bool) {
        let previousKind = record.kind
        let now = Date()
        record.updatedAt = now
        if isDuplicateCapture {
            record.lastUsedAt = now
            record.usageCount += 1
        }
        record.contentTypeRaw = snapshot.kind.rawValue
        record.displayText = snapshot.displayText
        record.fullText = snapshot.fullText
        record.imagePath = snapshot.imagePath
        record.cachedSizeBytesValue = snapshot.cachedSizeBytes
        record.assetPathValue = snapshot.assetPath
        record.thumbnailPathValue = snapshot.thumbnailPath
        record.sourceAppName = snapshot.sourceAppName
        record.sourceBundleId = snapshot.sourceBundleId
        record.contentHash = snapshot.hash
        record.normalizedSearchTextValue = normalizedSearchText(for: snapshot)

        updateCodeFields(record, snapshot: snapshot)
        updateFileCacheFields(record, snapshot: snapshot)
        updateColorFields(record, snapshot: snapshot)
        updateLinkFields(record, snapshot: snapshot, previousKind: previousKind)
    }

    private func normalizedSearchText(for snapshot: ClipboardSnapshot) -> String? {
        var pieces: [String] = []
        let displayText = snapshot.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayText.isEmpty { pieces.append(displayText) }
        if let sourceAppName = snapshot.sourceAppName?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceAppName.isEmpty { pieces.append(sourceAppName) }
        if let sourceBundleId = snapshot.sourceBundleId?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceBundleId.isEmpty { pieces.append(sourceBundleId) }
        if snapshot.kind == .files, let fullText = snapshot.fullText?.trimmingCharacters(in: .whitespacesAndNewlines), !fullText.isEmpty { pieces.append(fullText) }
        if let fileURLs = snapshot.fileURLs, !fileURLs.isEmpty { pieces.append(contentsOf: fileURLs.map(\.path)) }
        return pieces.isEmpty ? nil : pieces.joined(separator: " ").lowercased()
    }

    private func updateCodeFields(_ record: ClipboardRecord, snapshot: ClipboardSnapshot) {
        if snapshot.kind == .code {
            let codeText = snapshot.fullText ?? snapshot.displayText
            let language = ClipboardCodeLanguageDetector.detect(from: codeText)
            record.setValue(language.rawValue, forKey: "codeLanguageRaw")
            record.setValue(Int32(codeText.split(whereSeparator: \.isNewline).count), forKey: "codeLineCountValue")
        } else {
            record.setValue(nil, forKey: "codeLanguageRaw")
            record.setValue(0, forKey: "codeLineCountValue")
        }
    }

    private func updateFileCacheFields(_ record: ClipboardRecord, snapshot: ClipboardSnapshot) {
        if snapshot.kind == .files {
            record.fileCacheStatusValue = snapshot.fileURLs != nil ? ClipboardFileCacheStatus.pending.rawValue : ClipboardFileCacheStatus.skipped.rawValue
            record.fileCacheErrorValue = nil
            record.fileCacheUpdatedAtValue = Date()
        } else {
            record.fileCacheStatusValue = nil
            record.fileCacheErrorValue = nil
            record.fileCacheUpdatedAtValue = nil
        }
    }

    private func updateColorFields(_ record: ClipboardRecord, snapshot: ClipboardSnapshot) {
        if snapshot.kind == .colors, let color = ClipboardColorDetector.detect(from: snapshot.fullText ?? snapshot.displayText) {
            record.setValue(color.normalizedHexString, forKey: "colorHex")
            record.setValue(color.red, forKey: "colorRed")
            record.setValue(color.green, forKey: "colorGreen")
            record.setValue(color.blue, forKey: "colorBlue")
            record.setValue(color.alpha, forKey: "colorAlpha")
            record.setValue(color.sourceFormat.rawValue, forKey: "colorSourceFormat")
        } else {
            record.setValue(nil, forKey: "colorHex")
            record.setValue(0.0, forKey: "colorRed")
            record.setValue(0.0, forKey: "colorGreen")
            record.setValue(0.0, forKey: "colorBlue")
            record.setValue(0.0, forKey: "colorAlpha")
            record.setValue(nil, forKey: "colorSourceFormat")
        }
    }

    private func updateLinkFields(_ record: ClipboardRecord, snapshot: ClipboardSnapshot, previousKind: ClipboardContentKind) {
        if snapshot.kind == .link, let url = ClipboardRecord.webURL(from: snapshot.fullText ?? snapshot.displayText) {
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
}

struct SavedFileAssets {
    let folder: URL
    let cachedSizeBytes: Int64
}

private actor LinkMetadataFetchGate {
    private var inFlightRecordIDs: Set<String> = []

    func performIfAvailable(
        for key: String,
        operation: () async -> Void
    ) async {
        guard inFlightRecordIDs.insert(key).inserted else { return }
        defer { inFlightRecordIDs.remove(key) }
        await operation()
    }
}

final class LinkMetadataManager {
    private let context: NSManagedObjectContext
    private let fetchGate = LinkMetadataFetchGate()

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
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let key = recordID.uriRepresentation().absoluteString
            await self.fetchGate.performIfAvailable(for: key) {
                let metadata = await LinkMetadataFetcher.fetch(from: url)
                self.apply(metadata: metadata, for: recordID, url: url)
            }
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

private actor FileAssetCopyGate {
    private var inFlightKeys: Set<String> = []

    func performIfAvailable(
        for key: String,
        operation: () async -> Void
    ) async {
        guard inFlightKeys.insert(key).inserted else { return }
        defer { inFlightKeys.remove(key) }
        await operation()
    }
}

final class FileAssetCopyManager {
    private let context: NSManagedObjectContext
    private let gate = FileAssetCopyGate()

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func scheduleCopy(for recordID: NSManagedObjectID, hash: String, fileURLs: [URL]) {
        guard !fileURLs.isEmpty else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let key = recordID.uriRepresentation().absoluteString + "|" + hash
            await self.gate.performIfAvailable(for: key) {
                do {
                    let assets = try Self.saveFileAssets(from: fileURLs)
                    self.apply(assets: assets, for: recordID, hash: hash)
                } catch {
                    self.applyFailure(error, for: recordID, hash: hash)
                }
            }
        }
    }



    private static func saveFileAssets(from fileURLs: [URL]) throws -> SavedFileAssets {
        guard !fileURLs.isEmpty else {
            throw NSError(domain: "ClipDock.FileAssets", code: 1, userInfo: [NSLocalizedDescriptionKey: "No file URLs provided"])
        }

        var sourceSizes: Int64 = 0
        var sourceFileSizes: [Int64] = []
        sourceFileSizes.reserveCapacity(fileURLs.count)

        for fileURL in fileURLs {
            guard isCacheableFileURL(fileURL) else {
                throw NSError(domain: "ClipDock.FileAssets", code: 2, userInfo: [NSLocalizedDescriptionKey: "Uncacheable file URL"])
            }
            guard let fileSize = fileSizeBytes(for: fileURL) else {
                throw NSError(domain: "ClipDock.FileAssets", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing file size"])
            }
            guard fileSize <= maximumSingleFileCopySizeBytes else {
                throw NSError(domain: "ClipDock.FileAssets", code: 4, userInfo: [NSLocalizedDescriptionKey: "Single file exceeds copy limit"])
            }
            sourceSizes += fileSize
            guard sourceSizes <= maximumBatchFileCopySizeBytes else {
                throw NSError(domain: "ClipDock.FileAssets", code: 5, userInfo: [NSLocalizedDescriptionKey: "Batch exceeds copy limit"])
            }
            sourceFileSizes.append(fileSize)
        }

        let folderURL = fileAssetFolderURL().appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            var manifestFiles: [ClipboardFileCopyManifest.File] = []
            manifestFiles.reserveCapacity(fileURLs.count)

            for (index, pair) in zip(fileURLs, sourceFileSizes).enumerated() {
                let (sourceURL, fileSize) = pair
                let copiedFileName = "\(index)-\(sourceURL.lastPathComponent)"
                let destinationURL = folderURL.appendingPathComponent(copiedFileName)
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                manifestFiles.append(ClipboardFileCopyManifest.File(
                    sourcePath: sourceURL.path,
                    originalFileName: sourceURL.lastPathComponent,
                    originalFileExtension: sourceURL.pathExtension,
                    copiedFileName: copiedFileName,
                    copiedAt: Date(),
                    sizeBytes: fileSize
                ))
            }

            let manifest = ClipboardFileCopyManifest(files: manifestFiles)
            let manifestURL = try manifest.write(to: folderURL)
            let manifestSize = fileSizeBytes(for: manifestURL) ?? 0
            return SavedFileAssets(folder: folderURL, cachedSizeBytes: sourceSizes + manifestSize)
        } catch {
            try? FileManager.default.removeItem(at: folderURL)
            throw error
        }
    }

    private static func fileAssetFolderURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let bundleName = Bundle.main.bundleIdentifier ?? "ClipDock"
        return base.appendingPathComponent(bundleName, isDirectory: true)
            .appendingPathComponent("ClipboardAssets", isDirectory: true)
            .appendingPathComponent("Files", isDirectory: true)
    }

    private static func isCacheableFileURL(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
        return values?.isRegularFile == true && values?.isDirectory != true
    }

    private static func fileSizeBytes(for url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey])
        guard values?.isDirectory != true else { return nil }
        if let allocated = values?.totalFileAllocatedSize, allocated > 0 { return Int64(allocated) }
        if let fileSize = values?.fileSize, fileSize > 0 { return Int64(fileSize) }
        return nil
    }

    private static let maximumSingleFileCopySizeBytes: Int64 = 50 * 1024 * 1024
    private static let maximumBatchFileCopySizeBytes: Int64 = 200 * 1024 * 1024

    private func apply(assets: SavedFileAssets, for recordID: NSManagedObjectID, hash: String) {
        context.perform {
            guard let record = try? self.context.existingObject(with: recordID) as? ClipboardRecord,
                  record.kind == .files,
                  record.contentHash == hash else {
                try? FileManager.default.removeItem(at: assets.folder)
                return
            }

            record.assetPathValue = assets.folder.path
            record.cachedSizeBytesValue = assets.cachedSizeBytes
            record.fileCacheStatusValue = ClipboardFileCacheStatus.cached.rawValue
            record.fileCacheErrorValue = nil
            record.fileCacheUpdatedAtValue = Date()

            do {
                try self.context.save()
            } catch {
                NSLog("Failed to save file asset copy completion: \(error.localizedDescription)")
            }
        }
    }

    private func applyFailure(_ error: Error, for recordID: NSManagedObjectID, hash: String) {
        context.perform {
            guard let record = try? self.context.existingObject(with: recordID) as? ClipboardRecord,
                  record.kind == .files,
                  record.contentHash == hash else {
                return
            }

            record.fileCacheStatusValue = ClipboardFileCacheStatus.failed.rawValue
            record.fileCacheErrorValue = error.localizedDescription
            record.fileCacheUpdatedAtValue = Date()

            do {
                try self.context.save()
            } catch {
                NSLog("Failed to save file asset copy failure: \(error.localizedDescription)")
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
    private static let requestTimeout: TimeInterval = 4.0
    private static let htmlMaxBytes = 512 * 1024
    private static let iconMaxBytes = 256 * 1024

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout + 2.0
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    static func fetch(from url: URL) async -> LinkMetadata? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }

        let resolvedURL = url
        let host = resolvedURL.host?.trimmingCharacters(in: .whitespacesAndNewlines)

        let htmlResult = await fetchHTML(from: url)
        let title = htmlResult.flatMap { extractTitle(from: $0.html) }
        let iconURL = htmlResult.flatMap { extractIconURL(from: $0.html, baseURL: $0.resolvedURL) }
        let metadataHost = htmlResult?.resolvedURL.host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? host

        var iconData: Data?
        if let iconURL {
            iconData = await fetchIconData(from: iconURL)
        }

        if iconData == nil {
            iconData = await fetchIconData(from: rootFaviconURL(for: htmlResult?.resolvedURL ?? url))
        }

        return LinkMetadata(
            title: title,
            host: metadataHost,
            iconData: iconData
        )
    }

    private static func fetchHTML(from url: URL) async -> (html: String, resolvedURL: URL)? {
        do {
            let request = URLRequest(url: url, timeoutInterval: requestTimeout)
            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...399).contains(httpResponse.statusCode),
                  httpResponse.mimeType?.lowercased() == "text/html" else {
                return nil
            }

            if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init),
               contentLength > htmlMaxBytes {
                return nil
            }

            var data = Data()
            data.reserveCapacity(min(htmlMaxBytes, 64 * 1024))

            for try await byte in bytes {
                data.append(byte)
                if data.count > htmlMaxBytes {
                    return nil
                }
            }

            return (string(from: data), response.url ?? url)
        } catch {
            return nil
        }
    }

    private static func fetchIconData(from url: URL) async -> Data? {
        do {
            let request = URLRequest(url: url, timeoutInterval: requestTimeout)
            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...399).contains(httpResponse.statusCode),
                  let mimeType = httpResponse.mimeType?.lowercased(),
                  mimeType.hasPrefix("image/") else {
                return nil
            }

            if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init),
               contentLength > iconMaxBytes {
                return nil
            }

            var data = Data()
            data.reserveCapacity(min(iconMaxBytes, 16 * 1024))

            for try await byte in bytes {
                data.append(byte)
                if data.count > iconMaxBytes {
                    return nil
                }
            }

            return data
        } catch {
            return nil
        }
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
