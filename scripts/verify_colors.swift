import Foundation

@main
struct VerifyColors {
    @inline(__always)
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func approx(_ lhs: Double, _ rhs: Double, epsilon: Double = 0.0001) -> Bool {
        abs(lhs - rhs) <= epsilon
    }

    static func main() {
        let hex = ClipboardColorDetector.detect(from: "#FF5733")
        expect(hex?.normalizedHexString == "#FF5733", "hex normalization")
        expect(hex?.sourceFormat == .hex, "hex format")

        let shortHex = ClipboardColorDetector.detect(from: "#fff")
        expect(shortHex?.normalizedHexString == "#FFFFFF", "short hex expansion")

        let rgba = ClipboardColorDetector.detect(from: "rgba(255, 87, 51, 0.5)")
        expect(rgba?.normalizedHexString == "#FF573380", "rgba alpha hex")
        expect(rgba?.sourceFormat == .rgba, "rgba format")
        expect(approx(rgba?.alpha ?? 0, 0.5), "rgba alpha value")

        let rgb = ClipboardColorDetector.detect(from: "rgb(255, 87, 51)")
        expect(rgb?.hexString == "#FF5733", "rgb hex value")
        expect(rgb?.sourceFormat == .rgb, "rgb format")

        let hsl = ClipboardColorDetector.detect(from: "hsl(12, 100%, 60%)")
        expect(hsl != nil, "hsl detection")
        expect(approx(hsl?.red ?? 0, 1.0), "hsl red")

        expect(ClipboardColorDetector.detect(from: "https://example.com/#fff") == nil, "url should not be color")
        expect(ClipboardColorDetector.detect(from: "body { color: #fff; }") == nil, "css snippet should not be color")

        print("Color detection checks passed.")
    }
}
