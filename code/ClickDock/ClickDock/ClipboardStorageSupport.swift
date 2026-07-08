//
//  ClipboardStorageSupport.swift
//  ClipDock
//

import CoreData
import Foundation

struct ClipboardStorageSnapshot {
    let kind: ClipboardContentKind
    let cachedImagePaths: [String]
    let fileReferenceSet: ClipboardFileReferenceSet
    let linkIconBytes: Int
    let linkTextBytes: Int
}

struct ClipboardStorageSummary {
    let totalItemCount: Int
    let textItemCount: Int
    let imageItemCount: Int
    let filesCacheItemCount: Int
    let linkMetadataItemCount: Int
    let imageBytes: Int64
    let filesCacheBytes: Int64
    let linkMetadataBytes: Int64

    static let empty = ClipboardStorageSummary(
        totalItemCount: 0,
        textItemCount: 0,
        imageItemCount: 0,
        filesCacheItemCount: 0,
        linkMetadataItemCount: 0,
        imageBytes: 0,
        filesCacheBytes: 0,
        linkMetadataBytes: 0
    )

    var totalItemsValue: String {
        Self.countFormatter.string(from: NSNumber(value: totalItemCount)) ?? "\(totalItemCount)"
    }

    var textItemsValue: String {
        Self.countFormatter.string(from: NSNumber(value: textItemCount)) ?? "\(textItemCount)"
    }

    var imagesValue: String {
        "\(Self.countFormatter.string(from: NSNumber(value: imageItemCount)) ?? "\(imageItemCount)") / \(Self.byteFormatter.string(fromByteCount: imageBytes))"
    }

    var filesCacheValue: String {
        "\(Self.countFormatter.string(from: NSNumber(value: filesCacheItemCount)) ?? "\(filesCacheItemCount)") / \(Self.byteFormatter.string(fromByteCount: filesCacheBytes))"
    }

    var linkMetadataValue: String {
        "\(Self.countFormatter.string(from: NSNumber(value: linkMetadataItemCount)) ?? "\(linkMetadataItemCount)") / \(Self.byteFormatter.string(fromByteCount: linkMetadataBytes))"
    }

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        formatter.zeroPadsFractionDigits = false
        return formatter
    }()
}

enum ClipboardStorageCalculator {
    static func summary(for snapshots: [ClipboardStorageSnapshot]) -> ClipboardStorageSummary {
        let totalItemCount = snapshots.count
        var textItemCount = 0
        var imageItemCount = 0
        var filesCacheItemCount = 0
        var linkMetadataItemCount = 0
        var imageBytes: Int64 = 0
        var filesCacheBytes: Int64 = 0
        var linkMetadataBytes: Int64 = 0

        var seenImagePaths = Set<String>()
        var seenLegacyFileCachePaths = Set<String>()

        for snapshot in snapshots {
            switch snapshot.kind {
            case .text, .code, .colors, .unknown:
                textItemCount += 1
            case .image:
                imageItemCount += 1
                for path in snapshot.cachedImagePaths where seenImagePaths.insert(path).inserted {
                    imageBytes += Int64(fileSize(atPath: path) ?? 0)
                }
            case .files:
                filesCacheItemCount += 1
                if let cachedFolderURL = snapshot.fileReferenceSet.cachedFolderURL {
                    let standardizedPath = cachedFolderURL.standardizedFileURL.path
                    if seenLegacyFileCachePaths.insert(standardizedPath).inserted {
                        filesCacheBytes += Int64(fileSize(at: cachedFolderURL) ?? 0)
                    }
                }
            case .link:
                linkMetadataItemCount += 1
                linkMetadataBytes += Int64(snapshot.linkIconBytes + snapshot.linkTextBytes)
            }
        }

        return ClipboardStorageSummary(
            totalItemCount: totalItemCount,
            textItemCount: textItemCount,
            imageItemCount: imageItemCount,
            filesCacheItemCount: filesCacheItemCount,
            linkMetadataItemCount: linkMetadataItemCount,
            imageBytes: imageBytes,
            filesCacheBytes: filesCacheBytes,
            linkMetadataBytes: linkMetadataBytes
        )
    }

