//
//  LegacyDashboardComponents.swift
//  ClipDock
//

import SwiftUI
import AppKit

struct ClipboardCodePane: View {
    @Environment(\.appLocalizer) private var localizer
    let record: ClipboardRecord
    private let scrollAnchorID = "clipboard.code.pane.scroll.top"

    var body: some View {
        let lines = ClipboardCodeLineCache.shared.lines(for: record)
        let language = record.codeLanguage

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 8) {
                    Text(language.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(language.badgeColor)
                    Text("\(lines.count) lines")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(language.badgeColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer(minLength: 0)

                Button {
                    ClipboardCodeActions.copy(ClipboardCodeActions.markdownCodeBlock(record.detailText, language: language))
                } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .help(localizer.text(.copyMarkdown))

                if language == .json {
                    Button(localizer.text(.prettyJSON)) {
                        if let pretty = ClipboardCodeActions.prettyJSON(record.detailText) {
                            ClipboardCodeActions.copy(pretty)
                        }
                    }
                    .buttonStyle(.bordered)

                    Button(localizer.text(.minifyJSON)) {
                        if let minified = ClipboardCodeActions.minifyJSON(record.detailText) {
                            ClipboardCodeActions.copy(minified)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        Color.clear
                            .frame(width: 0, height: 0)
                            .id(scrollAnchorID)

                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary.opacity(0.75))
                                    .frame(width: 34, alignment: .trailing)

                                Text(ClipboardCodeHighlighter.attributedLine(line, language: language))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .id(record.objectID)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onAppear {
                    scrollToTop(proxy)
                }
                .onChange(of: record.objectID) { _ in
                    scrollToTop(proxy)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.gray.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func scrollToTop(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo(scrollAnchorID, anchor: .topLeading)
        }
    }
}

struct ActionRow: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                Text(title)
                Spacer()
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct ClipboardPreviewCard: View {
    @Environment(\.appLocalizer) private var localizer
    let record: ClipboardRecord
    let isSelected: Bool
    let layout: DashboardLayout
    let onTap: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    let onManageCategories: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: layout.cardSpacingInner) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        if record.kind == .code {
                            Image(systemName: record.kind.symbolName)
                                .font(.system(size: layout.iconSizeSmall, weight: .semibold))
                                .foregroundStyle(record.kind.accent)
                        } else if let icon = record.sourceAppIcon, record.kind == .link {
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: layout.iconSizeSmall, height: layout.iconSizeSmall)
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        } else {
                            Image(systemName: record.kind.symbolName)
                                .font(.system(size: layout.iconSizeSmall, weight: .semibold))
                        }
                        Text(record.kind.title)
                    }
                    .font(.system(size: layout.footerFontSize - 1, weight: .semibold))
                    .foregroundStyle(record.kind.accent)

                    Spacer()

                    Text(record.timeLabelShort)
                        .font(.system(size: layout.footerFontSize - 1))
                        .foregroundStyle(.secondary)

                    Image(systemName: "ellipsis")
                        .font(.system(size: layout.iconSizeSmall, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.8))
                }

                if record.kind == .image, let preview = record.previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(height: layout.cardImageHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: layout.mediumCornerRadius, style: .continuous))
                } else if record.kind == .colors, let color = record.clipboardColorValue {
                    RoundedRectangle(cornerRadius: layout.mediumCornerRadius, style: .continuous)
                        .fill(color.color)
                        .frame(height: layout.cardImageHeight)
                } else if record.kind == .code {
                    RoundedRectangle(cornerRadius: layout.mediumCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .overlay(
                            Image(systemName: "curlybraces")
                                .font(.system(size: layout.cardTitleSize + 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        )
                        .frame(height: layout.cardImageHeight)
                } else {
                    Text(record.previewTitle)
                        .font(.system(size: layout.cardTitleSize, weight: .semibold))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.primary)
                }

                if !record.customCategories.isEmpty {
                    ClipboardCategoryBadgeStrip(categories: record.customCategories)
                }

                HStack(spacing: 6) {
                    if let icon = record.sourceAppIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(record.sourceAppDisplayName)
                        .font(.system(size: layout.footerFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Text(record.kind.title)
                        .font(.system(size: layout.footerFontSize - 1, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(record.kind.accent.opacity(0.14))
                        .foregroundStyle(record.kind.accent)
                        .clipShape(Capsule())

                    Spacer()

                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(CardIconButtonStyle(layout: layout))

                    Button(action: onTogglePin) {
                        Image(systemName: record.isPinned ? "pin.fill" : "pin")
                    }
                    .buttonStyle(CardIconButtonStyle(layout: layout))
                }
            }
            .padding(layout.cardPadding)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                    .fill(cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                            .stroke(isSelected ? record.kind.accent.opacity(0.90) : Color.white.opacity(0.24), lineWidth: isSelected ? 1.6 : 1)
                    )
                    .shadow(color: isSelected ? record.kind.accent.opacity(0.16) : .black.opacity(0.06), radius: layout.cardShadowRadius, x: 0, y: 5)
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            onTap()
            onCopy()
        })
        .contextMenu {
            Button {
                onCopy()
            } label: {
                Label(localizer.text(.copy), systemImage: "doc.on.doc")
            }

            Button {
                onTogglePin()
            } label: {
                Label(record.isPinned ? "Unpin" : "Pin", systemImage: record.isPinned ? "pin.slash" : "pin")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(localizer.text(.delete), systemImage: "trash")
            }

            Divider()

            ClipboardCategoryRecordMenu(record: record, onManageCategories: onManageCategories)
        }
    }

    private var cardBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(0.94),
                record.kind.accent.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct FilterChip: View {
    let title: String
    let symbolName: String
    let accentColor: Color
    let isSelected: Bool
    let layout: DashboardLayout

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.system(size: layout.filterIconSize, weight: .semibold))
            Text(title)
        }
        .font(.system(size: layout.footerFontSize, weight: .medium))
        .foregroundStyle(isSelected ? .white : accentColor)
        .padding(.horizontal, layout.chipHorizontalPadding)
        .padding(.vertical, layout.chipVerticalPadding)
        .background(isSelected ? AnyShapeStyle(accentColor) : AnyShapeStyle(Color.white.opacity(0.78)))
        .clipShape(RoundedRectangle(cornerRadius: layout.chipCornerRadius, style: .continuous))
        .overlay(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: layout.chipCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                }
            }
        )
    }
}

