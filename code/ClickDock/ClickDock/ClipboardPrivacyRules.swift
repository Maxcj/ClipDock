//
//  ClipboardPrivacyRules.swift
//  ClipDock
//

import AppKit
import Foundation

enum ClipboardPrivacyRules {
    enum IgnoreReason: CustomStringConvertible {
        case verificationCode
        case passwordsOrTokens
        case privateKey
        case longSensitiveText
        case privateKeyFile

        var description: String {
            switch self {
            case .verificationCode: return "verification code"
            case .passwordsOrTokens: return "password/token"
            case .privateKey: return "private key"
            case .longSensitiveText: return "long sensitive text"
            case .privateKeyFile: return "private key file"
            }
        }
    }

    static let excludedBundleIdentifiersStorageKey = "clipboard.excludedSourceBundleIdentifiers"
    static let ignoreVerificationCodesStorageKey = "clipboard.ignoreVerificationCodes"
    static let ignorePasswordsAndTokensStorageKey = "clipboard.ignorePasswordsAndTokens"
    static let ignorePrivateKeysStorageKey = "clipboard.ignorePrivateKeys"
    static let ignoreLongSensitiveTextStorageKey = "clipboard.ignoreLongSensitiveText"

    static func bundleIdentifiers(from storageValue: String) -> [String] {
        storageValue
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func storageValue(from bundleIdentifiers: [String]) -> String {
        var seen = Set<String>()
        return bundleIdentifiers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .joined(separator: "\n")
    }

    static func isExcluded(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let excluded = bundleIdentifiers(from: UserDefaults.standard.string(forKey: excludedBundleIdentifiersStorageKey) ?? "")
        return excluded.contains(bundleIdentifier)
    }

    static func displayName(for bundleIdentifier: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let values = try? url.resourceValues(forKeys: [.localizedNameKey])
            if let localizedName = values?.localizedName, !localizedName.isEmpty {
                return localizedName
            }
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleIdentifier
    }

    static func shouldIgnoreCapturedText(
        _ text: String,
        contentKind: ClipboardContentKind? = nil,
        defaults: UserDefaults = .standard
    ) -> IgnoreReason? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch contentKind {
        case .code:
            return ignoreReasonForCodeContent(trimmed, defaults: defaults)
        case .colors:
            return nil
        case .image, .files:
            return ignoreReasonForFileLikeContent(trimmed, defaults: defaults)
        case .link, .text, .unknown, nil:
            for candidate in inspectionCandidates(for: trimmed) {
                if defaults.bool(forKey: ignoreVerificationCodesStorageKey),
                   matchesVerificationCode(candidate) {
                    return .verificationCode
                }

                if defaults.bool(forKey: ignorePasswordsAndTokensStorageKey),
                   matchesPasswordsOrTokens(candidate) {
                    return .passwordsOrTokens
                }

                if defaults.bool(forKey: ignorePrivateKeysStorageKey),
                   matchesPrivateKeys(candidate) {
                    return .privateKey
                }

                if defaults.bool(forKey: ignoreLongSensitiveTextStorageKey),
                   matchesLongSensitiveText(candidate, includePrivateKeys: defaults.bool(forKey: ignorePrivateKeysStorageKey)) {
                    return .longSensitiveText
                }
            }
        }

        return nil
    }

    static func shouldIgnoreCapturedFileURLs(_ fileURLs: [URL], defaults: UserDefaults = .standard) -> IgnoreReason? {
        guard !fileURLs.isEmpty else { return nil }

        if defaults.bool(forKey: ignorePrivateKeysStorageKey) {
            for url in fileURLs where isLikelyPrivateKeyFile(url) {
                return .privateKeyFile
            }
        }

        for url in fileURLs {
            guard let text = textContent(from: url) else { continue }
            if let reason = shouldIgnoreCapturedText(text, contentKind: .files, defaults: defaults) {
                return reason
            }
        }

        return nil
    }

    private static func inspectionCandidates(for text: String) -> [String] {
        var candidates = [text]

        let compact = text.replacingOccurrences(
            of: #"[^\p{L}\p{N}]+"#,
            with: "",
            options: .regularExpression
        )
        if !compact.isEmpty, compact != text {
            candidates.append(compact)
        }

        return candidates
    }

