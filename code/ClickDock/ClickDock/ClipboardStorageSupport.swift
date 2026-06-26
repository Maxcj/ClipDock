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
    let imageBytes: Int64
    let filesCacheBytes: Int64
    let linkMetadataBytes: Int64

    static let empty = ClipboardStorageSummary(
        totalItemCount: 0,
        textItemCount: 0,
        imageItemCount: 0,
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
        Self.byteFormatter.string(fromByteCount: filesCacheBytes)
    }

    var linkMetadataValue: String {
        Self.byteFormatter.string(fromByteCount: linkMetadataBytes)
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
                if let legacyCacheFolderURL = snapshot.fileReferenceSet.legacyCacheFolderURL {
                    let standardizedPath = legacyCacheFolderURL.standardizedFileURL.path
                    if seenLegacyFileCachePaths.insert(standardizedPath).inserted {
                        filesCacheBytes += Int64(fileSize(at: legacyCacheFolderURL) ?? 0)
                    }
                }
            case .link:
                linkMetadataBytes += Int64(snapshot.linkIconBytes + snapshot.linkTextBytes)
            }
        }

        return ClipboardStorageSummary(
            totalItemCount: totalItemCount,
            textItemCount: textItemCount,
            imageItemCount: imageItemCount,
            imageBytes: imageBytes,
            filesCacheBytes: filesCacheBytes,
            linkMetadataBytes: linkMetadataBytes
        )
    }

    static func summary(context: NSManagedObjectContext) -> ClipboardStorageSummary {
        var result = ClipboardStorageSummary.empty

        context.performAndWait {
            let request = NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")

            guard let records = try? context.fetch(request) else {
                result = .empty
                return
            }

            let snapshots = records.map { record in
                ClipboardStorageSnapshot(
                    kind: record.kind,
                    cachedImagePaths: record.cachedImagePaths,
                    fileReferenceSet: record.fileReferenceSet,
                    linkIconBytes: record.linkIconDataValue?.count ?? 0,
                    linkTextBytes: (record.linkTitleValue?.utf8.count ?? 0) + (record.linkHostValue?.utf8.count ?? 0)
                )
            }

            result = summary(for: snapshots)
        }

        return result
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
}
