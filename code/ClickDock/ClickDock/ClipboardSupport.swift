//
//  ClipboardSupport.swift
//  ClipDock
//

import SwiftUI
import CoreData
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct ClipboardSearchQuery: Equatable {
    enum Filter: Equatable {
        case contentType(String)
        case sourceApp(String)
        case host(String)
        case language(String)
        case pinned(Bool)
    }

    let text: String
    let filters: [Filter]

    init(_ rawValue: String) {
        var textTokens: [String] = []
        var parsedFilters: [Filter] = []

        for token in Self.tokenize(rawValue) {
            if let filter = Self.filter(from: token) {
                parsedFilters.append(filter)
            } else {
                textTokens.append(token)
            }
        }

        self.text = textTokens.joined(separator: " ")
        self.filters = parsedFilters
    }

    var predicate: NSPredicate? {
        var predicates: [NSPredicate] = []

        if !text.isEmpty {
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "displayText CONTAINS[cd] %@", text),
                NSPredicate(format: "fullText CONTAINS[cd] %@", text),
                NSPredicate(format: "sourceAppName CONTAINS[cd] %@", text)
            ]))
        }

        for filter in filters {
            switch filter {
            case .contentType(let rawValue):
                predicates.append(NSPredicate(format: "contentTypeRaw == %@", rawValue))
            case .sourceApp(let value):
                predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "sourceAppName CONTAINS[cd] %@", value),
                    NSPredicate(format: "sourceBundleId CONTAINS[cd] %@", value)
                ]))
            case .host(let value):
                predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "linkHost ==[cd] %@", value),
                    NSPredicate(format: "linkHost ENDSWITH[cd] %@", ".\(value)")
                ]))
            case .language(let rawValue):
                predicates.append(NSPredicate(format: "codeLanguageRaw ==[cd] %@", rawValue))
            case .pinned(let isPinned):
                predicates.append(NSPredicate(format: "isPinned == %@", NSNumber(value: isPinned)))
            }
        }

        guard !predicates.isEmpty else { return nil }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private static func filter(from token: String) -> Filter? {
        guard let separatorIndex = token.firstIndex(of: ":"), separatorIndex != token.startIndex else {
            return nil
        }

        let key = token[..<separatorIndex].lowercased()
        let valueStart = token.index(after: separatorIndex)
        let value = token[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        switch key {
        case "type":
            guard let rawValue = contentTypeRawValue(for: value) else { return nil }
            return .contentType(rawValue)
        case "app":
            return .sourceApp(value)
        case "host":
            let normalized = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !normalized.isEmpty else { return nil }
            return .host(normalized)
        case "lang":
            return .language(value.lowercased())
        case "pinned":
            switch value.lowercased() {
            case "true", "yes", "1": return .pinned(true)
            case "false", "no", "0": return .pinned(false)
            default: return nil
            }
        default:
            return nil
        }
    }

    private static func contentTypeRawValue(for value: String) -> String? {
        switch value.lowercased() {
        case "text": return ClipboardContentKind.text.rawValue
        case "link", "links", "url": return ClipboardContentKind.link.rawValue
        case "image", "images": return ClipboardContentKind.image.rawValue
        case "code": return ClipboardContentKind.code.rawValue
        case "file", "files": return ClipboardContentKind.files.rawValue
        case "color", "colors": return ClipboardContentKind.colors.rawValue
        case "other", "unknown": return ClipboardContentKind.unknown.rawValue
        default: return nil
        }
    }

    private static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var isEscaping = false

        func appendCurrentToken() {
            guard !current.isEmpty else { return }
            tokens.append(current)
            current = ""
        }

        for character in input {
            if isEscaping {
                current.append(character)
                isEscaping = false
                continue
            }

            if character == "\\", quote != nil {
                isEscaping = true
                continue
            }

            if character == "\"" || character == "'" {
                if quote == nil {
                    quote = character
                    continue
                }
                if quote == character {
                    quote = nil
                    continue
                }
            }

            if character.isWhitespace, quote == nil {
                appendCurrentToken()
            } else {
                current.append(character)
            }
        }

        if isEscaping {
            current.append("\\")
        }
        appendCurrentToken()
        return tokens
    }
}

