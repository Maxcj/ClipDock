//
//  ClipboardCodeRenderingViews.swift
//  ClipDock
//

import SwiftUI
import AppKit
import Highlighter

struct ClipboardCodePane: View {
    @Environment(\.appLocalizer) private var localizer
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var clipboardMonitor: ClipboardMonitor
    @ObservedObject var record: ClipboardRecord
    @State private var copiedActionKey: String?

    var body: some View {
        let language = record.codeLanguage

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Menu {
                    ForEach(ClipboardCodeLanguage.pickerCases) { item in
                        Button {
                            updateCodeLanguage(item)
                        } label: {
                            HStack(spacing: 8) {
                                if item == language {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                }

                                Text(item.title)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(language.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(language.badgeColor)
                        Text("\(record.codeLineCount) lines")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(language.badgeColor.opacity(colorScheme == .dark ? 0.14 : 0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Spacer(minLength: 0)

                Button {
                    clipboardMonitor.copyTextSilently(
                        ClipboardCodeActions.markdownCodeBlock(record.detailText, language: language)
                    )
                    triggerCopiedFeedback(key: "markdown")
                } label: {
                    copyActionLabel(
                        title: localizer.text(.copyMarkdown),
                        systemImage: copiedActionKey == "markdown" ? "checkmark.circle.fill" : "chevron.left.forwardslash.chevron.right"
                    )
                }
                .buttonStyle(.plain)
                .help(localizer.text(.copyMarkdown))
            }
            HighlighterCodeView(text: record.detailText, language: language)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(codePaneBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(codePaneBorderColor, lineWidth: 1)
                )
        )
    }

    private func triggerCopiedFeedback(key: String) {
        withAnimation(.easeInOut(duration: 0.16)) {
            copiedActionKey = key
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard copiedActionKey == key else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                copiedActionKey = nil
            }
        }
    }

    private func copyActionLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(colorScheme == .dark ? Color.primary.opacity(0.88) : Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(copyButtonBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(copyButtonBorderColor, lineWidth: 1)
        )
    }

    private func updateCodeLanguage(_ newValue: ClipboardCodeLanguage) {
        record.setValue(newValue.rawValue, forKey: "codeLanguageRaw")
        saveContext()
    }

    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            NSLog("Failed to save code language change: \(error.localizedDescription)")
        }
    }

    private var codePaneBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.92)
    }

    private var codePaneBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.gray.opacity(0.12)
    }

    private var copyButtonBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.78)
    }

    private var copyButtonBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }
}

struct HighlighterCodeView: NSViewRepresentable {
    let text: String
    let language: ClipboardCodeLanguage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.scrollerStyle = .overlay
        scrollView.backgroundColor = .clear
        scrollView.verticalScrollElasticity = .automatic
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.backgroundColor = NSColor(calibratedWhite: 0.985, alpha: 1.0)

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.backgroundColor = NSColor(calibratedWhite: 0.985, alpha: 1.0)
        textView.textColor = .labelColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 18, height: 14)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)

        scrollView.documentView = textView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        let rulerView = CodeLineNumberRulerView(scrollView: scrollView, textView: textView, lineCount: lineCount(for: text))
        scrollView.verticalRulerView = rulerView

        context.coordinator.install(into: textView, scrollView: scrollView)
        context.coordinator.render(text: text, language: language, lineCount: lineCount(for: text))

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.install(into: textView, scrollView: scrollView)
        context.coordinator.render(text: text, language: language, lineCount: lineCount(for: text))
    }

    private func lineCount(for text: String) -> Int {
        let count = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        return max(1, count)
    }

    final class Coordinator {
        private static let maxHighlightedCharacterCount = 20_000
        private let highlighter: Highlighter?
        private weak var textView: NSTextView?
        private weak var scrollView: NSScrollView?
        private var lastSignature: String?

        init() {
            if let highlighter = Highlighter() {
                self.highlighter = highlighter
                _ = highlighter.setTheme("github", withFont: "Menlo-Regular", ofSize: 13.0)
            } else {
                self.highlighter = nil
            }
        }

        func install(into textView: NSTextView, scrollView: NSScrollView) {
            self.textView = textView
            self.scrollView = scrollView
            if let ruler = scrollView.verticalRulerView as? CodeLineNumberRulerView {
                ruler.attach(textView: textView, scrollView: scrollView)
            }
        }

        func render(text: String, language: ClipboardCodeLanguage, lineCount: Int) {
            guard let textView else { return }

            let signature = "\(language.rawValue)-\(text.count)-\(text.hashValue)"
            guard signature != lastSignature else {
                return
            }
            lastSignature = signature

            if language == .plain || text.count > Self.maxHighlightedCharacterCount {
                textView.string = text
                textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                textView.frame = NSRect(origin: .zero, size: textView.fittingSize)
                textView.scrollRangeToVisible(NSRange(location: 0, length: 0))

                if let ruler = scrollView?.verticalRulerView as? CodeLineNumberRulerView {
                    ruler.update(lineCount: lineCount)
                }
                return
            }

            let rendered = highlighter?.highlight(text, as: language.highlighterLanguageIdentifier) ?? NSAttributedString(string: text)
            textView.textStorage?.setAttributedString(rendered)
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.frame = NSRect(origin: .zero, size: textView.fittingSize)
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))

            if let ruler = scrollView?.verticalRulerView as? CodeLineNumberRulerView {
                ruler.update(lineCount: lineCount)
            }
        }
    }
}

