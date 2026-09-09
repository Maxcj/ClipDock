//
//  ClipboardFileAssetCopyManager.swift
//  ClipDock
//

import CoreData
import Foundation

struct SavedFileAssets {
    let folder: URL
    let cachedSizeBytes: Int64
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