struct RetentionRule {
    let isEnabled: Bool
    let value: Int
    let unit: RetentionUnit

    var cutoffDate: Date? {
        guard isEnabled, value > 0 else { return nil }
        let interval = TimeInterval(value) * unit.secondsMultiplier
        return Date().addingTimeInterval(-interval)
    }

    static func current() -> RetentionRule {
        let defaults = UserDefaults.standard
        let isEnabled = defaults.object(forKey: "clipboard.retentionEnabled") as? Bool ?? true
        let storedValue = defaults.object(forKey: "clipboard.retentionValue") as? Int ?? 7
        let value = storedValue > 0 ? storedValue : 7
        let unit = RetentionUnit(rawValue: defaults.string(forKey: "clipboard.retentionUnit") ?? RetentionUnit.day.rawValue) ?? .day
        return RetentionRule(isEnabled: isEnabled, value: value, unit: unit)
    }
}

enum RetentionUnit: String, CaseIterable, Identifiable {
    case minute
    case hour
    case day

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minute: return AppLocalizer.current.text(.minute)
        case .hour: return AppLocalizer.current.text(.hour)
        case .day: return AppLocalizer.current.text(.day)
        }
    }

    var secondsMultiplier: TimeInterval {
        switch self {
        case .minute: return 60
        case .hour: return 60 * 60
        case .day: return 60 * 60 * 24
        }
    }
}

enum ClipboardFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case links
    case images
    case code
    case files
    case colors
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return AppLocalizer.current.text(.all)
        case .text: return AppLocalizer.current.text(.text)
        case .links: return AppLocalizer.current.text(.links)
        case .images: return AppLocalizer.current.text(.images)
        case .code: return AppLocalizer.current.text(.code)
        case .files: return AppLocalizer.current.text(.files)
        case .colors: return AppLocalizer.current.text(.colors)
        case .other: return AppLocalizer.current.text(.other)
        }
    }

    var symbolName: String {
        switch self {
        case .all: return "circle.fill"
        case .text: return "text.quote"
        case .links: return "link"
        case .images: return "photo"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .files: return "doc"
        case .colors: return "paintpalette"
        case .other: return "ellipsis"
        }
    }

    var accentColor: Color {
        switch self {
        case .all: return Color(red: 0.96, green: 0.20, blue: 0.28)
        case .text: return Color(red: 0.96, green: 0.48, blue: 0.18)
        case .links: return Color(red: 0.11, green: 0.66, blue: 0.53)
        case .images: return Color(red: 0.16, green: 0.54, blue: 0.96)
        case .code: return Color(red: 0.60, green: 0.35, blue: 0.95)
        case .files: return Color(red: 0.99, green: 0.67, blue: 0.15)
        case .colors: return Color(red: 0.95, green: 0.49, blue: 0.16)
        case .other: return Color.secondary
        }
    }
}

enum ClipboardContentKind: String {
    case text
    case link
    case image
    case code
    case files
    case colors
    case unknown

    var title: String {
        switch self {
        case .text: return AppLocalizer.current.text(.text)
        case .link: return AppLocalizer.current.text(.link)
        case .image: return AppLocalizer.current.text(.image)
        case .code: return AppLocalizer.current.text(.code)
        case .files: return AppLocalizer.current.text(.files)
        case .colors: return AppLocalizer.current.text(.colors)
        case .unknown: return AppLocalizer.current.text(.other)
        }
    }

    var symbolName: String {
        switch self {
        case .text: return "text.quote"
        case .link: return "link"
        case .image: return "photo"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .files: return "doc"
        case .colors: return "paintpalette"
        case .unknown: return "questionmark.circle"
        }
    }