    static func summary(context: NSManagedObjectContext) -> ClipboardStorageSummary {
        var result = ClipboardStorageSummary.empty

        context.performAndWait {
            let request = NSFetchRequest<NSDictionary>(entityName: "ClipboardRecord")
            request.resultType = .dictionaryResultType
            request.includesPropertyValues = true
            request.returnsObjectsAsFaults = false
            request.propertiesToFetch = [
                "contentTypeRaw",
                "cachedSizeBytes",
                "linkIconData",
                "linkTitle",
                "linkHost"
            ]

            guard let records = try? context.fetch(request) else {
                result = .empty
                return
            }

        var totalItemCount = 0
        var textItemCount = 0
        var imageItemCount = 0
        var filesCacheItemCount = 0
        var linkMetadataItemCount = 0
        var imageBytes: Int64 = 0
        var filesCacheBytes: Int64 = 0
        var linkMetadataBytes: Int64 = 0

            for record in records {
                totalItemCount += 1
                let kind = ClipboardContentKind(rawValue: record["contentTypeRaw"] as? String ?? "") ?? .unknown

                switch kind {
                case .text, .code, .colors, .unknown:
                    textItemCount += 1
                case .image:
                    imageItemCount += 1
                    imageBytes += int64Value(record["cachedSizeBytes"])
                case .files:
                    filesCacheItemCount += 1
                    filesCacheBytes += int64Value(record["cachedSizeBytes"])
                case .link:
                    linkMetadataItemCount += 1
                    linkMetadataBytes += Int64((record["linkIconData"] as? Data)?.count ?? 0)
                    linkMetadataBytes += Int64((record["linkTitle"] as? String)?.utf8.count ?? 0)
                    linkMetadataBytes += Int64((record["linkHost"] as? String)?.utf8.count ?? 0)
                }
            }

            result = ClipboardStorageSummary(
                totalItemCount: totalItemCount,
                textItemCount: textItemCount,
                imageItemCount: imageItemCount,
                filesCacheItemCount: filesCacheItemCount,
                linkMetadataItemCount: linkMetadataItemCount,
                imageBytes: imageBytes,
                filesCacheBytes: filesCacheBytes,
                linkMetadataBytes: linkMetadataBytes
            )
        }

        return result
    }

    static func rebuildCachedSizes(context: NSManagedObjectContext) {
        context.performAndWait {
            let request = NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")
            request.fetchBatchSize = 32

            guard let records = try? context.fetch(request) else { return }

            var didChange = false
            for record in records {
                let cachedSizeBytes = cachedSizeBytes(for: record)
                guard record.cachedSizeBytesValue != cachedSizeBytes else { continue }
                record.cachedSizeBytesValue = cachedSizeBytes
                didChange = true
            }

            if didChange {
                try? context.save()
            }
        }
    }

    static func backfillSearchIndexAndFileCacheState(context: NSManagedObjectContext) {
        context.performAndWait {
            let request = NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")
            request.fetchBatchSize = 32

            guard let records = try? context.fetch(request) else { return }

            var didChange = false
            for record in records {
                if let normalizedSearchText = normalizedSearchText(for: record),
                   record.normalizedSearchTextValue != normalizedSearchText {
                    record.normalizedSearchTextValue = normalizedSearchText
                    didChange = true
                }

                guard record.kind == .files else { continue }

                if record.fileCacheStatusValue == nil || record.fileCacheStatusValue?.isEmpty == true {
                    if record.fileReferenceSet.cachedFolderURL != nil {
                        record.fileCacheStatusValue = ClipboardFileCacheStatus.cached.rawValue
                    } else if record.assetPathValue == nil {
                        record.fileCacheStatusValue = ClipboardFileCacheStatus.skipped.rawValue
                    } else {
                        record.fileCacheStatusValue = ClipboardFileCacheStatus.failed.rawValue
                        record.fileCacheErrorValue = "Cached folder missing"
                    }
                    record.fileCacheUpdatedAtValue = Date()
                    didChange = true
                }
            }

            if didChange {
                try? context.save()
            }
        }
    }

