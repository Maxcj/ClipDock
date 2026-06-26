//
//  MainWindowSupport.swift
//  ClipDock
//

import SwiftUI
import AppKit

struct WindowChromeOverlay: View {
    let window: NSWindow?
    let layout: SimpleClipboardLayout

    var body: some View {
        HStack(alignment: .center, spacing: layout.chromeButtonSpacing) {
            ChromeButton(color: Color(red: 1.0, green: 0.37, blue: 0.31), symbolName: "xmark", size: layout.chromeButtonSize) {
                window?.orderOut(nil)
            }

            ChromeButton(color: Color(red: 1.0, green: 0.80, blue: 0.20), symbolName: "minus", size: layout.chromeButtonSize) {
                window?.miniaturize(nil)
            }

            ChromeButton(color: Color(red: 0.20, green: 0.78, blue: 0.33), symbolName: "plus", size: layout.chromeButtonSize) {
                window?.zoom(nil)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, layout.chromeOverlayLeading)
        .padding(.top, layout.chromeOverlayTopPadding)
    }
}

struct ChromeButton: View {
    @Environment(\.appLocalizer) private var localizer
    let color: Color
    let symbolName: String
    let size: CGFloat
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color.opacity(isHovered ? 1.0 : 0.92))

                Image(systemName: symbolName)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(isHovered ? Color.black.opacity(0.7) : Color.black.opacity(0.0))
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(symbolName == "xmark" ? localizer.text(.close) : symbolName == "minus" ? localizer.text(.minimize) : localizer.text(.zoom))
    }
}


struct SimpleClipboardLayout {
    let containerSize: CGSize

    private let baseSize = CGSize(width: 1440, height: 1024)

    private var scale: CGFloat {
        let baseScale = min(containerSize.width / baseSize.width, containerSize.height / baseSize.height)
        return pow(baseScale, 0.55)
    }

    private func s(_ value: CGFloat) -> CGFloat { value * scale }

    var outerPadding: CGFloat { s(24) }
    var outerSpacing: CGFloat { s(12) }
    var chromeBarHeight: CGFloat { s(26) }
    var chromeBarTopPadding: CGFloat { s(14) }
    var chromeBarBottomPadding: CGFloat { s(2) }
    var chromeBarLeadingPadding: CGFloat { s(2) }
    var chromeBarHorizontalPadding: CGFloat { s(18) }
    var chromeButtonSpacing: CGFloat { s(8) }
    var chromeButtonSize: CGFloat { s(14) }
    var chromeSettingsButtonSize: CGFloat { s(32) }
    var chromeSettingsIconSize: CGFloat { s(14) }
    var chromeSettingsButtonCornerRadius: CGFloat { s(9) }
    var chromeOverlayTopPadding: CGFloat { s(12) }
    var chromeOverlayLeading: CGFloat { s(18) }
    var chromeOverlaySpacing: CGFloat { s(6) }
    var workspacePadding: CGFloat { s(18) }
    var workspaceCornerRadius: CGFloat { s(16) }
    var panelGap: CGFloat { s(18) }
    var panelCornerRadius: CGFloat { s(20) }
    var sidebarWidth: CGFloat { max(s(500), min(s(560), containerSize.width * 0.38)) }
    var sidebarPadding: CGFloat { s(16) }
    var sidebarSpacing: CGFloat { s(12) }
    var searchHeight: CGFloat { s(42) }
    var searchCornerRadius: CGFloat { s(14) }
    var searchPaddingX: CGFloat { s(14) }
    var searchIconSize: CGFloat { s(15) }
    var searchTextSize: CGFloat { s(14) }
    var searchHintSize: CGFloat { s(12) }
    var chipSpacing: CGFloat { s(6) }
    var chipHeight: CGFloat { s(30) }
    var chipPaddingX: CGFloat { s(12) }
    var chipIconSize: CGFloat { s(12) }
    var chipTextSize: CGFloat { s(12) }
    var sectionLabelSize: CGFloat { s(13) }
    var rowSpacing: CGFloat { s(10) }
    var rowHeight: CGFloat { s(122) }
    var rowCornerRadius: CGFloat { s(18) }
    var rowPaddingX: CGFloat { s(12) }
    var rowPaddingY: CGFloat { s(10) }
    var rowTitleSize: CGFloat { s(17) }
    var rowSubtitleSize: CGFloat { s(12) }
    var rowSnippetSize: CGFloat { s(13) }
    var rowMetaSize: CGFloat { s(11) }
    var rowStatusDotSize: CGFloat { s(9) }
    var rowActionSize: CGFloat { s(18) }
    var rowActionIconSize: CGFloat { s(14) }
    var rowAccessoryGap: CGFloat { s(8) }
    var rowContentGap: CGFloat { s(12) }
    var rowTextSpacing: CGFloat { s(5) }
    var rowTagSize: CGFloat { s(12) }
    var rowImagePreviewWidth: CGFloat { s(90) }
    var rowImagePreviewHeight: CGFloat { s(72) }
    var rowImagePreviewCornerRadius: CGFloat { s(12) }
    var rowFilePreviewCornerRadius: CGFloat { s(14) }
    var rowFileIconSize: CGFloat { s(18) }
    var footerButtonSize: CGFloat { s(22) }
    var footerIconSize: CGFloat { s(11) }
    var badgeSize: CGFloat { s(40) }
    var badgeCornerRadius: CGFloat { s(12) }
    var badgeIconSize: CGFloat { s(18) }
    var footerSize: CGFloat { s(12) }
    var detailPaddingX: CGFloat { s(24) }
    var detailPaddingY: CGFloat { s(22) }
    var detailSpacing: CGFloat { s(16) }
    var detailLabelSize: CGFloat { s(13) }
    var detailLabelColumnWidth: CGFloat { s(92) }
    var detailValueSize: CGFloat { s(14) }
    var detailButtonSize: CGFloat { s(14) }
    var detailActionHeight: CGFloat { s(44) }
    var detailTitleSize: CGFloat { s(32) }
    var detailSubtitleSize: CGFloat { s(15) }
    var previewTextSize: CGFloat { s(42) }
    var detailButtonGap: CGFloat { s(12) }
    var heroImageHeight: CGFloat { s(320) }
    var rowTimeWidth: CGFloat { s(112) }
    var rowKindWidth: CGFloat { s(72) }
    var rowFooterWidth: CGFloat { s(138) }