final class CodeLineNumberRulerView: NSRulerView {
    private weak var observedTextView: NSTextView?
    private weak var observedScrollView: NSScrollView?
    private var lineCount: Int

    init(scrollView: NSScrollView, textView: NSTextView, lineCount: Int) {
        self.observedTextView = textView
        self.observedScrollView = scrollView
        self.lineCount = max(1, lineCount)
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = Self.thickness(for: self.lineCount)
        // Keep the gutter visible and stable beside the code block.
        needsDisplay = true
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(textView: NSTextView, scrollView: NSScrollView) {
        observedTextView = textView
        observedScrollView = scrollView
        clientView = textView
    }

    func update(lineCount: Int) {
        let newCount = max(1, lineCount)
        guard newCount != self.lineCount else {
            needsDisplay = true
            return
        }

        self.lineCount = newCount
        ruleThickness = Self.thickness(for: newCount)
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = observedTextView,
              let layoutManager = textView.layoutManager,
              textView.textContainer != nil else {
            return
        }

        let lineAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: {
                let style = NSMutableParagraphStyle()
                style.alignment = .right
                return style
            }()
        ]

        let backgroundGradient = NSGradient(
            colors: [
                NSColor(calibratedWhite: 0.975, alpha: 1.0),
                NSColor(calibratedWhite: 0.955, alpha: 1.0)
            ]
        )
        backgroundGradient?.draw(in: rect, angle: 0)

        let separatorX = bounds.maxX - 0.5
        NSColor.separatorColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(rect: NSRect(x: separatorX, y: bounds.minY, width: 0.5, height: bounds.height)).fill()

        var glyphIndex = 0
        var currentLineNumber = 1
        while glyphIndex < layoutManager.numberOfGlyphs {
            var lineRange = NSRange(location: 0, length: 0)
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &lineRange,
                withoutAdditionalLayout: true
            )

            let rulerLineRect = convert(lineRect, from: textView)

            if rulerLineRect.intersects(rect) {
                let numberRect = NSRect(
                    x: 6,
                    y: rulerLineRect.minY,
                    width: bounds.width - 12,
                    height: rulerLineRect.height
                )
                let label = "\(currentLineNumber)" as NSString
                label.draw(in: numberRect, withAttributes: lineAttributes)
            }

            glyphIndex = NSMaxRange(lineRange)
            currentLineNumber += 1
        }
    }

    private static func thickness(for lineCount: Int) -> CGFloat {
        let digits = max(2, String(lineCount).count)
        return CGFloat(24 + (digits * 7))
    }
}
