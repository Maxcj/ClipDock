//
//  LinkMetadataFetcher.swift
//  ClipDock
//

import Foundation

enum LinkMetadataPrivacyPolicy {
    static let allowPrivateNetworkStorageKey = "clipboard.linkMetadataAllowPrivateNetwork"

    static func canFetchMetadata(for url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return false
        }

        if isLocalOrPrivateHost(host) {
            return UserDefaults.standard.bool(forKey: allowPrivateNetworkStorageKey)
        }

        return true
    }

    private static func isLocalOrPrivateHost(_ host: String) -> Bool {
        let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if normalizedHost == "localhost" ||
            normalizedHost.hasSuffix(".localhost") ||
            normalizedHost.hasSuffix(".local") ||
            normalizedHost == "internal" ||
            normalizedHost.hasSuffix(".internal") {
            return true
        }

        if !normalizedHost.contains(".") && !normalizedHost.contains(":") {
            return true
        }

        if isPrivateIPv4Host(normalizedHost) || isPrivateIPv6Host(normalizedHost) {
            return true
        }

        return false
    }

    private static func isPrivateIPv4Host(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4,
              let first = UInt8(parts[0]),
              let second = UInt8(parts[1]) else {
            return false
        }

        switch first {
        case 0, 10, 127:
            return true
        case 100:
            return (64...127).contains(second)
        case 169:
            return second == 254
        case 172:
            return (16...31).contains(second)
        case 192:
            return second == 168
        default:
            return false
        }
    }

    private static func isPrivateIPv6Host(_ host: String) -> Bool {
        host == "::1" ||
            host.hasPrefix("fc") ||
            host.hasPrefix("fd") ||
            host.hasPrefix("fe80:")
    }
}

struct LinkMetadata {
    let title: String?
    let host: String?
    let iconData: Data?
}

enum LinkMetadataFetcher {
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
        guard LinkMetadataPrivacyPolicy.canFetchMetadata(for: url) else {
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
        guard LinkMetadataPrivacyPolicy.canFetchMetadata(for: url) else {
            return nil
        }

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
        guard LinkMetadataPrivacyPolicy.canFetchMetadata(for: url) else {
            return nil
        }

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
