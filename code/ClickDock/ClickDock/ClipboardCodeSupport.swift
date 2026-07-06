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

    var highlighterLanguageIdentifier: String? {
        switch self {
        case .plain:
            return nil
        case .shell:
            return "bash"
        default:
            return rawValue
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

extension ClipboardCodeLanguage {
    static let pickerCases: [ClipboardCodeLanguage] = [
        .plain,
        .swift,
        .json,
        .javascript,
        .typescript,
        .sql,
        .shell,
        .java,
        .python,
        .html,
        .css,
        .xml,
        .yaml
    ]
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
        if isTypeScript(trimmed) { return .typescript }
        if isJavaScript(trimmed) { return .javascript }
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
        let declarationPatterns = [
            #"(?m)^\s*(?:export\s+)?(?:declare\s+)?interface\s+[A-Za-z_$]"#,
            #"(?m)^\s*(?:export\s+)?type\s+[A-Za-z_$][A-Za-z0-9_$]*\s*="#,
            #"(?m)^\s*(?:export\s+)?(?:const\s+)?enum\s+[A-Za-z_$]"#,
            #"(?m)^\s*(?:export\s+)?(?:declare\s+)?namespace\s+[A-Za-z_$]"#
        ]
        if declarationPatterns.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) {
            return true
        }

        let typeSyntaxPatterns = [
            #":\s*(?:string|number|boolean|unknown|any|never|void)(?:\[\])?\b"#,
            #":\s*[A-Z][A-Za-z0-9_$]*(?:<[^>]+>)?(?:\[\])?\b"#,
            #"\bas\s+(?:const|[A-Z][A-Za-z0-9_$]*(?:<[^>]+>)?)\b"#,
            #"\b(?:keyof|satisfies|implements)\s+"#,
            #"\breadonly\s+[A-Za-z_$]"#
        ]
        let hasTypeSyntax = typeSyntaxPatterns.contains {
            text.range(of: $0, options: .regularExpression) != nil
        }
        guard hasTypeSyntax else { return false }

        let codeMarkers = ["const ", "let ", "function ", "=>", "class ", "export ", "import "]
        return codeMarkers.contains(where: text.contains)
    }

    private static func isShell(_ text: String) -> Bool {
        text.hasPrefix("#!") || text.contains("brew install ") || text.contains("npm install ") || text.contains("git ")
    }

    private static func isCSS(_ text: String) -> Bool {
        guard text.contains("{"), text.contains("}") else { return false }

        let selectorPattern = #"(?m)^\s*(?:[.#][A-Za-z_-][A-Za-z0-9_-]*|[a-z][a-z0-9-]*|\*|\[[^\]\n]+\])(?:[.#][A-Za-z_-][A-Za-z0-9_-]*|:[A-Za-z-]+(?:\([^\)\n]*\))?|\[[^\]\n]+\]|\s+(?:[>+~]\s*)?(?:[.#]?[A-Za-z_-][A-Za-z0-9_-]*|[a-z][a-z0-9-]*|\*|\[[^\]\n]+\]))*(?:\s*,\s*(?:[.#]?[A-Za-z_-][A-Za-z0-9_-]*|[a-z][a-z0-9-]*|\*|\[[^\]\n]+\]))*\s*\{"#
        guard text.range(of: selectorPattern, options: .regularExpression) != nil else {
            return false
        }

        let propertyNames = [
            "align-(?:content|items|self)",
            "animation(?:-[a-z-]+)?",
            "appearance",
            "aspect-ratio",
            "background(?:-[a-z-]+)?",
            "border(?:-[a-z-]+)?",
            "bottom",
            "box-shadow",
            "clear",
            "color",
            "column(?:-[a-z-]+)?",
            "content",
            "cursor",
            "display",
            "filter",
            "flex(?:-[a-z-]+)?",
            "float",
            "font(?:-[a-z-]+)?",
            "gap",
            "grid(?:-[a-z-]+)?",
            "height",
            "inset",
            "justify-(?:content|items|self)",
            "left",
            "line-height",
            "margin(?:-[a-z-]+)?",
            "max-(?:height|width)",
            "min-(?:height|width)",
            "object-(?:fit|position)",
            "opacity",
            "outline(?:-[a-z-]+)?",
            "overflow(?:-[xy])?",
            "padding(?:-[a-z-]+)?",
            "pointer-events",
            "position",
            "resize",
            "right",
            "stroke(?:-[a-z-]+)?",
            "table-layout",
            "text-(?:align|decoration|overflow|transform)",
            "top",
            "transform",
            "transition(?:-[a-z-]+)?",
            "user-select",
            "vertical-align",
            "visibility",
            "white-space",
            "width",
            "word-(?:break|spacing|wrap)",
            "z-index"
        ]
        let declarationPattern = #"(?:\{|;)\s*(?:--[A-Za-z0-9_-]+|"#
            + propertyNames.joined(separator: "|")
            + #")\s*:\s*[^;{}]+;"#
        return text.range(of: declarationPattern, options: [.regularExpression, .caseInsensitive]) != nil
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
}

extension ClipboardRecord {
    var codeLanguage: ClipboardCodeLanguage {
        if let persisted = persistedCodeLanguageRaw,
           let language = ClipboardCodeLanguage(rawValue: persisted) {
            return language
        }

        return ClipboardCodeLanguageDetector.detect(from: fullText ?? displayText ?? "")
    }

    var codeLineCount: Int {
        if let persisted = persistedCodeLineCount {
            return persisted
        }

        let text = detailText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        return max(1, lines.isEmpty ? 1 : lines.count)
    }

    var persistedCodeLanguageRaw: String? {
        value(forKey: "codeLanguageRaw") as? String
    }

    var persistedCodeLineCount: Int? {
        if let value = value(forKey: "codeLineCountValue") as? NSNumber {
            return value.intValue
        }
        return nil
    }
}