    static func matchesVerificationCode(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^\d{6}$"#, options: .regularExpression) != nil {
            return true
        }

        let lowercased = trimmed.lowercased()
        let verificationHints = ["verification code", "verify code", "otp", "one-time password", "验证码", "校验码"]
        if verificationHints.contains(where: lowercased.contains),
           trimmed.range(of: #"\b\d{6}\b"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    static func matchesPasswordsOrTokens(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if isLikelyJWT(trimmed) || containsPaymentCardNumber(trimmed) {
            return true
        }

        if containsSensitiveCredentialAssignment(trimmed) {
            return true
        }

        if containsSensitiveEnvContent(trimmed) {
            return true
        }

        return false
    }

    private static func ignoreReasonForCodeContent(_ text: String, defaults: UserDefaults) -> IgnoreReason? {
        if defaults.bool(forKey: ignorePrivateKeysStorageKey), matchesPrivateKeys(text) {
            return .privateKey
        }

        if defaults.bool(forKey: ignorePasswordsAndTokensStorageKey),
           containsSensitiveCredentialAssignment(text) {
            return .passwordsOrTokens
        }

        if defaults.bool(forKey: ignoreVerificationCodesStorageKey),
           matchesVerificationCode(text) {
            return .verificationCode
        }

        if defaults.bool(forKey: ignorePasswordsAndTokensStorageKey),
           matchesPaymentOrJWT(text, includeEnvContent: false) {
            return .passwordsOrTokens
        }

        return nil
    }

    private static func ignoreReasonForFileLikeContent(_ text: String, defaults: UserDefaults) -> IgnoreReason? {
        if defaults.bool(forKey: ignorePrivateKeysStorageKey), matchesPrivateKeys(text) {
            return .privateKey
        }

        if defaults.bool(forKey: ignorePasswordsAndTokensStorageKey),
           matchesPasswordsOrTokens(text) {
            return .passwordsOrTokens
        }

        if defaults.bool(forKey: ignoreVerificationCodesStorageKey),
           matchesVerificationCode(text) {
            return .verificationCode
        }

        if defaults.bool(forKey: ignoreLongSensitiveTextStorageKey),
           matchesLongSensitiveText(text, includePrivateKeys: defaults.bool(forKey: ignorePrivateKeysStorageKey)) {
            return .longSensitiveText
        }

        return nil
    }

    static func matchesPrivateKeys(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        if lowercased.contains("private key") {
            return true
        }

        return lowercased.contains("-----begin") && lowercased.contains("private key-----")
    }

    private static func isLikelyPrivateKeyFile(_ url: URL) -> Bool {
        let extensionName = url.pathExtension.lowercased()
        if extensionName == "pem" || extensionName == "key" {
            return true
        }

        let lowerName = url.lastPathComponent.lowercased()
        return lowerName.contains("private") && (lowerName.contains("key") || extensionName == "txt")
    }

    private static func textContent(from url: URL, byteLimit: Int = 64 * 1024) -> String? {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true else { return nil }

        if let fileSize = values?.fileSize, fileSize > 2 * 1024 * 1024 {
            return nil
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { handle.closeFile() }

        guard let data = try? handle.read(upToCount: byteLimit), !data.isEmpty else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func matchesLongSensitiveText(_ text: String, includePrivateKeys: Bool = true) -> Bool {
        guard text.count >= 160 else { return false }

        if (includePrivateKeys && matchesPrivateKeys(text)) || containsSensitiveEnvContent(text) || isLikelyJWT(text) {
            return true
        }

        let lowercased = text.lowercased()
        let sensitiveSignals = [
            "password",
            "secret",
            "authorization",
            "api_key",
            "access_token",
            "refresh_token"
        ]

        if includePrivateKeys, lowercased.contains("private key") {
            return true
        }

        let signalCount = sensitiveSignals.reduce(0) { partialResult, signal in
            partialResult + (lowercased.contains(signal) ? 1 : 0)
        }

        return signalCount >= 2
    }

    private static func matchesPaymentOrJWT(_ text: String, includeEnvContent: Bool) -> Bool {
        if isLikelyJWT(text) || containsPaymentCardNumber(text) {
            return true
        }

        if containsSensitiveCredentialAssignment(text) {
            return true
        }

        if includeEnvContent, containsSensitiveEnvContent(text) {
            return true
        }

        return false
    }

    private static func containsSensitiveEnvContent(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
        guard !lines.isEmpty else { return false }

        var assignmentCount = 0
        var sensitiveAssignmentCount = 0
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let assignment = parseAssignment(in: line) else {
                continue
            }

            assignmentCount += 1
            if isSensitiveCredentialKey(assignment.key), isLikelySecretValue(assignment.value) {
                sensitiveAssignmentCount += 1
            }
        }

        if sensitiveAssignmentCount >= 1 && assignmentCount >= 3 {
            return true
        }

        return sensitiveAssignmentCount >= 2
    }

    private static func containsSensitiveCredentialAssignment(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
        guard !lines.isEmpty else { return false }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let assignment = parseAssignment(in: line) else {
                continue
            }

            if isSensitiveCredentialKey(assignment.key), isLikelySecretValue(assignment.value) {
                return true
            }
        }

        return false
    }

    private static func parseAssignment(in line: String) -> (key: String, value: String)? {
        let separators: [Character] = ["=", ":"]
        guard let separator = line.firstIndex(where: { separators.contains($0) }) else {
            return nil
        }

        let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        let valueStart = line.index(after: separator)
        let value = line[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !value.isEmpty else { return nil }
        return (key: key, value: value)
    }

    private static func isSensitiveCredentialKey(_ key: String) -> Bool {
        let normalized = key
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        let directMatches = [
            "password",
            "secret",
            "api_key",
            "access_token",
            "refresh_token",
            "id_token",
            "auth_token",
            "client_secret",
            "private_key",
            "bearer"
        ]

        if directMatches.contains(where: { normalized == $0 || normalized.contains("\($0)_") || normalized.hasSuffix("_\($0)") }) {
            return true
        }

        return normalized.contains("password") || normalized.contains("secret") || normalized.contains("private_key")
    }

    private static func isLikelySecretValue(_ value: String) -> Bool {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`;,"))

        guard !trimmed.isEmpty else { return false }

        if trimmed.lowercased().hasPrefix("bearer ") {
            let token = trimmed.dropFirst("bearer ".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return token.count >= 16 && token.range(of: #"^[A-Za-z0-9._\-+/=]+$"#, options: .regularExpression) != nil
        }

        if trimmed.range(of: #"[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#, options: .regularExpression) != nil {
            return true
        }

        if trimmed.count >= 20,
           trimmed.range(of: #"^[A-Za-z0-9._\-+/=]+$"#, options: .regularExpression) != nil {
            return true
        }

        if trimmed.count >= 24,
           trimmed.contains(where: { $0.isNumber }),
           trimmed.contains(where: { $0.isLetter }) {
            return true
        }

        return false
    }

    private static func isLikelyJWT(_ text: String) -> Bool {
        guard let match = text.range(
            of: #"[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#,
            options: .regularExpression
        ) else {
            return false
        }

        return !text[match].isEmpty
    }

    private static func containsPaymentCardNumber(_ text: String) -> Bool {
        let pattern = #"\b(?:\d[ -]*?){13,19}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range).map { match in
            guard let valueRange = Range(match.range, in: text) else { return false }
            let digits = text[valueRange].filter(\.isNumber)
            return isValidLuhnNumber(String(digits))
        } ?? false
    }

    private static func isValidLuhnNumber(_ digits: String) -> Bool {
        guard (13...19).contains(digits.count) else { return false }

        var sum = 0
        let reversedDigits = digits.reversed().compactMap { Int(String($0)) }
        guard reversedDigits.count == digits.count else { return false }

        for (index, digit) in reversedDigits.enumerated() {
            if index.isMultiple(of: 2) {
                sum += digit
            } else {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
        }

        return sum.isMultiple(of: 10)
    }
}