    var accent: Color {
        switch self {
        case .text: return Color(red: 0.96, green: 0.48, blue: 0.18)
        case .link: return Color(red: 0.11, green: 0.66, blue: 0.53)
        case .image: return Color(red: 0.16, green: 0.54, blue: 0.96)
        case .code: return Color(red: 0.60, green: 0.35, blue: 0.95)
        case .files: return Color(red: 0.99, green: 0.67, blue: 0.15)
        case .colors: return Color(red: 0.95, green: 0.49, blue: 0.16)
        case .unknown: return Color.secondary
        }
    }
}

extension ClipboardRecord {
    var sourceAppDisplayName: String {
        if let sourceAppName = sourceAppName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceAppName.isEmpty {
            return sourceAppName
        }
        return AppLocalizer.current.text(.unknownSource)
    }

    var kind: ClipboardContentKind {
        ClipboardContentKind(rawValue: contentTypeRaw ?? "") ?? .unknown
    }

    var previewImage: NSImage? {
        guard kind == .image,
              let previewPath = thumbnailPathValue ?? imagePath,
              let image = ClipboardImageCache.shared.image(at: previewPath) else {
            return nil
        }
        return image
    }

    var originalImage: NSImage? {
        guard kind == .image,
              let imagePath,
              let image = ClipboardImageCache.shared.image(at: imagePath) else {
            return nil
        }
        return image
    }

    var previewTitle: String {
        if kind == .colors {
            return clipboardColorValue?.sourceText ?? AppLocalizer.current.text(.colors)
        }

        if let displayText, !displayText.isEmpty {
            return displayText
        }

        if kind == .image {
            return AppLocalizer.current.text(.image)
        }

        if kind == .files {
            return AppLocalizer.current.text(.fileList)
        }

        return AppLocalizer.current.text(.empty)
    }

    var previewSubtitle: String {
        if kind == .link {
            return sourceAppDisplayName
        }

        if kind == .files {
            return fileSubtitleText
        }

        if kind == .code {
            return codeLanguage.title
        }

        return sourceAppDisplayName
    }

    var sourceAppIcon: NSImage? {
        return ClipboardAppIconCache.shared.icon(bundleId: sourceBundleId)
    }

    var websiteIconImage: NSImage? {
        guard kind == .link else { return nil }
        return linkIconImage
    }

    var linkURL: URL? {
        Self.webURL(from: fullText ?? displayText)
    }

    var linkHostLabel: String? {
        guard kind == .link else { return nil }
        if let host = linkHostValue?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
            return host
        }