struct DashboardLayout {
    let containerSize: CGSize

    private let baseSize = CGSize(width: 1286, height: 856)

    private var scale: CGFloat {
        let baseScale = min(containerSize.width / baseSize.width, containerSize.height / baseSize.height)
        return pow(baseScale, 0.55)
    }

    private func s(_ value: CGFloat) -> CGFloat { value * scale }

    var outerPadding: CGFloat { s(20) }
    var verticalSpacing: CGFloat { s(14) }
    var toolbarSpacing: CGFloat { s(12) }
    var toolbarButtonSize: CGFloat { s(36) }
    var toolbarIconSize: CGFloat { s(12) }
    var toolbarDotsSize: CGFloat { s(16) }
    var searchBarHeight: CGFloat { s(38) }
    var searchBarMaxWidth: CGFloat { s(430) }
    var searchHorizontalPadding: CGFloat { s(14) }
    var searchCornerRadius: CGFloat { s(19) }
    var searchIconSize: CGFloat { s(15) }
    var searchTextSize: CGFloat { s(14) }
    var searchHintSize: CGFloat { s(12) }
    var toolbarPillHeight: CGFloat { s(32) }
    var toolbarPillTextSize: CGFloat { s(13) }
    var panelPadding: CGFloat { s(16) }
    var mainSectionSpacing: CGFloat { s(14) }
    var cardPanelSpacing: CGFloat { s(12) }
    var cardPanelPadding: CGFloat { s(14) }
    var cardPanelCornerRadius: CGFloat { s(18) }
    var sectionTitleSize: CGFloat { s(15) }
    var categorySpacing: CGFloat { s(8) }
    var panelCornerRadius: CGFloat { s(18) }
    var detailCornerRadius: CGFloat { s(22) }
    var smallCornerRadius: CGFloat { s(12) }
    var mediumCornerRadius: CGFloat { s(14) }
    var cardCornerRadius: CGFloat { s(22) }
    var cardSpacing: CGFloat { s(14) }
    var cardSpacingInner: CGFloat { s(12) }
    var cardPadding: CGFloat { s(14) }
    var detailPadding: CGFloat { s(14) }
    var detailSpacing: CGFloat { s(14) }
    var detailSidePadding: CGFloat { s(12) }
    var chipHorizontalPadding: CGFloat { s(11.5) }
    var chipVerticalPadding: CGFloat { s(6.5) }
    var chipCornerRadius: CGFloat { s(9.5) }
    var footerSpacing: CGFloat { s(12) }
    var titleSize: CGFloat { s(19) }
    var subtitleSize: CGFloat { s(13) }
    var bodySize: CGFloat { s(14) }
    var footerFontSize: CGFloat { s(13) }
    var cardTitleSize: CGFloat { s(17) }
    var detailTitleSize: CGFloat { s(17) }
    var detailBodyTitleSize: CGFloat { s(16) }
    var filterIconSize: CGFloat { s(11) }
    var iconSizeSmall: CGFloat { s(12) }
    var iconSizeMedium: CGFloat { s(18) }
    var iconSizeLarge: CGFloat { s(22) }
    var actionButtonSize: CGFloat { s(34) }
    var statusDotSize: CGFloat { s(9) }
    var cardImageHeight: CGFloat { s(104) }
    var detailBadgeSize: CGFloat { s(44) }
    var codePaneMinHeight: CGFloat { s(124) }
    var heroMinHeight: CGFloat { s(310) }
    var heroPreviewMinHeight: CGFloat { s(280) }
    var heroTitleSize: CGFloat { s(27) }
    var heroSubtitleSize: CGFloat { s(15) }
    var heroBodySize: CGFloat { s(14) }
    var cardMinWidth: CGFloat { s(200) }
    var cardMaxWidth: CGFloat { s(236) }
    var cardHeight: CGFloat { s(336) }
    var cardShadowRadius: CGFloat { s(8) }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    let layout: DashboardLayout

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: layout.footerFontSize, weight: .semibold))
            .padding(.horizontal, max(12, layout.chipHorizontalPadding))
            .padding(.vertical, max(6, layout.chipVerticalPadding))
            .foregroundStyle(.white)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.76 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct DetailActionButtonStyle: ButtonStyle {
    let layout: DashboardLayout

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: layout.footerFontSize, weight: .semibold))
            .padding(.horizontal, max(12, layout.chipHorizontalPadding))
            .padding(.vertical, max(6, layout.chipVerticalPadding))
            .background(Color.white.opacity(configuration.isPressed ? 0.68 : 0.88))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct FooterButtonStyle: ButtonStyle {
    let layout: DashboardLayout

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: layout.footerFontSize, weight: .semibold))
            .padding(.horizontal, max(12, layout.chipHorizontalPadding))
            .padding(.vertical, max(6, layout.chipVerticalPadding))
            .background(Color.white.opacity(configuration.isPressed ? 0.58 : 0.82))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct CardIconButtonStyle: ButtonStyle {
    let layout: DashboardLayout

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: layout.iconSizeSmall, weight: .semibold))
            .frame(width: layout.actionButtonSize, height: layout.actionButtonSize)
            .background(Color.white.opacity(configuration.isPressed ? 0.55 : 0.90))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct IconButtonStyle: ButtonStyle {
    let layout: DashboardLayout

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(Color.white.opacity(configuration.isPressed ? 0.55 : 0.84))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CircleToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(Color.white.opacity(configuration.isPressed ? 0.60 : 0.84))
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.24), lineWidth: 1))
    }
}

private struct PillToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .foregroundStyle(.primary)
            .background(Color.white.opacity(configuration.isPressed ? 0.62 : 0.80))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}

private struct DotsToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.secondary)
            .background(Color.white.opacity(configuration.isPressed ? 0.58 : 0.72))
            .clipShape(Circle())
    }
}