    var sidebarMinWidth: CGFloat { s(420) }
    var sidebarMaxWidth: CGFloat { min(s(640), containerSize.width * 0.48) }
    var resizeHandleWidth: CGFloat { s(14) }
    var resizeHandleHeight: CGFloat { s(86) }

    func clampedSidebarWidth(_ value: CGFloat) -> CGFloat {
        min(max(value, sidebarMinWidth), sidebarMaxWidth)
    }

    // Compatibility for older views still in this file.
    var panelSpacing: CGFloat { panelGap }
    var detailPadding: CGFloat { detailPaddingX }
    var toolbarButtonSize: CGFloat { s(34) }
    var toolbarDotsSize: CGFloat { s(16) }
    var toolbarPillTextSize: CGFloat { s(13) }
    var toolbarPillHeight: CGFloat { s(32) }
    var searchBarMaxWidth: CGFloat { s(430) }
    var searchBarHeight: CGFloat { s(38) }
    var searchHorizontalPadding: CGFloat { s(14) }
    var toolbarSpacing: CGFloat { s(12) }
    var toolbarIconSize: CGFloat { s(12) }
    var panelPadding: CGFloat { s(16) }
    var mainSectionSpacing: CGFloat { s(14) }
    var categorySpacing: CGFloat { s(10) }
    var cardPanelSpacing: CGFloat { s(12) }
    var cardPanelPadding: CGFloat { s(14) }
    var cardPanelCornerRadius: CGFloat { s(18) }
    var cardSpacing: CGFloat { s(14) }
    var cardMinWidth: CGFloat { s(200) }
    var cardHeight: CGFloat { s(300) }
    var cardShadowRadius: CGFloat { s(8) }
    var cardSpacingInner: CGFloat { s(12) }
    var cardPadding: CGFloat { s(14) }
    var cardCornerRadius: CGFloat { s(22) }
    var sectionTitleSize: CGFloat { s(15) }
    var filterIconSize: CGFloat { s(11) }
    var footerFontSize: CGFloat { s(13) }
    var chipHorizontalPadding: CGFloat { s(14) }
    var chipVerticalPadding: CGFloat { s(8) }
    var detailCornerRadius: CGFloat { s(22) }
    var smallCornerRadius: CGFloat { s(12) }
    var mediumCornerRadius: CGFloat { s(14) }
    var heroMinHeight: CGFloat { s(310) }
    var heroPreviewMinHeight: CGFloat { s(280) }
    var heroTitleSize: CGFloat { s(27) }
    var heroSubtitleSize: CGFloat { s(15) }
    var heroBodySize: CGFloat { s(14) }
    var codePaneMinHeight: CGFloat { s(124) }
}
