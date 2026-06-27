//
//  ClipboardCodeSupport.swift
//  ClipDock
//

import SwiftUI
import AppKit
import Foundation

enum ClipboardCodeLanguage: String, CaseIterable, Identifiable, Codable {
    case plain
    case json
    case swift
    case java
    case javascript
    case typescript
    case sql
    case shell
    case html
    case css
    case python
    case xml
    case yaml

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain: return "Plain Text"
        case .json: return "JSON"
        case .swift: return "Swift"
        case .java: return "Java"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .sql: return "SQL"
        case .shell: return "Shell"
        case .html: return "HTML"
        case .css: return "CSS"
        case .python: return "Python"
        case .xml: return "XML"
        case .yaml: return "YAML"
        }
    }

    var markdownIdentifier: String {
        switch self {
        case .javascript: return "javascript"
        case .typescript: return "typescript"
        case .shell: return "bash"
        case .plain: return ""
        default: return rawValue
        }
    }

    var badgeColor: Color {
        switch self {
        case .plain: return Color.secondary
        case .json: return Color(red: 0.14, green: 0.58, blue: 0.86)
        case .swift: return Color(red: 0.95, green: 0.49, blue: 0.16)
        case .java: return Color(red: 0.87, green: 0.35, blue: 0.16)
        case .javascript: return Color(red: 0.85, green: 0.64, blue: 0.14)
        case .typescript: return Color(red: 0.12, green: 0.47, blue: 0.78)
        case .sql: return Color(red: 0.53, green: 0.35, blue: 0.91)
        case .shell: return Color(red: 0.22, green: 0.65, blue: 0.36)
        case .html: return Color(red: 0.87, green: 0.30, blue: 0.23)
        case .css: return Color(red: 0.20, green: 0.54, blue: 0.96)
        case .python: return Color(red: 0.90, green: 0.73, blue: 0.17)
        case .xml: return Color(red: 0.77, green: 0.39, blue: 0.19)
        case .yaml: return Color(red: 0.62, green: 0.40, blue: 0.87)
        }
    }

    var iconSymbolName: String {
        switch self {
        case .plain: return "doc.plaintext"
        case .json: return "curlybraces"
        case .swift: return "swift"
        case .java: return "mug.fill"
        case .javascript: return "curlybraces"
        case .typescript: return "curlybraces"
        case .sql: return "tablecells"
        case .shell: return "terminal"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .css: return "curlybraces"
        case .python: return "doc.text"
        case .xml: return "chevron.left.forwardslash.chevron.right"
        case .yaml: return "doc.text"
        }
    }
}

enum ClipboardCodeLanguageDetector {
    static func detect(from text: String) -> ClipboardCodeLanguage {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .plain }