        if let host = linkURL?.host?.trimmingCharacters(in: .whitespacesAndNewlines),
           !host.isEmpty {
            return host
        }
        return nil
    }

    var linkTitleLabel: String? {
        guard kind == .link else { return nil }
        if let title = linkTitleValue?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return linkHostLabel
    }

    var linkIconImage: NSImage? {
        guard kind == .link,
              let data = linkIconDataValue,
              !data.isEmpty,
              let image = NSImage(data: data) else {
            return nil
        }
        return image
    }

    var rowSubtitle: String {
        if kind == .link {
            return linkTitleLabel ?? linkHostLabel ?? previewTitle
        }

        if kind == .code {
            return codeLanguage.title
        }

        if kind == .files {
            return fileSubtitleText
        }

        if kind == .colors {
            return clipboardColorValue?.sourceFormat.title ?? colorFormatLabel
        }

        return detailText
    }

    var fileIconImage: NSImage? {
        guard kind == .files else { return nil }
        return ClipboardFileIconCache.shared.icon(for: fileRepresentativeURL)
    }

    var imageFormatLabel: String {
        guard kind == .image else { return "-" }
        let path = imagePath ?? thumbnailPathValue
        return Self.fileExtensionLabel(for: path) ?? "PNG"
    }

    var imageResolutionLabel: String {
        guard kind == .image, let imagePath else { return "-" }
        return Self.imageResolutionLabel(forImageAtPath: imagePath) ?? "-"
    }

    var imageFileSizeLabel: String {
        guard kind == .image else { return "-" }
        return Self.fileSizeLabel(forPath: imagePath)
    }

    var fileSizeLabel: String {
        guard kind == .files else { return "-" }
        return fileReferenceSet.fileSizeLabel
    }

    var cachedImagePaths: [String] {
        var paths: [String] = []

        if let imagePath, !imagePath.isEmpty {
            paths.append(imagePath)
        }

        if let thumbnailPath, !thumbnailPath.isEmpty, thumbnailPath != imagePath {
            paths.append(thumbnailPath)
        }

        return paths
    }

    func detailImage(maxPixelSize: CGFloat) -> NSImage? {
        guard kind == .image, let imagePath else { return nil }
        return ClipboardImageCache.shared.downsampledImage(at: imagePath, maxPixelSize: maxPixelSize) ?? previewImage
    }

    var fileRepresentativeURL: URL? {
        guard kind == .files else { return nil }
        return fileReferenceSet.representativeURL
    }

    var detailText: String {
        if kind == .link {
            return fullText ?? displayText ?? "-"
        }

        if kind == .files {
            let filePaths = fileReferenceSet.displayPathText
            if !filePaths.isEmpty {
                return filePaths
            }

            return fileReferenceSet.overallStatusText
        }

        if let fullText, !fullText.isEmpty {
            return fullText
        }

        if kind == .colors {
            return clipboardColorValue?.sourceText ?? previewTitle
        }

        if kind == .image {
            return imagePath ?? "Image saved locally"
        }

        return previewTitle
    }

    var rowSnippet: String {
        switch kind {
        case .text, .code, .colors, .unknown:
            return detailText
        case .link:
            return fullText ?? previewTitle
        case .image:
            return "Image saved locally"
        case .files:
            return fileStatusText
        }
    }

    var fileStatusText: String {
        guard kind == .files else { return "" }
        return fileReferenceSet.overallStatusText
    }

    var fileOriginalStatusText: String {
        guard kind == .files else { return "" }
        return fileReferenceSet.originalFileStatusText
    }

    var fileCachedStatusText: String {
        guard kind == .files else { return "" }
        return fileReferenceSet.cachedCopyStatusText
    }

    var fileSubtitleText: String {
        guard kind == .files else { return "" }

        if fileReferenceSet.hasMissingOriginalFiles && !fileReferenceSet.hasCachedCopies {
            return AppLocalizer.current.text(.originalFileMissing)
        }

        let filePaths = fileReferenceSet.displayPathText
        if !filePaths.isEmpty {
            return filePaths
        }

        return fileStatusText
    }

    var imagePathText: String {
        guard kind == .image else { return "" }

        if let imagePath, !imagePath.isEmpty {
            return imagePath
        }

        if let thumbnailPathValue, !thumbnailPathValue.isEmpty {
            return thumbnailPathValue
        }

        return "-"
    }

    var fileReferenceSet: ClipboardFileReferenceSet {
        ClipboardFileReferenceSet(originalPathsText: fullText, legacyCacheFolderPath: assetPathValue)
    }

    var characterCount: Int {
        (fullText ?? displayText ?? "").count
    }

    var timeLabel: String {
        Self.formatter.string(from: createdAt ?? Date())
    }

    var timeLabelShort: String {
        Self.shortFormatter.string(from: createdAt ?? Date())
    }

    var timeLabelPrecise: String {
        Self.preciseFormatter.string(from: createdAt ?? Date())
    }

    var historyRowTimeLabel: String {
        let date = createdAt ?? Date()
        let timeText = Self.shortFormatter.string(from: date)
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "\(AppLocalizer.current.text(.today))  \(timeText)"
        }

        if calendar.isDateInYesterday(date) {
            return "\(AppLocalizer.current.text(.yesterday))  \(timeText)"
        }

        return Self.historyRowFormatter.string(from: date)
    }

    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let preciseFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    static let historyRowFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd  HH:mm"
        return formatter
    }()

    static func webURL(from string: String?) -> URL? {
        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty,
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private static func fileExtensionLabel(for path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return ext.isEmpty ? nil : ext.uppercased()
    }

    private static func imageResolutionLabel(forImageAtPath path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return "\(width) × \(height)"
    }

    private static func fileSizeLabel(forPath path: String?) -> String {
        guard let path, !path.isEmpty else { return "-" }
        let url = URL(fileURLWithPath: path)
        guard let size = fileSize(at: url) else { return "-" }
        return Self.byteCountFormatter.string(fromByteCount: Int64(size))
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

        var total: Int = 0
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

    static func fetchPredicate(searchText: String, filter: ClipboardFilter) -> NSPredicate? {
        fetchPredicate(searchText: searchText, categorySelection: filter.categorySelection)
    }

    static func fetchPredicate(searchText: String, categorySelection: ClipboardCategorySelection) -> NSPredicate? {
        var predicates: [NSPredicate] = [
            NSPredicate(format: "isIgnored == NO")
        ]

        let searchQuery = ClipboardSearchQuery(searchText)
        if let searchPredicate = searchQuery.predicate {
            predicates.append(searchPredicate)
        }

        switch categorySelection {
        case .system(let key):
            if let predicate = systemPredicate(for: key) {
                predicates.append(predicate)
            }
        case .custom(let categoryID):
            predicates.append(NSPredicate(format: "ANY categoryLinks.category.id == %@", categoryID as CVarArg))
        }

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private static func systemPredicate(for key: SystemClipboardCategoryKey) -> NSPredicate? {
        switch key {
        case .all:
            return nil
        case .text:
            return NSPredicate(format: "contentTypeRaw == %@", ClipboardContentKind.text.rawValue)
        case .links:
            return NSPredicate(format: "contentTypeRaw == %@", ClipboardContentKind.link.rawValue)
        case .images:
            return NSPredicate(format: "contentTypeRaw == %@", ClipboardContentKind.image.rawValue)
        case .code:
            return NSPredicate(format: "contentTypeRaw == %@", ClipboardContentKind.code.rawValue)
        case .files:
            return NSPredicate(format: "contentTypeRaw == %@", ClipboardContentKind.files.rawValue)
        case .colors:
            return NSPredicate(format: "contentTypeRaw == %@", ClipboardContentKind.colors.rawValue)
        case .other:
            return NSPredicate(format: "contentTypeRaw == %@", ClipboardContentKind.unknown.rawValue)
        }
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
    }
}

func removeCachedAssets(for record: ClipboardRecord) {
    if let imagePath = record.imagePath, !imagePath.isEmpty {
        try? FileManager.default.removeItem(atPath: imagePath)
        ClipboardImageCache.shared.remove(path: imagePath)
    }
    if let cachedFolderURL = record.fileReferenceSet.cachedFolderURL {
        try? FileManager.default.removeItem(at: cachedFolderURL)
    }
    if let thumbnailPath = record.thumbnailPathValue, !thumbnailPath.isEmpty {
        try? FileManager.default.removeItem(atPath: thumbnailPath)
        ClipboardImageCache.shared.remove(path: thumbnailPath)
    }
}

final class ClipboardImageCache {
    static let shared = ClipboardImageCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 48
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func image(at path: String, preferredSize: CGSize? = nil) -> NSImage? {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let image = NSImage(contentsOfFile: path) else {
            return nil
        }

        if let preferredSize {
            image.size = preferredSize
        }

        cache.setObject(image, forKey: key, cost: Self.cacheCost(for: image))
        return image
    }

    func downsampledImage(at path: String, maxPixelSize: CGFloat) -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixelSize = max(1, maxPixelSize * scale)
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    func remove(path: String) {
        cache.removeObject(forKey: path as NSString)
    }

    func remove(paths: [String]) {
        paths.forEach { cache.removeObject(forKey: $0 as NSString) }
    }

    private static func cacheCost(for image: NSImage) -> Int {
        let pixelWidth = max(1, Int(image.size.width))
        let pixelHeight = max(1, Int(image.size.height))
        return pixelWidth * pixelHeight * 4
    }
}

final class ClipboardAppIconCache {
    static let shared = ClipboardAppIconCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 24
        cache.totalCostLimit = 8 * 1024 * 1024
    }

    func icon(bundleId: String?) -> NSImage? {
        let key = bundleId ?? "__generic__"
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        let icon: NSImage
        if let bundleId,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            icon = NSWorkspace.shared.icon(forFile: appURL.path)
        } else {
            icon = NSWorkspace.shared.icon(for: UTType.application)
        }
        icon.size = NSSize(width: 128, height: 128)
        cache.setObject(icon, forKey: key as NSString, cost: Self.cacheCost(for: icon))
        return icon
    }

    private static func cacheCost(for icon: NSImage) -> Int {
        let pixelWidth = max(1, Int(icon.size.width))
        let pixelHeight = max(1, Int(icon.size.height))
        return pixelWidth * pixelHeight * 4
    }
}

