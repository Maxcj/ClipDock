import Foundation
import SwiftUI
import AppKit

final class ClipboardRecord {
    var fullText: String?
    var displayText: String?

    init(fullText: String?, displayText: String? = nil) {
        self.fullText = fullText
        self.displayText = displayText
    }
}

final class ClipboardCodeLineCache {
    static let shared = ClipboardCodeLineCache()
    func lines(for record: ClipboardRecord) -> [String] {
        let text = (record.fullText ?? record.displayText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        return lines.isEmpty ? [text] : lines
    }
}

@main
struct VerifyCodeSnippets {
    @inline(__always)
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        let swiftSnippet = """
        import SwiftUI
        struct ContentView: View { }
        """
        expect(ClipboardCodeLanguageDetector.detect(from: swiftSnippet) == .swift, "swift detect")

        let jsonSnippet = #"{"name":"ClipDock","enabled":true}"#
        expect(ClipboardCodeLanguageDetector.detect(from: jsonSnippet) == .json, "json detect")

        let sqlSnippet = "SELECT * FROM users WHERE id = 1"
        expect(ClipboardCodeLanguageDetector.detect(from: sqlSnippet) == .sql, "sql detect")

        let markdown = ClipboardCodeActions.markdownCodeBlock("let a = 1", language: .swift)
        expect(markdown.contains("```swift"), "markdown language fence")

        let record = ClipboardRecord(fullText: "line1\nline2\nline3")
        let lines = ClipboardCodeLineCache.shared.lines(for: record)
        expect(lines.count == 3, "line count")

        print("Code snippet checks passed.")
    }
}