        if isJSON(trimmed) { return .json }
        if isXML(trimmed) { return .xml }
        if isHTML(trimmed) { return .html }
        if isSQL(trimmed) { return .sql }
        if isSwift(trimmed) { return .swift }
        if isJava(trimmed) { return .java }
        if isJavaScript(trimmed) { return .javascript }
        if isTypeScript(trimmed) { return .typescript }
        if isShell(trimmed) { return .shell }
        if isCSS(trimmed) { return .css }
        if isPython(trimmed) { return .python }
        if isYAML(trimmed) { return .yaml }
        return .plain
    }

    private static func isJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func isXML(_ text: String) -> Bool {
        text.hasPrefix("<") && text.contains("</") && text.contains(">")
    }

    private static func isHTML(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("<!doctype html") || lower.contains("<html") || lower.contains("</div") || lower.contains("</span")
    }

    private static func isSQL(_ text: String) -> Bool {
        let upper = text.uppercased()
        let trimmed = upper.trimmingCharacters(in: .whitespacesAndNewlines)

        let sqlStarts = [
            "SELECT ",
            "INSERT INTO ",
            "UPDATE ",
            "DELETE FROM ",
            "CREATE TABLE ",
            "ALTER TABLE "
        ]

        let hasSqlStart = sqlStarts.contains { trimmed.hasPrefix($0) }
        let hasSqlStructure =
            upper.contains(" FROM ") ||
            upper.contains(" WHERE ") ||
            upper.contains(" JOIN ") ||
            upper.contains(" SET ") ||
            upper.contains(" VALUES ")

        return hasSqlStart && hasSqlStructure
    }

    private static func isSwift(_ text: String) -> Bool {
        let markers = ["import SwiftUI", "import Foundation", "struct ", "class ", "enum ", "func ", "let ", "var ", "protocol ", "extension "]
        return markers.reduce(0) { $0 + (text.contains($1) ? 1 : 0) } >= 2
    }

    private static func isJava(_ text: String) -> Bool {
        let markers = [
            "package ",
            "import java.",
            "public class ",
            "public interface ",
            "public static void main",
            "System.out.println",
            "implements ",
            "extends ",
            "new "
        ]
        return markers.reduce(0) { $0 + (text.contains($1) ? 1 : 0) } >= 2
    }

    private static func isJavaScript(_ text: String) -> Bool {
        let markers = ["const ", "let ", "var ", "function ", "=>", "export ", "import ", "document.", "window."]
        return markers.reduce(0) { $0 + (text.contains($1) ? 1 : 0) } >= 2
    }

    private static func isTypeScript(_ text: String) -> Bool {
        let markers = [
            "interface ",
            "enum ",
            "type ",
            "export ",
            "import ",
            "from ",
            ": string",
            ": number",
            "readonly ",
            "implements ",
            " as "
        ]
        return markers.reduce(0) { $0 + (text.contains($1) ? 1 : 0) } >= 2
    }

    private static func isShell(_ text: String) -> Bool {
        text.hasPrefix("#!") || text.contains("brew install ") || text.contains("npm install ") || text.contains("git ")
    }

    private static func isCSS(_ text: String) -> Bool {
        text.contains("{") && text.contains("}") && text.contains(":") && text.contains(";")
    }

    private static func isPython(_ text: String) -> Bool {
        let markers = ["def ", "import ", "from ", "class ", "self", "lambda ", "print("]
        return markers.reduce(0) { $0 + (text.contains($1) ? 1 : 0) } >= 2
    }

    private static func isYAML(_ text: String) -> Bool {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        guard lines.count >= 2 else { return false }

        let yamlLikeLineCount = lines.filter { line in
            line.range(of: #"^[-\s]*[A-Za-z0-9_\-]+\s*:"#, options: .regularExpression) != nil
        }.count

        return yamlLikeLineCount >= 2
    }
}

enum ClipboardCodeActions {
    static func markdownCodeBlock(_ code: String, language: ClipboardCodeLanguage) -> String {
        let identifier = language.markdownIdentifier
        return """
        ```\(identifier)
        \(code)
        ```
        """
    }

    static func prettyJSON(_ code: String) -> String? {
        guard let data = code.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return result
    }

    static func minifyJSON(_ code: String) -> String? {
        guard let data = code.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let minifiedData = try? JSONSerialization.data(withJSONObject: object),
              let result = String(data: minifiedData, encoding: .utf8) else {
            return nil
        }
        return result
    }
}

extension ClipboardRecord {
    var codeLanguage: ClipboardCodeLanguage {
        ClipboardCodeLanguageDetector.detect(from: fullText ?? displayText ?? "")
    }

    var codeLineCount: Int {
        ClipboardCodeLineCache.shared.lines(for: self).count
    }

    var codeDisplayTitle: String {
        let title = (displayText ?? fullText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? codeLanguage.title : title
    }
}

enum ClipboardCodeHighlighter {
    static func attributedLine(_ line: String, language: ClipboardCodeLanguage) -> AttributedString {
        var attributed = AttributedString(line.isEmpty ? " " : line)
        attributed.font = .system(size: 13, design: .monospaced)

        switch language {
        case .json:
            applyJSONHighlights(to: &attributed, text: line)
        case .swift:
            applyKeywordHighlights(to: &attributed, text: line, keywords: swiftKeywords, color: Color(red: 0.56, green: 0.34, blue: 0.92), bold: true)
            applyQuotedStringHighlights(to: &attributed, text: line, color: Color(red: 0.11, green: 0.64, blue: 0.36))
            applyCommentHighlights(to: &attributed, text: line, prefix: "//", color: .secondary)
        case .java:
            applyKeywordHighlights(to: &attributed, text: line, keywords: javaKeywords, color: Color(red: 0.56, green: 0.34, blue: 0.92), bold: true)
            applyQuotedStringHighlights(to: &attributed, text: line, color: Color(red: 0.11, green: 0.64, blue: 0.36))
            applyCommentHighlights(to: &attributed, text: line, prefix: "//", color: .secondary)
        case .sql:
            applyKeywordHighlights(to: &attributed, text: line, keywords: sqlKeywords, color: Color(red: 0.17, green: 0.48, blue: 0.95), bold: true)
            applyQuotedStringHighlights(to: &attributed, text: line, color: Color(red: 0.11, green: 0.64, blue: 0.36))
        case .shell:
            applyCommentHighlights(to: &attributed, text: line, prefix: "#", color: .secondary)
            applyCommandHighlights(to: &attributed, text: line)
        default:
            break
        }

        return attributed
    }

