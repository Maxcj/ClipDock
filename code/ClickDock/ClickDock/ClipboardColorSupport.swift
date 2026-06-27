//
//  ClipboardColorSupport.swift
//  ClipDock
//

import SwiftUI
import AppKit

extension ClipboardRecord {
    var clipboardColorValue: ClipboardColorValue? {
        guard kind == .colors else { return nil }
        return ClipboardColorDetector.detect(from: fullText ?? displayText ?? "")
    }

    var colorFormatLabel: String {
        clipboardColorValue?.summaryText ?? AppLocalizer.current.text(.colors)
    }

    var colorDisplayText: String {
        clipboardColorValue?.sourceText ?? previewTitle
    }

    var colorDetailValue: String {
        clipboardColorValue?.sourceText ?? detailText
    }
}

struct ClipboardColorDetailView: View {
    @Environment(\.appLocalizer) private var localizer
    let record: ClipboardRecord
    let layout: SimpleClipboardLayout
    let onCopyHex: () -> Void
    let onCopyRGB: () -> Void
    let onCopyRGBA: () -> Void

    var body: some View {
        let color = record.clipboardColorValue

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if let color {
                    colorPreview(color)
                    colorValues(color)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(record.previewTitle)
                            .font(.system(size: 28, weight: .semibold))
                        Text(record.detailText)
                            .font(.system(size: layout.detailSubtitleSize))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.trailing, 2)
        }
    }

    private func colorPreview(_ color: ClipboardColorValue) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(color.color)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                )
                .frame(height: 180)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(color.normalizedHexString)
                            .font(.system(size: 30, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 2)
                        HStack(spacing: 8) {
                            infoPill(text: color.sourceFormat.title)
                            infoPill(text: opacityLabel(for: color))
                        }
                    }
                    .padding(18)
                }

            HStack(spacing: 10) {
                Text(record.colorDetailValue)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
            }

            HStack(spacing: 8) {
                infoTag(title: localizer.text(.source), value: color.sourceText)
                infoTag(title: localizer.text(.format), value: color.sourceFormat.title)
                infoTag(title: localizer.text(.opacity), value: opacityLabel(for: color))
            }
        }
    }

    private func colorValues(_ color: ClipboardColorValue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            colorValueRow(title: "HEX", value: color.normalizedHexString, action: onCopyHex)
            colorValueRow(title: "RGB", value: color.rgbString, action: onCopyRGB)
            colorValueRow(title: "RGBA", value: color.rgbaString, action: onCopyRGBA)
        }
    }

    private func colorValueRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: layout.footerFontSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .leading)
                Text(value)
                    .font(.system(size: layout.detailSubtitleSize, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.20))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func infoPill(text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.18))
            .clipShape(Capsule())
    }

    private func infoTag(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func opacityLabel(for color: ClipboardColorValue) -> String {
        color.alpha >= 0.999 ? "Opaque" : String(format: "%.0f%%", color.alpha * 100)
    }
}
