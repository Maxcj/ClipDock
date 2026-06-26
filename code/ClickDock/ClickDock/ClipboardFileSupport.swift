//
//  ClipboardFileSupport.swift
//  ClipDock
//

import Foundation

struct ClipboardFileReferenceSet {
    let originalPathsText: String?
    let legacyCacheFolderPath: String?

    var originalURLs: [URL] {
        Self.urls(fromPathsText: originalPathsText)
    }

    var existingOriginalURLs: [URL] {
        originalURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var missingOriginalURLs: [URL] {
        originalURLs.filter { !FileManager.default.fileExists(atPath: $0.path) }
    }

    var hasOriginalPaths: Bool {
        !originalURLs.isEmpty
    }

    var hasMissingOriginalFiles: Bool {
        !missingOriginalURLs.isEmpty
    }

    var preferredURLsForPasteboard: [URL] {
        if !existingOriginalURLs.isEmpty {
            return existingOriginalURLs
        }

        return legacyCachedURLs
    }

    var representativeURL: URL? {
        preferredURLsForPasteboard.first
    }

    var displayPathText: String {
        let paths = originalURLs.map(\.path)
        if !paths.isEmpty {
            return paths.joined(separator: "\n")
        }

        return legacyCachedURLs.map(\.path).joined(separator: "\n")
    }

    var fileSizeLabel: String {
        if let label = Self.fileSizeLabel(for: existingOriginalURLs), label != "-" {
            return label
        }

        if let legacyCacheFolderURL {
            return Self.fileSizeLabel(forPath: legacyCacheFolderURL.path)
        }

        return "-"
    }

    var legacyCacheFolderURL: URL? {
        guard let legacyCacheFolderPath,
              !legacyCacheFolderPath.isEmpty,
              !legacyCacheFolderPath.contains("\n") else {
            return nil
        }

        let url = URL(fileURLWithPath: legacyCacheFolderPath)
        guard Self.isLegacyCacheFolder(url) else { return nil }

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory == true else { return nil }
        return url
    }

    var legacyCachedURLs: [URL] {
        guard let legacyCacheFolderURL else { return [] }
        return Self.fileURLs(in: legacyCacheFolderURL) ?? []
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

    static func isLegacyCacheFolder(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.hasPrefix(legacyCacheRootURL().standardizedFileURL.path)
    }

    private static func legacyCacheRootURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let bundleName = Bundle.main.bundleIdentifier ?? "ClipDock"
        return base.appendingPathComponent(bundleName, isDirectory: true)
            .appendingPathComponent("ClipboardImages", isDirectory: true)
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

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()
}
