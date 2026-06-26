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
    case storage
    case updates
    case about

    var id: String { rawValue }

    var titleKey: AppTextKey {
        switch self {
        case .general: return .general
        case .privacy: return .privacy
        case .quickOpen: return .quickOpen
        case .storage: return .storage
        case .updates: return .updates
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
        case .storage: return "internaldrive.fill"
        case .updates: return "arrow.triangle.2.circlepath"
        case .about: return "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general: return Color(red: 0.20, green: 0.49, blue: 0.98)
        case .privacy: return Color(red: 0.56, green: 0.36, blue: 0.83)
        case .quickOpen: return Color(red: 0.16, green: 0.68, blue: 0.34)
        case .storage: return Color(red: 0.21, green: 0.64, blue: 0.88)
        case .updates: return Color(red: 0.86, green: 0.48, blue: 0.16)
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
    let isDimmed: Bool

    init(
        iconName: String,
        title: String,
        subtitle: String,
        isDimmed: Bool = false,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.iconName = iconName
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
        self.isDimmed = isDimmed
    }

    var body: some View {
        let iconColor: Color = isDimmed ? Color.secondary.opacity(0.52) : Color.secondary
        let titleColor: Color = isDimmed ? Color.secondary : Color.primary
        let subtitleColor: Color = isDimmed ? Color.secondary.opacity(0.82) : Color.secondary

        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(isDimmed ? 0.02 : 0.04))

                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(titleColor)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(subtitleColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            accessory
                .opacity(isDimmed ? 0.55 : 1.0)
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
