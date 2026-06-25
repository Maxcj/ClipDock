//
//  SettingsSupportViews.swift
//  ClipDock
//

import SwiftUI
import AppKit

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case privacy
    case quickOpen
    case autoClean
    case about

    var id: String { rawValue }

    var titleKey: AppTextKey {
        switch self {
        case .general: return .general
        case .privacy: return .privacy
        case .quickOpen: return .quickOpen
        case .autoClean: return .autoClean
        case .about: return .about
        }
    }

    var title: String {
        AppLocalizer.current.text(titleKey)
    }

    var iconName: String {
        switch self {
        case .general: return "gearshape.fill"
        case .privacy: return "hand.raised.fill"
        case .quickOpen: return "keyboard"
        case .autoClean: return "clock.arrow.circlepath"
        case .about: return "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general: return Color(red: 0.20, green: 0.49, blue: 0.98)
        case .privacy: return Color(red: 0.56, green: 0.36, blue: 0.83)
        case .quickOpen: return Color(red: 0.16, green: 0.68, blue: 0.34)
        case .autoClean: return Color(red: 0.99, green: 0.67, blue: 0.15)
        case .about: return Color(red: 0.61, green: 0.39, blue: 0.95)
        }
    }
}

struct SettingsWindowMetrics {
    let containerSize: CGSize

    var windowPadding: CGFloat { 0 }
    var windowCornerRadius: CGFloat { 16 }
    var sidebarWidth: CGFloat { max(200, min(236, containerSize.width * 0.27)) }
    var sidebarPadding: CGFloat { 16 }
    var sidebarSpacing: CGFloat { 14 }
    var contentPadding: CGFloat { 18 }
    var contentTopPadding: CGFloat { 18 }
    var sectionSpacing: CGFloat { 16 }
    var titleSize: CGFloat { 26 }
    var rowSpacing: CGFloat { 12 }
    var topInsetCompensation: CGFloat { 18 }
    var panelHorizontalBleed: CGFloat { 2 }
    var panelVerticalBleed: CGFloat { 22 }
    var closeButtonSize: CGFloat { 12 }
    var closeButtonLeading: CGFloat { windowPadding + 12 }
    var closeButtonTop: CGFloat { windowPadding + 12 }
}

struct SettingsCloseOverlay: View {
    let window: NSWindow?
    let metrics: SettingsWindowMetrics

    var body: some View {
        HStack {
            ChromeButton(
                color: Color(red: 1.0, green: 0.37, blue: 0.31),
                symbolName: "xmark",
                size: metrics.closeButtonSize
            ) {
                window?.orderOut(nil)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, metrics.closeButtonLeading)
        .padding(.top, metrics.closeButtonTop)
    }
}

struct SettingsPreferenceRow<Accessory: View>: View {
    let iconName: String
    let title: String
    let subtitle: String
    let accessory: Accessory

    init(
        iconName: String,
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.iconName = iconName
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.04))

                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            accessory
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct SettingsInlineKeyValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(title):")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
    }
}

struct DestructivePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(Color(red: 0.96, green: 0.27, blue: 0.22).opacity(configuration.isPressed ? 0.82 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .red.opacity(0.16), radius: 8, x: 0, y: 3)
    }
}

struct SettingsSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(configuration.isPressed ? 0.56 : 0.80))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
    }
}

struct SettingsTabCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 6)
    }
}

extension SettingsView {
    var appName: String {
        "ClipDock"
    }

    var appAuthor: String {
        "Maxcj"
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ?? "Unknown"
    }
}

struct ShortcutRecorderField: View {
    @Environment(\.appLocalizer) private var localizer
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    @Binding var displayText: String

    let defaultKeyCode: Int
    let defaultModifiers: Int
    let defaultDisplay: String

    @State private var isCapturing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizer.text(.shortcutRecordTitle))
                        .font(.system(size: 12, weight: .semibold))
                    Text(localizer.text(.shortcutRecordHint))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(isCapturing ? localizer.text(.recording) : localizer.text(.change)) {
                    isCapturing = true
                }
                .buttonStyle(SettingsSecondaryButtonStyle())

                Button(localizer.text(.reset)) {
                    keyCode = defaultKeyCode
                    modifiers = defaultModifiers
                    displayText = defaultDisplay
                }
                .buttonStyle(SettingsSecondaryButtonStyle())
            }

            HStack(spacing: 8) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)
                Text(displayText.isEmpty ? localizer.text(.noShortcutSet) : displayText)
                    .font(.system(size: 12, design: .monospaced))
                    .monospacedDigit()
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.white.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .overlay(
                Group {
                    if isCapturing {
                        ShortcutCaptureView(
                            onCapture: { capturedKeyCode, capturedModifiers, capturedDisplay in
                                keyCode = capturedKeyCode
                                modifiers = capturedModifiers
                                displayText = capturedDisplay
                                isCapturing = false
                            },
                            onCancel: {
                                isCapturing = false
                            }
                        )
                        .allowsHitTesting(true)
                    }
                }
            )
        }
    }
}

struct ShortcutCaptureView: NSViewRepresentable {
    let onCapture: (Int, Int, String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        KeyCaptureNSView(onCapture: onCapture, onCancel: onCancel)
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
    }

    final class KeyCaptureNSView: NSView {
        var onCapture: (Int, Int, String) -> Void
        var onCancel: () -> Void

        init(onCapture: @escaping (Int, Int, String) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            let keyCode = Int(event.keyCode)
            if keyCode == 53 {
                onCancel()
                return
            }

            let modifiers = HotKeyConfiguration.carbonModifiers(from: event.modifierFlags)
            guard modifiers != 0 else { return }

            onCapture(keyCode, modifiers, HotKeyConfiguration.displayString(for: event))
        }
    }
}