final class ClipboardFileIconCache {
    static let shared = ClipboardFileIconCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 24
        cache.totalCostLimit = 8 * 1024 * 1024
    }

    func icon(for url: URL?) -> NSImage? {
        let contentType = Self.contentType(for: url)
        let cacheKey = contentType?.identifier ?? "__generic_file__"

        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached
        }

        let icon = NSWorkspace.shared.icon(for: contentType ?? .data)
        icon.size = NSSize(width: 256, height: 256)
        cache.setObject(icon, forKey: cacheKey as NSString, cost: Self.cacheCost(for: icon))
        return icon
    }

    private static func contentType(for url: URL?) -> UTType? {
        guard let url else { return nil }

        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey]),
           let contentType = values.contentType {
            return contentType
        }

        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return .folder
        }

        let ext = url.pathExtension.lowercased()
        if let mappedExtension = mappedPreferredExtension(forExtension: ext),
           let type = UTType(filenameExtension: mappedExtension) {
            return type
        }

        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            return type
        }

        return nil
    }

    private static func mappedPreferredExtension(forExtension ext: String) -> String? {
        switch ext {
        case "pdf":
            return "pdf"
        case "rtf":
            return "rtf"
        case "txt", "text", "log", "md", "markdown", "rst", "ini", "conf", "cfg":
            return "txt"
        case "csv", "tsv":
            return "csv"
        case "json":
            return "json"
        case "xml", "plist":
            return "xml"
        case "html", "htm":
            return "html"
        case "yaml", "yml":
            return "yaml"
        case "swift":
            return "swift"
        case "c":
            return "c"
        case "h", "hh", "hpp":
            return "h"
        case "m":
            return "m"
        case "mm":
            return "mm"
        case "js", "mjs", "cjs":
            return "js"
        case "ts", "mts", "cts":
            return "ts"
        case "jsx":
            return "jsx"
        case "tsx":
            return "tsx"
        case "py":
            return "py"
        case "sh", "bash", "zsh", "fish":
            return "sh"
        case "sql":
            return "sql"
        case "zip":
            return "zip"
        case "gz", "tgz":
            return "gz"
        case "tar":
            return "tar"
        case "7z":
            return "7z"
        case "rar":
            return "rar"
        case "dmg":
            return "dmg"
        case "pkg":
            return "pkg"
        case "iso":
            return "iso"
        case "pages":
            return "pages"
        case "numbers":
            return "numbers"
        case "key":
            return "key"
        case "doc":
            return "doc"
        case "docx":
            return "docx"
        case "dotx":
            return "dotx"
        case "xls":
            return "xls"
        case "xlsx":
            return "xlsx"
        case "xlsm":
            return "xlsm"
        case "xltx":
            return "xltx"
        case "ppt":
            return "ppt"
        case "pptx":
            return "pptx"
        case "odp":
            return "odp"
        case "odt":
            return "odt"
        case "ods":
            return "ods"
        case "png":
            return "png"
        case "jpg", "jpeg", "jpe":
            return "jpg"
        case "gif":
            return "gif"
        case "webp":
            return "webp"
        case "heic":
            return "heic"
        case "heif":
            return "heif"
        case "tif", "tiff":
            return "tiff"
        case "bmp":
            return "bmp"
        case "svg":
            return "svg"
        case "psd":
            return "psd"
        case "mp3":
            return "mp3"
        case "aac":
            return "aac"
        case "m4a":
            return "m4a"
        case "wav":
            return "wav"
        case "aiff", "aif":
            return "aiff"
        case "flac":
            return "flac"
        case "mp4":
            return "mp4"
        case "m4v":
            return "m4v"
        case "mov":
            return "mov"
        case "avi":
            return "avi"
        case "mkv":
            return "mkv"
        case "webm":
            return "webm"
        case "srt":
            return "srt"
        case "vtt":
            return "vtt"
        default:
            return nil
        }
    }

    private static func cacheCost(for icon: NSImage) -> Int {
        let pixelWidth = max(1, Int(icon.size.width))
        let pixelHeight = max(1, Int(icon.size.height))
        return pixelWidth * pixelHeight * 4
    }
}

