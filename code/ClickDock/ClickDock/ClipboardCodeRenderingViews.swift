//
//  ClipboardCodeRenderingViews.swift
//  ClipDock
//

import SwiftUI
import AppKit
import Highlighter

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
        private let highlighter: Highlighter
        private weak var textView: NSTextView?
        private weak var scrollView: NSScrollView?
        private var lastSignature: String?

        init() {
            guard let highlighter = Highlighter() else {
                preconditionFailure("HighlighterSwift failed to initialize")
            }
            self.highlighter = highlighter
            _ = self.highlighter.setTheme("github", withFont: "Menlo-Regular", ofSize: 13.0)
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

            let signature = "\(language.rawValue)\u{0}\(text)"
            guard signature != lastSignature else {
                return
            }
            lastSignature = signature

            let rendered = highlighter.highlight(text, as: language.highlighterLanguageIdentifier) ?? NSAttributedString(string: text)
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
