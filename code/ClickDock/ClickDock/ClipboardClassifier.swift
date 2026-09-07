//
//  ClipboardClassifier.swift
//  ClipDock
//

import CryptoKit
import Foundation

struct ClipboardClassification {
    let kind: ClipboardContentKind
    let color: ClipboardColorValue?
}

struct ClipboardClassifier {
    func classify(text: String) -> ClipboardClassification {
        let detectedColor = ClipboardColorDetector.detect(from: text)
        let kind: ClipboardContentKind
        if ClipboardRecord.webURL(from: text) != nil {
            kind = .link
        } else if detectedColor != nil {
            kind = .colors
        } else if isLikelyCode(text) || ClipboardCodeLanguageDetector.detect(from: text) != .plain {
            kind = .code
        } else {
            kind = .text
        }
        return ClipboardClassification(kind: kind, color: detectedColor)
    }

    func previewText(from text: String) -> String {
        let limit = 120
        guard text.count > limit else { return text }
        let index = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<index]) + "…"
    }

    func hash(kind: ClipboardContentKind, text: String) -> String {
        switch kind {
        case .image, .files:
            return hash(kind: kind, data: Data(text.utf8))
        case .text, .link, .code, .colors, .unknown:
            return text
        }
    }

    func hash(kind: ClipboardContentKind, data: Data) -> String {
        let digest = SHA256.hash(data: Data(kind.rawValue.utf8) + data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func isLikelyCode(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.count <= 8_000 else { return false }

        let lines = trimmed.split(whereSeparator: \.isNewline)
        let lowercased = trimmed.lowercased()
        let strongCodeMarkers = ["func ", "class ", "struct ", "enum ", "protocol ", "extension ", "import ", "public class ", "public static void main", "def ", "const ", "let ", "var ", "interface ", "type "]
        let weakCodeKeywords = ["if ", "for ", "while ", "switch ", "case ", "return "]
        let codeSymbols = ["{", "}", ";", "=>", "->", "==", "!=", "&&", "||", "</", "/>", "[", "]"]

        let strongMarkerHits = strongCodeMarkers.reduce(0) { $0 + (lowercased.contains($1) ? 1 : 0) }
        let weakKeywordHits = weakCodeKeywords.reduce(0) { $0 + (lowercased.contains($1) ? 1 : 0) }
        let symbolHits = codeSymbols.reduce(0) { $0 + (trimmed.contains($1) ? 1 : 0) }
        let hasIndentedBlock = lines.count >= 2 && lines.contains { $0.hasPrefix("    ") || $0.hasPrefix("\t") }
        let hasMultiLineCodeShape = lines.count >= 2 && symbolHits >= 2

        if trimmed.contains("```") { return true }
        if strongMarkerHits >= 1 && (symbolHits >= 1 || hasIndentedBlock || lines.count >= 2) { return true }
        if hasMultiLineCodeShape && weakKeywordHits >= 1 { return true }
        if hasIndentedBlock && (strongMarkerHits >= 1 || weakKeywordHits >= 2 || symbolHits >= 1) { return true }
        return false
    }
}