    private static let swiftKeywords = [
        "actor", "as", "async", "await", "case", "catch", "class", "continue", "default", "defer", "do", "else",
        "enum", "extension", "for", "func", "guard", "if", "import", "in", "init", "let", "nil", "protocol",
        "return", "self", "static", "struct", "switch", "throw", "throws", "try", "var", "where", "while"
    ]

    private static let javaKeywords = [
        "abstract", "boolean", "break", "byte", "case", "catch", "class", "continue", "default", "do", "double",
        "else", "extends", "final", "finally", "float", "for", "if", "implements", "import", "instanceof", "int",
        "interface", "long", "new", "package", "private", "protected", "public", "return", "static", "strictfp",
        "super", "switch", "synchronized", "this", "throw", "throws", "transient", "try", "void", "volatile", "while"
    ]

    private static let sqlKeywords = [
        "SELECT", "FROM", "WHERE", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "GROUP", "ORDER", "BY", "LIMIT",
        "INSERT", "INTO", "VALUES", "UPDATE", "DELETE", "CREATE", "TABLE", "ALTER", "DROP", "AND", "OR", "NOT", "NULL"
    ]

    private static func applyJSONHighlights(to attributed: inout AttributedString, text: String) {
        applyQuotedStringHighlights(to: &attributed, text: text, color: Color(red: 0.11, green: 0.64, blue: 0.36))
        applyPattern(to: &attributed, text: text, pattern: #"\b(true|false|null)\b"#, color: Color(red: 0.56, green: 0.34, blue: 0.92), bold: true)
        applyPattern(to: &attributed, text: text, pattern: #"\b-?\d+(\.\d+)?([eE][+-]?\d+)?\b"#, color: Color(red: 0.17, green: 0.48, blue: 0.95), bold: false)
    }

    private static func applyKeywordHighlights(to attributed: inout AttributedString, text: String, keywords: [String], color: Color, bold: Bool) {
        let pattern = #"\b("# + keywords.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + #")\b"#
        applyPattern(to: &attributed, text: text, pattern: pattern, color: color, bold: bold, options: [.caseInsensitive])
    }

    private static func applyQuotedStringHighlights(to attributed: inout AttributedString, text: String, color: Color) {
        applyPattern(to: &attributed, text: text, pattern: #""([^"\\]|\\.)*""#, color: color, bold: false)
        applyPattern(to: &attributed, text: text, pattern: #"'([^'\\]|\\.)*'"#, color: color, bold: false)
    }

    private static func applyCommentHighlights(to attributed: inout AttributedString, text: String, prefix: String, color: Color) {
        guard let index = text.range(of: prefix) else { return }
        let end = text.endIndex
        applyRange(to: &attributed, text: text, start: index.lowerBound, end: end, color: color, bold: false)
    }

    private static func applyCommandHighlights(to attributed: inout AttributedString, text: String) {
        guard let regex = try? NSRegularExpression(pattern: #"\b(brew|git|npm|pnpm|yarn|make|curl|chmod|python3?|node|swift)\b"#, options: [.caseInsensitive]) else { return }
        apply(regex: regex, to: &attributed, text: text, color: Color(red: 0.17, green: 0.48, blue: 0.95), bold: true)
    }

    private static func applyPattern(to attributed: inout AttributedString, text: String, pattern: String, color: Color, bold: Bool, options: NSRegularExpression.Options = []) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        apply(regex: regex, to: &attributed, text: text, color: color, bold: bold)
    }

    private static func apply(regex: NSRegularExpression, to attributed: inout AttributedString, text: String, color: Color, bold: Bool) {
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range).reversed() {
            guard let swiftRange = Range(match.range, in: text) else { continue }
            applyRange(to: &attributed, text: text, start: swiftRange.lowerBound, end: swiftRange.upperBound, color: color, bold: bold)
        }
    }

    private static func applyRange(to attributed: inout AttributedString, text: String, start: String.Index, end: String.Index, color: Color, bold: Bool) {
        let lowerOffset = text.distance(from: text.startIndex, to: start)
        let upperOffset = text.distance(from: text.startIndex, to: end)

        let lower = attributed.index(attributed.startIndex, offsetByCharacters: lowerOffset)
        let upper = attributed.index(attributed.startIndex, offsetByCharacters: upperOffset)
        let attributedRange = lower..<upper
        attributed[attributedRange].foregroundColor = color
        if bold {
            attributed[attributedRange].font = .system(size: 13, weight: .semibold, design: .monospaced)
        }
    }
}
