import CoreData
import Foundation

enum ClipboardContentKind: String {
    case text
    case link
    case image
    case code
    case files
    case colors
    case unknown
}

@main
struct VerifySearchSyntax {
    @inline(__always)
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        let query = ClipboardSearchQuery(
            #"crash report type:code app:"Google Chrome" host:github.com lang:swift pinned:true"#
        )
        expect(query.text == "crash report", "plain text remains searchable")
        expect(query.filters == [
            .contentType("code"),
            .sourceApp("Google Chrome"),
            .host("github.com"),
            .language("swift"),
            .pinned(true)
        ], "all lightweight filters parse in order")

        let matching: NSDictionary = [
            "displayText": "Crash report from build",
            "fullText": "fatal error details",
            "sourceAppName": "Google Chrome",
            "sourceBundleId": "com.google.Chrome",
            "contentTypeRaw": "code",
            "linkHost": "gist.github.com",
            "codeLanguageRaw": "swift",
            "isPinned": true
        ]
        expect(query.predicate?.evaluate(with: matching) == true, "combined predicate matches record")

        let unpinned = matching.mutableCopy() as! NSMutableDictionary
        unpinned["isPinned"] = false
        expect(query.predicate?.evaluate(with: unpinned) == false, "pinned filter rejects record")

        let aliases = ClipboardSearchQuery("TYPE:file pinned:0")
        expect(aliases.filters == [.contentType("files"), .pinned(false)], "aliases and case-insensitive keys parse")
        expect(ClipboardSearchQuery("type:image").filters == [.contentType("image")], "image type parses")

        let invalid = ClipboardSearchQuery("type:video pinned:maybe owner:max")
        expect(invalid.filters.isEmpty, "unsupported filters do not become predicates")
        expect(invalid.text == "type:video pinned:maybe owner:max", "unsupported filters fall back to text")

        let quotedText = ClipboardSearchQuery(#""exact phrase" app:Safari"#)
        expect(quotedText.text == "exact phrase", "quoted text remains one phrase")
        expect(quotedText.filters == [.sourceApp("Safari")], "quoted text composes with filters")

        print("Advanced search syntax checks passed.")
    }
}