struct ClipboardSnapshot {
    let kind: ClipboardContentKind
    let displayText: String
    let fullText: String?
    let imagePath: String?
    let assetPath: String?
    let thumbnailPath: String?
    let cachedSizeBytes: Int64
    let sourceAppName: String?
    let sourceBundleId: String?
    let hash: String
}

struct SavedImageAssets {
    let original: URL
    let thumbnail: URL
    let originalData: Data
    let thumbnailData: Data?

    var cachedSizeBytes: Int64 {
        let thumbnailBytes = Int64(thumbnailData?.count ?? originalData.count)
        return Int64(originalData.count) + thumbnailBytes
    }
}

func clipboardRecordDisplaysBefore(_ lhs: ClipboardRecord, _ rhs: ClipboardRecord) -> Bool {
    if lhs.isPinned != rhs.isPinned {
        return lhs.isPinned && !rhs.isPinned
    }

    let lhsAnchor = lhs.isPinned ? (lhs.pinnedAtValue ?? lhs.updatedAt ?? lhs.createdAt ?? .distantPast) : (lhs.createdAt ?? .distantPast)
    let rhsAnchor = rhs.isPinned ? (rhs.pinnedAtValue ?? rhs.updatedAt ?? rhs.createdAt ?? .distantPast) : (rhs.createdAt ?? .distantPast)
    if lhsAnchor != rhsAnchor {
        return lhsAnchor > rhsAnchor
    }

    return lhs.objectID.uriRepresentation().absoluteString < rhs.objectID.uriRepresentation().absoluteString
}

extension ClipboardRecord {
    var cachedSizeBytesValue: Int64 {
        get { Int64((value(forKey: "cachedSizeBytes") as? NSNumber)?.int64Value ?? 0) }
        set { setValue(newValue, forKey: "cachedSizeBytes") }
    }

    var thumbnailPathValue: String? {
        get { thumbnailPath }
        set { thumbnailPath = newValue }
    }

    var assetPathValue: String? {
        get { assetPath }
        set { assetPath = newValue }
    }

    var pinnedAtValue: Date? {
        get { pinnedAt }
        set { pinnedAt = newValue }
    }

    var linkHostValue: String? {
        get { linkHost }
        set { linkHost = newValue }
    }

    var linkTitleValue: String? {
        get { linkTitle }
        set { linkTitle = newValue }
    }

    var linkIconDataValue: Data? {
        get { linkIconData }
        set { linkIconData = newValue }
    }

    var linkMetadataCheckedAtValue: Date? {
        get { linkMetadataCheckedAt }
        set { linkMetadataCheckedAt = newValue }
    }
}
