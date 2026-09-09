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