    private static func fileSize(atPath path: String) -> Int? {
        fileSize(at: URL(fileURLWithPath: path))
    }

    private static func fileSize(at url: URL) -> Int? {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey])
        if values?.isDirectory == true {
            return directorySize(at: url)
        }

        if let allocated = values?.totalFileAllocatedSize, allocated > 0 {
            return allocated
        }

        if let fileSize = values?.fileSize, fileSize > 0 {
            return fileSize
        }

        return nil
    }

    private static func directorySize(at url: URL) -> Int? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var total = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey])
            guard values?.isDirectory != true else { continue }
            if let allocated = values?.totalFileAllocatedSize, allocated > 0 {
                total += allocated
            } else if let fileSize = values?.fileSize, fileSize > 0 {
                total += fileSize
            }
        }

        return total > 0 ? total : nil
    }

    private static func cachedSizeBytes(for record: ClipboardRecord) -> Int64 {
        switch record.kind {
        case .image:
            return cachedSizeBytes(forPaths: record.cachedImagePaths)
        case .files:
            guard let cachedFolderURL = record.fileReferenceSet.cachedFolderURL else { return 0 }
            return Int64(fileSize(at: cachedFolderURL) ?? 0)
        case .text, .link, .code, .colors, .unknown:
            return 0
        }
    }

    private static func cachedSizeBytes(forPaths paths: [String]) -> Int64 {
        var total: Int64 = 0
        var seenPaths = Set<String>()

        for path in paths where seenPaths.insert(path).inserted {
            total += Int64(fileSize(atPath: path) ?? 0)
        }

        return total
    }

    private static func normalizedSearchText(for record: ClipboardRecord) -> String? {
        var pieces: [String] = []

        let displayText = (record.displayText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayText.isEmpty {
            pieces.append(displayText)
        }

        let fullText = (record.fullText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !fullText.isEmpty {
            pieces.append(fullText)
        }

        let sourceAppName = (record.sourceAppName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !sourceAppName.isEmpty {
            pieces.append(sourceAppName)
        }

        let sourceBundleId = (record.sourceBundleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !sourceBundleId.isEmpty {
            pieces.append(sourceBundleId)
        }

        if let linkHost = record.linkHostValue?.trimmingCharacters(in: .whitespacesAndNewlines), !linkHost.isEmpty {
            pieces.append(linkHost)
        }

        if let codeLanguageRaw = record.codeLanguageRawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !codeLanguageRaw.isEmpty {
            pieces.append(codeLanguageRaw)
        }

        if record.kind == .files {
            if !fullText.isEmpty {
                pieces.append(fullText)
            }
        }

        return pieces.isEmpty ? nil : pieces.joined(separator: " ").lowercased()
    }

    private static func int64Value(_ value: Any?) -> Int64 {
        if let value = value as? Int64 {
            return value
        }

        if let value = value as? Int {
            return Int64(value)
        }

        if let value = value as? NSNumber {
            return value.int64Value
        }

        return 0
    }
}

extension Notification.Name {
    static let clipDockStorageSummaryDidChange = Notification.Name("clipDockStorageSummaryDidChange")
}

enum ClipboardStorageSummaryStore {
    static let lastUpdatedAtDefaultsKey = "clipboard.storageSummary.lastUpdatedAt"

    static func recordUpdated(at date: Date = Date()) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastUpdatedAtDefaultsKey)
    }

    static var lastUpdatedAt: Date? {
        let timeInterval = UserDefaults.standard.double(forKey: lastUpdatedAtDefaultsKey)
        guard timeInterval > 0 else { return nil }
        return Date(timeIntervalSince1970: timeInterval)
    }
}
