//
//  ClipboardDetailViews.swift
//  ClipDock
//

import SwiftUI
import AppKit

struct ClipboardDetailInspector: View {
    @Environment(\.appLocalizer) private var localizer
    @EnvironmentObject private var clipboardMonitor: ClipboardMonitor
    let record: ClipboardRecord?
    let layout: SimpleClipboardLayout
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onExcludeSourceApp: () -> Void
    let onManageCategories: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: layout.detailSpacing) {
            if let record {
                header(for: record)
                preview(for: record)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()
                    .overlay(Color.black.opacity(0.06))

                metadata(for: record)

                if !record.customCategories.isEmpty {
                    ClipboardCategoryBadgeStrip(categories: record.customCategories)
                }

                HStack(spacing: layout.detailButtonGap) {
                    detailButton(title: localizer.text(.pin), icon: record.isPinned ? "pin.fill" : "pin", action: onTogglePin)
                    if record.sourceBundleId?.isEmpty == false {
                        detailButton(title: localizer.text(.excludeApp), icon: "hand.raised", action: onExcludeSourceApp)
                    }
                    detailButton(title: localizer.text(.delete), icon: "trash", action: onDelete, isDestructive: true)
                }
                .padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(localizer.text(.noSelection))
                        .font(.system(size: layout.detailTitleSize, weight: .semibold))
                    Text(localizer.text(.chooseClipboardItem))
                        .font(.system(size: layout.detailSubtitleSize))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, layout.detailPaddingX)
        .padding(.vertical, layout.detailPaddingY)
    }

    private func header(for record: ClipboardRecord) -> some View {
        HStack(alignment: .center, spacing: 12) {
            sourceAppIcon(for: record, size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.sourceAppDisplayName)
                    .font(.system(size: layout.detailLabelSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(record.kind.title)
                    .font(.system(size: layout.footerFontSize))
                    .foregroundStyle(record.kind.accent)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func sourceAppIcon(for record: ClipboardRecord, size: CGFloat) -> some View {
        if let icon = record.sourceAppIcon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(record.kind.accent.opacity(0.12))
                .overlay(
                    Image(systemName: record.kind == .link ? "globe" : "app.dashed")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(record.kind.accent)
                )
                .frame(width: size, height: size)
        }
    }

    private func preview(for record: ClipboardRecord) -> some View {
        switch record.kind {
        case .image:
            return AnyView(
                AsyncDetailImageView(
                    imagePath: record.imagePath,
                    initialImage: record.previewImage,
                    placeholderTitle: record.previewTitle,
                    maxPixelSize: layout.heroImageHeight * 2,
                    cornerRadius: 18,
                    fallbackHeight: 240
                )
            )
        case .link:
            return AnyView(
                VStack(alignment: .leading, spacing: 14) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .overlay(
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .center, spacing: 10) {
                                    if let icon = record.websiteIconImage {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .interpolation(.high)
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 22, height: 22)
                                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    } else if let icon = record.sourceAppIcon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .interpolation(.high)
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 22, height: 22)
                                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    } else {
                                        Image(systemName: "globe")
                                            .font(.system(size: 19, weight: .semibold))
                                            .foregroundStyle(record.kind.accent)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(record.previewSubtitle)
                                            .font(.system(size: 16, weight: .semibold))
                                            .lineLimit(1)
                                        if let host = record.linkHostLabel {
                                            Text(host)
                                                .font(.system(size: 13))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()
                                }

                                Text(record.previewTitle)
                                    .font(.system(size: 26, weight: .semibold))
                                    .lineLimit(4)

                                Text(record.detailText)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        )
                        .frame(height: 220)
                }
                .textSelection(.enabled)
            )
        case .files:
            return AnyView(
                FileDetailPreview(
                    record: record,
                    subtitleFontSize: layout.detailSubtitleSize,
                    footerFontSize: layout.footerFontSize,
                    iconSize: 112,
                    height: 240
                )
            )
        case .code:
            return AnyView(
                ClipboardCodePane(record: record)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            )
        case .colors:
            return AnyView(
                ClipboardColorDetailView(
                    record: record,
                    layout: layout,
                    onCopyHex: { copyColorValue(record.clipboardColorValue?.normalizedHexString ?? record.fullText ?? record.displayText ?? "") },
                    onCopyRGB: { copyColorValue(record.clipboardColorValue?.rgbString ?? "") },
                    onCopyRGBA: { copyColorValue(record.clipboardColorValue?.rgbaString ?? "") }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            )
        case .text, .unknown:
            return AnyView(
                ScrollView(.vertical, showsIndicators: false) {
                    Text(record.detailText)
                        .font(.system(size: layout.previewTextSize, weight: .semibold))
                        .monospaced()
                        .foregroundStyle(.primary)
                        .lineSpacing(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            )
        }
    }

    private func copyColorValue(_ value: String) {
        guard !value.isEmpty else { return }
        clipboardMonitor.copyTextSilently(value)
    }

    private func imagePreview(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(height: layout.heroImageHeight)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.16))
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
    }

    private func metadata(for record: ClipboardRecord) -> some View {
        let rows = metadataRows(for: record)

        return VStack(spacing: 14) {
            ForEach(rows.indices, id: \.self) { index in
                ClipboardDetailMetaRow(title: rows[index].title, value: rows[index].value, layout: layout)
            }
        }
        .padding(.top, 2)
    }

    private func metadataRows(for record: ClipboardRecord) -> [(title: String, value: String)] {
        var rows: [(title: String, value: String)] = [
            (localizer.text(.copied), record.timeLabelPrecise)
        ]

        if let sourceAppName = record.sourceAppName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceAppName.isEmpty {
            rows.append((localizer.text(.sourceApp), sourceAppName))
        }

        switch record.kind {
        case .image:
            rows.append((localizer.text(.imageFormat), record.imageFormatLabel))
            rows.append((localizer.text(.resolution), record.imageResolutionLabel))
            rows.append((localizer.text(.imageSize), record.imageFileSizeLabel))
            rows.append((localizer.text(.path), record.imagePathText))
        case .code:
            rows.append((localizer.text(.language), record.codeLanguage.title))
            rows.append((localizer.text(.lines), "\(record.codeLineCount)"))
        case .files:
            rows.append((localizer.text(.path), record.fileSubtitleText))
            rows.append((localizer.text(.fileSize), record.fileSizeLabel))
        default:
            rows.append((localizer.text(.characters), "\(record.characterCount)"))
        }

        return rows
    }

    private func detailButton(title: String, icon: String, action: @escaping () -> Void, isDestructive: Bool = false) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.system(size: layout.detailButtonSize, weight: .medium))
            .foregroundStyle(isDestructive ? Color.red : .primary)
            .frame(maxWidth: .infinity)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .allowsTightening(true)
            .frame(height: layout.detailActionHeight)
            .background(Color.white.opacity(0.20))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ClipboardDetailMetaRow: View {
    let title: String
    let value: String
    let layout: SimpleClipboardLayout

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: layout.detailLabelSize))
                .foregroundStyle(.secondary)
                .frame(width: layout.detailLabelColumnWidth, alignment: .leading)

            Spacer()

            Text(value)
                .font(.system(size: layout.detailValueSize, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

struct SimpleFilterChip: View {
    let title: String
    let symbolName: String
    let accentColor: Color
    let isSelected: Bool
    let layout: SimpleClipboardLayout

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.system(size: layout.chipIconSize, weight: .semibold))
            Text(title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.system(size: layout.chipTextSize, weight: isSelected ? .semibold : .medium))
        .foregroundStyle(accentColor)
        .padding(.horizontal, layout.chipPaddingX)
        .padding(.vertical, layout.chipVerticalPadding)
        .fixedSize(horizontal: true, vertical: false)
        .background(isSelected ? AnyShapeStyle(accentColor.opacity(0.10)) : AnyShapeStyle(Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: layout.chipCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: layout.chipCornerRadius, style: .continuous))
        .overlay(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: layout.chipCornerRadius, style: .continuous)
                        .stroke(accentColor.opacity(0.26), lineWidth: 1)
                }
            }
        )
        .shadow(color: isSelected ? Color.black.opacity(0.03) : .clear, radius: 2, x: 0, y: 1)
    }
}
