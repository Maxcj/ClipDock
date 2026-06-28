//
//  ClipboardColorModels.swift
//  ClipDock
//

import SwiftUI
import Foundation

enum ClipboardColorFormat: String, CaseIterable, Identifiable, Codable {
    case hex
    case rgb
    case rgba
    case hsl
    case hsla

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hex: return "HEX"
        case .rgb: return "RGB"
        case .rgba: return "RGBA"
        case .hsl: return "HSL"
        case .hsla: return "HSLA"
        }
    }
}

struct ClipboardColorValue: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    let sourceText: String
    let sourceFormat: ClipboardColorFormat

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var hexString: String {
        let r = Self.channelValue(red)
        let g = Self.channelValue(green)
        let b = Self.channelValue(blue)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var hexStringIncludingAlpha: String {
        let r = Self.channelValue(red)
        let g = Self.channelValue(green)
        let b = Self.channelValue(blue)
        let a = Self.channelValue(alpha)
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }

    var normalizedHexString: String {
        alpha >= 0.999 ? hexString : hexStringIncludingAlpha
    }

    var rgbString: String {
        let r = Self.channelValue(red)
        let g = Self.channelValue(green)
        let b = Self.channelValue(blue)
        return "rgb(\(r), \(g), \(b))"
    }

    var rgbaString: String {
        let r = Self.channelValue(red)
        let g = Self.channelValue(green)
        let b = Self.channelValue(blue)
        return "rgba(\(r), \(g), \(b), \(Self.alphaString(alpha)))"
    }

    var swiftUIColorString: String {
        "Color(red: \(Self.doubleString(red)), green: \(Self.doubleString(green)), blue: \(Self.doubleString(blue)), opacity: \(Self.doubleString(alpha)))"
    }

    var cssString: String {
        "color: \(normalizedHexString);"
    }

    var summaryText: String {
        sourceFormat.title
    }

    var displayText: String {
        normalizedHexString
    }

    private static func channelValue(_ value: Double) -> Int {
        Int((value * 255).rounded())
    }

    private static func alphaString(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func doubleString(_ value: Double) -> String {
        if value == floor(value) {
            return String(format: "%.1f", value)
        }
        let formatted = String(format: "%.4f", value)
        return formatted.replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}

enum ClipboardColorDetector {
    static func detect(from text: String) -> ClipboardColorValue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return nil }
        guard !trimmed.contains("\n"), !trimmed.contains("\t") else { return nil }

        if let color = parseHex(trimmed) {
            return color
        }

        if let color = parseRGB(trimmed) {
            return color
        }

        if let color = parseHSL(trimmed) {
            return color
        }

        return nil
    }

    private static func parseHex(_ text: String) -> ClipboardColorValue? {
        let hasLeadingHash = text.hasPrefix("#")
        if !hasLeadingHash, text.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil {
            return nil
        }

        let pattern = #"^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let hex = String(text[valueRange])
        let chars = Array(hex)

        func expand(_ value: Character) -> String {
            "\(value)\(value)"
        }

        let r: Int
        let g: Int
        let b: Int
        let a: Int

        switch chars.count {
        case 3:
            r = Int(expand(chars[0]), radix: 16) ?? 0
            g = Int(expand(chars[1]), radix: 16) ?? 0
            b = Int(expand(chars[2]), radix: 16) ?? 0
            a = 255
        case 4:
            r = Int(expand(chars[0]), radix: 16) ?? 0
            g = Int(expand(chars[1]), radix: 16) ?? 0
            b = Int(expand(chars[2]), radix: 16) ?? 0
            a = Int(expand(chars[3]), radix: 16) ?? 255
        case 6:
            r = Int(String(chars[0...1]), radix: 16) ?? 0
            g = Int(String(chars[2...3]), radix: 16) ?? 0
            b = Int(String(chars[4...5]), radix: 16) ?? 0
            a = 255
        case 8:
            r = Int(String(chars[0...1]), radix: 16) ?? 0
            g = Int(String(chars[2...3]), radix: 16) ?? 0
            b = Int(String(chars[4...5]), radix: 16) ?? 0
            a = Int(String(chars[6...7]), radix: 16) ?? 255
        default:
            return nil
        }

        return ClipboardColorValue(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255,
            sourceText: text,
            sourceFormat: .hex
        )
    }

    private static func parseRGB(_ text: String) -> ClipboardColorValue? {
        let pattern = #"^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})(?:\s*,\s*([01](?:\.\d+)?))?\s*\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }

        func intValue(_ index: Int) -> Int? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return Int(text[range])
        }

        guard let r = intValue(1),
              let g = intValue(2),
              let b = intValue(3),
              (0...255).contains(r),
              (0...255).contains(g),
              (0...255).contains(b) else {
            return nil
        }

        var alpha = 1.0
        if match.range(at: 4).location != NSNotFound,
           let range = Range(match.range(at: 4), in: text),
           let parsedAlpha = Double(text[range]) {
            alpha = min(max(parsedAlpha, 0), 1)
        }

        return ClipboardColorValue(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: alpha,
            sourceText: text,
            sourceFormat: text.lowercased().hasPrefix("rgba") ? .rgba : .rgb
        )
    }

    private static func parseHSL(_ text: String) -> ClipboardColorValue? {
        let pattern = #"^hsla?\(\s*(\d{1,3}(?:\.\d+)?)\s*,\s*(\d{1,3}(?:\.\d+)?)%\s*,\s*(\d{1,3}(?:\.\d+)?)%(?:\s*,\s*([01](?:\.\d+)?))?\s*\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }

        func doubleValue(_ index: Int) -> Double? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return Double(text[range])
        }

        guard let hue = doubleValue(1),
              let saturation = doubleValue(2),
              let lightness = doubleValue(3),
              (0...360).contains(hue),
              (0...100).contains(saturation),
              (0...100).contains(lightness) else {
            return nil
        }

        var alpha = 1.0
        if match.range(at: 4).location != NSNotFound,
           let range = Range(match.range(at: 4), in: text),
           let parsedAlpha = Double(text[range]) {
            alpha = min(max(parsedAlpha, 0), 1)
        }

        let (red, green, blue) = rgbFromHSL(hue: hue, saturation: saturation / 100, lightness: lightness / 100)
        return ClipboardColorValue(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha,
            sourceText: text,
            sourceFormat: text.lowercased().hasPrefix("hsla") ? .hsla : .hsl
        )
    }

    private static func rgbFromHSL(hue: Double, saturation: Double, lightness: Double) -> (Double, Double, Double) {
        let normalizedHue = hue.truncatingRemainder(dividingBy: 360) / 360

        if saturation == 0 {
            return (lightness, lightness, lightness)
        }

        func hueToRGB(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var value = t
            if value < 0 { value += 1 }
            if value > 1 { value -= 1 }
            if value < 1.0 / 6.0 { return p + (q - p) * 6 * value }
            if value < 1.0 / 2.0 { return q }
            if value < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - value) * 6 }
            return p
        }

        let q = lightness < 0.5
            ? lightness * (1 + saturation)
            : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q

        let red = hueToRGB(p, q, normalizedHue + 1.0 / 3.0)
        let green = hueToRGB(p, q, normalizedHue)
        let blue = hueToRGB(p, q, normalizedHue - 1.0 / 3.0)
        return (red, green, blue)
    }
}
