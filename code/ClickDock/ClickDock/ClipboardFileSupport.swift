//
//  ClipboardFileSupport.swift
//  ClipDock
//

import Foundation

enum FileHistoryCopyStrategy: Int, CaseIterable, Identifiable {
    case pathOnly = 0
    case saveCopy = 1

    var id: Int { rawValue }

    var titleKey: AppTextKey {
        switch self {
        case .pathOnly: return .fileHistoryPathOnly
        case .saveCopy: return .fileHistorySaveCopy
        }
    }
}

struct ClipboardFileReferenceSet {
    let originalPathsText: String?
    let legacyCacheFolderPath: String?

    var originalURLs: [URL] {
        Self.urls(fromPathsText: originalPathsText)
    }

    var existingOriginalURLs: [URL] {
        resolvedOriginalURLs.existing
    }

    var missingOriginalURLs: [URL] {
        resolvedOriginalURLs.missing
    }

    var hasOriginalPaths: Bool {
        !originalURLs.isEmpty
    }

    var hasMissingOriginalFiles: Bool {
        !missingOriginalURLs.isEmpty
    }

    var hasCachedCopies: Bool {
        !cachedURLs.isEmpty
    }

    var preferredURLsForPasteboard: [URL] {
        let originals = resolvedOriginalURLs.existing
        if !originals.isEmpty {
            return originals
        }

        return cachedURLs
    }

    var representativeURL: URL? {
        preferredURLsForPasteboard.first
    }

    var displayPathText: String {
        let originals = resolvedOriginalURLs.existing
        let displayURLs = !originals.isEmpty ? originals : cachedURLs
        let paths = displayURLs.map(\.path)
        if !paths.isEmpty {
            return paths.joined(separator: "\n")
        }

        return originalURLs.map(\.path).joined(separator: "\n")
    }

    var fileSizeLabel: String {
        if let label = Self.fileSizeLabel(for: existingOriginalURLs), label != "-" {
            return label
        }

        if let label = Self.fileSizeLabel(for: cachedURLs), label != "-" {
            return label
        }

        if let cachedFolderURL {
            return Self.fileSizeLabel(forPath: cachedFolderURL.path)
        }

        return "-"
    }

    var cachedFolderURL: URL? {
        guard let legacyCacheFolderPath,
              !legacyCacheFolderPath.isEmpty,
              !legacyCacheFolderPath.contains("\n") else {
            return nil
        }

        let url = URL(fileURLWithPath: legacyCacheFolderPath)
        guard Self.isCachedAssetFolder(url) else { return nil }

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory == true else { return nil }
        return url
    }

    var legacyCacheFolderURL: URL? {
        cachedFolderURL
    }

    var cachedURLs: [URL] {
        guard let cachedFolderURL else { return [] }
        return Self.fileURLs(in: cachedFolderURL) ?? []
    }

    var legacyCachedURLs: [URL] {
        cachedURLs
    }

    static func urls(fromPathsText text: String?) -> [URL] {
        guard let text else { return [] }

        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { path in
                if path.hasPrefix("file://"), let url = URL(string: path) {
                    return url
                }
                return URL(fileURLWithPath: path)
            }
    }

    static func isCachedAssetFolder(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return cachedAssetRootURLs().contains(where: { path.hasPrefix($0.standardizedFileURL.path) })
    }

    private static func cachedAssetRootURLs() -> [URL] {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let bundleName = Bundle.main.bundleIdentifier ?? "ClipDock"
        let bundleRoot = base.appendingPathComponent(bundleName, isDirectory: true)
        return [
            bundleRoot.appendingPathComponent("ClipboardAssets", isDirectory: true),
            bundleRoot.appendingPathComponent("ClipboardImages", isDirectory: true)
        ]
    }

    private static func fileURLs(in folderURL: URL) -> [URL]? {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return contents.filter { url in
            (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func fileSizeLabel(for urls: [URL]) -> String? {
        guard !urls.isEmpty else { return nil }

        let total = urls.reduce(0) { partialResult, url in
            partialResult + max(0, fileSize(at: url) ?? 0)
        }

        guard total > 0 else { return nil }
        return byteCountFormatter.string(fromByteCount: Int64(total))
    }

    private static func fileSizeLabel(forPath path: String?) -> String {
        guard let path, !path.isEmpty else { return "-" }
        let url = URL(fileURLWithPath: path)
        guard let size = fileSize(at: url) else { return "-" }
        return byteCountFormatter.string(fromByteCount: Int64(size))
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

    private var resolvedOriginalURLs: (existing: [URL], missing: [URL]) {
        let urls = originalURLs
        guard !urls.isEmpty else {
            return ([], [])
        }

        var existing: [URL] = []
        var missing: [URL] = []
        existing.reserveCapacity(urls.count)
        missing.reserveCapacity(urls.count)

        for url in urls {
            if FileManager.default.fileExists(atPath: url.path) {
                existing.append(url)
            } else {
                missing.append(url)
            }
        }

        return (existing, missing)
    }

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()
}
