//
//  ClipboardPrivacyRules.swift
//  ClipDock
//

import AppKit
import Foundation

enum ClipboardPrivacyRules {
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

    static func shouldIgnoreCapturedText(_ text: String, defaults: UserDefaults = .standard) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        for candidate in inspectionCandidates(for: trimmed) {
            if defaults.bool(forKey: ignoreVerificationCodesStorageKey),
               matchesVerificationCode(candidate) {
                return true
            }

            if defaults.bool(forKey: ignorePasswordsAndTokensStorageKey),
               matchesPasswordsOrTokens(candidate) {
                return true
            }

            if defaults.bool(forKey: ignorePrivateKeysStorageKey),
               matchesPrivateKeys(candidate) {
                return true
            }

            if defaults.bool(forKey: ignoreLongSensitiveTextStorageKey),
               matchesLongSensitiveText(candidate) {
                return true
            }
        }

        return false
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
        let lowercased = text.lowercased()
        let keywordMatches = [
            "password",
            "secret",
            "api_key",
            "access_token",
            "refresh_token",
            "authorization: bearer",
            "jwt token",
            "bearer "
        ]

        if keywordMatches.contains(where: lowercased.contains) {
            return true
        }

        if isLikelyJWT(text) || containsSensitiveEnvContent(text) || containsPaymentCardNumber(text) {
            return true
        }

        return false
    }

    static func matchesPrivateKeys(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        if lowercased.contains("private key") {
            return true
        }

        return lowercased.contains("-----begin") && lowercased.contains("private key-----")
    }

    static func matchesLongSensitiveText(_ text: String) -> Bool {
        guard text.count >= 160 else { return false }

        if matchesPrivateKeys(text) || containsSensitiveEnvContent(text) || isLikelyJWT(text) {
            return true
        }

        let lowercased = text.lowercased()
        let sensitiveSignals = [
            "password",
            "secret",
            "token",
            "authorization",
            "private key",
            "api_key",
            "access_token",
            "refresh_token"
        ]

        let signalCount = sensitiveSignals.reduce(0) { partialResult, signal in
            partialResult + (lowercased.contains(signal) ? 1 : 0)
        }

        return signalCount >= 2
    }

    private static func containsSensitiveEnvContent(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
        guard !lines.isEmpty else { return false }

        let envKeys = [
            "password",
            "secret",
            "token",
            "api_key",
            "access_token",
            "refresh_token",
            "private_key",
            "jwt"
        ]

        var assignmentCount = 0
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let separatorIndex = line.firstIndex(of: "=") else {
                continue
            }

            assignmentCount += 1
            let key = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if envKeys.contains(where: key.contains) {
                return true
            }
        }

        return assignmentCount >= 3
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
