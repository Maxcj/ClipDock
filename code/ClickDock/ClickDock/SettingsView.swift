//
//  SettingsView.swift
//  ClipDock
//

import SwiftUI
import CoreData
import AppKit

struct SettingsView: View {
    @Environment(\.appLocalizer) private var localizer
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var loginItemManager: LoginItemManager
    @State private var activeTab: SettingsTab = .general
    @State private var hasConfiguredWindow = false
    @State private var windowRef: NSWindow?
    @AppStorage("clipboard.startAtLogin") private var startAtLogin = false
    @AppStorage("clipboard.keepImages") private var keepImages = true
    @AppStorage("clipboard.retentionEnabled") private var retentionEnabled = true
    @AppStorage("clipboard.retentionValue") private var retentionValue = 7
    @AppStorage("clipboard.retentionUnit") private var retentionUnit = RetentionUnit.day.rawValue
    @AppStorage("clipboard.hotkeyEnabled") private var hotkeyEnabled = true
    @AppStorage("clipboard.hotkeyKeyCode") private var hotkeyKeyCode = HotKeyConfiguration.defaultKeyCode
    @AppStorage("clipboard.hotkeyModifiers") private var hotkeyModifiers = Int(HotKeyConfiguration.defaultModifiers)
    @AppStorage("clipboard.hotkeyDisplay") private var hotkeyDisplay = HotKeyConfiguration.defaultDisplay
    @AppStorage("clipboard.autoHideAfterCopy") private var autoHideAfterCopy = false
    @AppStorage(ClipboardPrivacyRules.excludedBundleIdentifiersStorageKey) private var excludedBundleIdentifiersStorage = ""
    @AppStorage("app.languagePreference") private var languagePreference = AppLanguagePreference.system.rawValue

    var body: some View {
        GeometryReader { proxy in
            let layout = SettingsWindowMetrics(containerSize: proxy.size)
            let topInset = max(0, proxy.safeAreaInsets.top - layout.topInsetCompensation)

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    settingsSidebar(layout: layout)
                        .frame(width: layout.sidebarWidth)

                    Rectangle()
                        .fill(Color.black.opacity(0.06))
                        .frame(width: 1)

                    ScrollView(.vertical, showsIndicators: false) {
                        settingsPane(layout: layout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, layout.contentPadding)
                        .padding(.top, layout.contentTopPadding)
                        .padding(.bottom, layout.contentPadding)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.98),
                                Color(red: 0.97, green: 0.98, blue: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .frame(
                    width: proxy.size.width + layout.panelHorizontalBleed,
                    height: proxy.size.height + topInset + layout.panelVerticalBleed
                )
                .background(
                    RoundedRectangle(cornerRadius: layout.windowCornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.30),
                                    Color.white.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: layout.windowCornerRadius, style: .continuous))
                        )
                        .shadow(color: .black.opacity(0.12), radius: 26, x: 0, y: 12)
                )
                .clipShape(RoundedRectangle(cornerRadius: layout.windowCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: layout.windowCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.42), lineWidth: 1)
                )
                .padding(layout.windowPadding)

                SettingsCloseOverlay(window: windowRef, metrics: layout)
            }
            .ignoresSafeArea()
        }
        .frame(minWidth: 720, minHeight: 500)
        .background(
            WindowAccessor { window in
                if windowRef !== window {
                    windowRef = window
                }
                guard !hasConfiguredWindow else { return }
                hasConfiguredWindow = true
                configureSettingsWindow(window)
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        )
        .onAppear {
            loginItemManager.refreshStatus()
            startAtLogin = loginItemManager.isEnabled
        }
        .onChange(of: startAtLogin) { newValue in
            guard newValue != loginItemManager.isEnabled else { return }
            loginItemManager.setEnabled(newValue)
            startAtLogin = loginItemManager.isEnabled
        }
    }

    private func configureSettingsWindow(_ window: NSWindow) {
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert([.fullSizeContentView, .titled, .closable, .miniaturizable, .resizable])
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .normal
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.animationBehavior = .utilityWindow
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    @ViewBuilder
    private func settingsSidebar(layout: SettingsWindowMetrics) -> some View {
        VStack(alignment: .leading, spacing: layout.sidebarSpacing) {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 74, height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(appName)
                        .font(.system(size: 20, weight: .semibold))
                    Text(localizer.text(.versionLabel, appVersion))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 18)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        activeTab = tab
                    } label: {
                        settingsSidebarItem(tab: tab, isSelected: activeTab == tab)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, layout.sidebarPadding)
        .padding(.vertical, layout.sidebarPadding)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color.white.opacity(0.16))
            }
        )
    }

    @ViewBuilder
    private func settingsPane(layout: SettingsWindowMetrics) -> some View {
        switch activeTab {
        case .general:
            VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                settingsSection(title: localizer.text(.launchAndBehavior), subtitle: localizer.text(.launchAndBehaviorSubtitle)) {
                    settingsToggleRow(
                        iconName: "power",
                        title: localizer.text(.launchAtLogin),
                        subtitle: localizer.text(.launchAtLoginSubtitle),
                        isOn: $startAtLogin
                    )

                    Divider().padding(.leading, 52)

                    settingsToggleRow(
                        iconName: "rectangle.on.rectangle",
                        title: localizer.text(.autoHideAfterCopy),
                        subtitle: localizer.text(.autoHideAfterCopySubtitle),
                        isOn: $autoHideAfterCopy
                    )

                    if let statusMessage = loginItemManager.statusMessage {
                        Divider().padding(.leading, 52)
                        settingsInlineMessage(statusMessage)
                    }
                }

                settingsSection(title: localizer.text(.interfaceSection), subtitle: localizer.text(.interfaceSectionSubtitle)) {
                    settingsValueRow(
                        iconName: "globe",
                        title: localizer.text(.language),
                        subtitle: localizer.text(.languageSubtitle)
                    ) {
                        Picker("", selection: $languagePreference) {
                            ForEach(AppLanguagePreference.allCases) { option in
                                Text(localizedTitle(for: option)).tag(option.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 132)
                    }
                }

                settingsSection(title: localizer.text(.clipboardSection), subtitle: localizer.text(.clipboardSectionSubtitle)) {
                    settingsToggleRow(
                        iconName: "photo.on.rectangle",
                        title: localizer.text(.keepImages),
                        subtitle: localizer.text(.keepImagesSubtitle),
                        isOn: $keepImages
                    )
                }

                settingsSection(title: localizer.text(.dataManagement), subtitle: localizer.text(.dataManagementSubtitle)) {
                    settingsDestructiveRow(
                        iconName: "trash",
                        title: localizer.text(.clearAllHistory),
                        subtitle: localizer.text(.clearAllHistorySubtitle),
                        buttonTitle: localizer.text(.clear),
                        action: {
                            clearAllHistory()
                        }
                    )
                }
            }
        case .quickOpen:
            VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                settingsSection(title: localizer.text(.shortcutSection), subtitle: localizer.text(.shortcutSectionSubtitle)) {
                    settingsShortcutRow()
                }
            }
        case .privacy:
            VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                settingsSection(title: localizer.text(.privacySection), subtitle: localizer.text(.privacySectionSubtitle)) {
                    if excludedBundleIdentifiers.isEmpty {
                        settingsPlaceholderRow(
                            iconName: "hand.raised",
                            title: localizer.text(.noExcludedApps),
                            subtitle: localizer.text(.noExcludedAppsSubtitle)
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(excludedBundleIdentifiers, id: \.self) { bundleIdentifier in
                                settingsPrivacyAppRow(bundleIdentifier: bundleIdentifier)

                                if bundleIdentifier != excludedBundleIdentifiers.last {
                                    Divider().padding(.leading, 56)
                                }
                            }
                        }
                    }
                }
            }
        case .autoClean:
            VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                settingsSection(title: localizer.text(.autoCleanSection), subtitle: localizer.text(.autoCleanSectionSubtitle)) {
                    settingsToggleRow(
                        iconName: "clock.arrow.circlepath",
                        title: localizer.text(.enableAutoCleanup),
                        subtitle: localizer.text(.enableAutoCleanupSubtitle),
                        isOn: $retentionEnabled
                    )

                    Divider().padding(.leading, 52)

                    settingsValueRow(
                        iconName: "calendar.badge.clock",
                        title: localizer.text(.retentionDuration),
                        subtitle: localizer.text(.retentionDurationSubtitle),
                        accessory: {
                            HStack(spacing: 8) {
                                TextField("", value: $retentionValue, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 72)
                                    .multilineTextAlignment(.trailing)

                                Picker("", selection: $retentionUnit) {
                                    ForEach(RetentionUnit.allCases) { unit in
                                        Text(unit.title).tag(unit.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 98)
                            }
                        }
                    )
                }
            }
        case .about:
            VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                settingsSection(title: localizer.text(.about), subtitle: localizer.text(.appInfo)) {
                    settingsAboutRow()
                }
            }
        }
    }
    @ViewBuilder
    private func settingsSidebarItem(tab: SettingsTab, isSelected: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? tab.tint.opacity(0.16) : Color.white.opacity(0.0))

                Image(systemName: tab.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? tab.tint : Color.black.opacity(0.62))
            }
            .frame(width: 36, height: 36)

            Text(localizer.text(tab.titleKey))
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(isSelected ? tab.tint : Color.black.opacity(0.80))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? tab.tint.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? tab.tint.opacity(0.18) : Color.clear, lineWidth: 1)
        )
    }


    private func settingsSection<Content: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.38), lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private func settingsToggleRow(
        iconName: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        SettingsPreferenceRow(iconName: iconName, title: title, subtitle: subtitle) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    @ViewBuilder
    private func settingsValueRow<Accessory: View>(
        iconName: String,
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        SettingsPreferenceRow(iconName: iconName, title: title, subtitle: subtitle) {
            accessory()
        }
    }

    @ViewBuilder
    private func settingsDisclosureRow(
        iconName: String,
        title: String,
        subtitle: String,
        trailingText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SettingsPreferenceRow(iconName: iconName, title: title, subtitle: subtitle) {
                HStack(spacing: 10) {
                    Text(trailingText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func settingsDestructiveRow(
        iconName: String,
        title: String,
        subtitle: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        SettingsPreferenceRow(iconName: iconName, title: title, subtitle: subtitle) {
            Button(buttonTitle, action: action)
                .buttonStyle(DestructivePillButtonStyle())
        }
    }

    @ViewBuilder
    private func settingsPlaceholderRow(iconName: String, title: String, subtitle: String) -> some View {
        SettingsPreferenceRow(iconName: iconName, title: title, subtitle: subtitle) {
            Text("...")
                .font(.system(size: 11))
                .foregroundStyle(.clear)
        }
    }

    @ViewBuilder
    private func settingsPrivacyAppRow(bundleIdentifier: String) -> some View {
        HStack(spacing: 14) {
            privacyAppIcon(for: bundleIdentifier)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(ClipboardPrivacyRules.displayName(for: bundleIdentifier))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                Text(bundleIdentifier)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            Button(localizer.text(.remove)) {
                removeExcludedBundleIdentifier(bundleIdentifier)
            }
            .buttonStyle(SettingsSecondaryButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func settingsShortcutRow() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsPreferenceRow(
                iconName: "command",
                title: localizer.text(.shortcutRecordTitle),
                subtitle: localizer.text(.shortcutChangeSubtitle)
            ) {
                ShortcutRecorderField(
                    keyCode: $hotkeyKeyCode,
                    modifiers: $hotkeyModifiers,
                    displayText: $hotkeyDisplay,
                    defaultKeyCode: HotKeyConfiguration.defaultKeyCode,
                    defaultModifiers: Int(HotKeyConfiguration.defaultModifiers),
                    defaultDisplay: HotKeyConfiguration.defaultDisplay
                )
            }

            if let statusMessage = loginItemManager.statusMessage {
                settingsInlineMessage(statusMessage)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func settingsAboutRow() -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 8) {
                Text(appName)
                    .font(.system(size: 20, weight: .regular))
                Text(localizer.text(.appTagline))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Divider().padding(.vertical, 4)

                SettingsInlineKeyValueRow(title: localizer.text(.author), value: appAuthor)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func clearAllHistory() {
        let request = NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")

        do {
            let records = try viewContext.fetch(request)
            records.forEach {
                removeCachedAssets(for: $0)
                viewContext.delete($0)
            }
            try viewContext.save()
        } catch {
            NSLog("Failed to clear clipboard history from settings: \(error.localizedDescription)")
        }
    }

    private func localizedTitle(for preference: AppLanguagePreference) -> String {
        switch preference {
        case .system:
            return localizer.text(.followSystem)
        case .simplifiedChinese:
            return localizer.text(.simplifiedChinese)
        case .english:
            return localizer.text(.english)
        }
    }

    @ViewBuilder
    private func settingsInlineMessage(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .general:
            SettingsTabCard {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Launch at login", isOn: $startAtLogin)
                    if let statusMessage = loginItemManager.statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Toggle("Keep images in history", isOn: $keepImages)
                    Toggle("Auto-hide after copying from history", isOn: $autoHideAfterCopy)
                    Text("Hide the main window after copying a clipboard item so you can paste immediately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .about:
            SettingsTabCard {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(appName)
                            .font(.headline)
                        Text("A lightweight clipboard manager for fast copy and paste workflows.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    LabeledContent("Author:", value: appAuthor)
                    LabeledContent("Version:", value: appVersion)
                }
            }
        case .privacy:
            SettingsTabCard {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Source App Exclusions")
                            .font(.headline)
                        Text("Items copied from excluded apps are not recorded in history. You can add apps from the item detail panel.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if excludedBundleIdentifiers.isEmpty {
                        Text("No excluded apps yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(excludedBundleIdentifiers, id: \.self) { bundleIdentifier in
                                HStack(spacing: 12) {
                                    privacyAppIcon(for: bundleIdentifier)
                                        .frame(width: 30, height: 30)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ClipboardPrivacyRules.displayName(for: bundleIdentifier))
                                            .font(.subheadline.weight(.semibold))
                                        Text(bundleIdentifier)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }

                                    Spacer(minLength: 0)

                                    Button("Remove") {
                                        removeExcludedBundleIdentifier(bundleIdentifier)
                                    }
                                    .buttonStyle(SettingsSecondaryButtonStyle())
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.white.opacity(0.48))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                )
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Clear All") {
                            excludedBundleIdentifiersStorage = ""
                        }
                        .buttonStyle(SettingsSecondaryButtonStyle())

                        Spacer(minLength: 0)
                    }
                }
            }
        case .quickOpen:
            SettingsTabCard {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Enable global hotkey", isOn: $hotkeyEnabled)

                    ShortcutRecorderField(
                        keyCode: $hotkeyKeyCode,
                        modifiers: $hotkeyModifiers,
                        displayText: $hotkeyDisplay,
                        defaultKeyCode: HotKeyConfiguration.defaultKeyCode,
                        defaultModifiers: Int(HotKeyConfiguration.defaultModifiers),
                        defaultDisplay: HotKeyConfiguration.defaultDisplay
                    )
                }
            }
        case .autoClean:
            SettingsTabCard {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Enable auto cleanup", isOn: $retentionEnabled)

                    HStack(spacing: 10) {
                        Text("Delete unpinned items older than")
                            .font(.subheadline)

                        TextField("", value: $retentionValue, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 76)
                            .multilineTextAlignment(.trailing)

                        Picker("", selection: $retentionUnit) {
                            ForEach(RetentionUnit.allCases) { unit in
                                Text(unit.title).tag(unit.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)

                        Spacer()
                    }

                    Text("Pinned items are never removed by auto cleanup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var excludedBundleIdentifiers: [String] {
        ClipboardPrivacyRules.bundleIdentifiers(from: excludedBundleIdentifiersStorage)
    }

    private func removeExcludedBundleIdentifier(_ bundleIdentifier: String) {
        var identifiers = excludedBundleIdentifiers
        identifiers.removeAll { $0 == bundleIdentifier }
        excludedBundleIdentifiersStorage = ClipboardPrivacyRules.storageValue(from: identifiers)
    }

    @ViewBuilder
    private func privacyAppIcon(for bundleIdentifier: String) -> some View {
        if let icon = ClipboardAppIconCache.shared.icon(bundleId: bundleIdentifier) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .overlay(
                    Image(systemName: "app.dashed")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                )
        }
    }

    private var settingsTabBar: some View {
        HStack(spacing: 10) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    activeTab = tab
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 13, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(activeTab == tab ? Color.white : Color.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(activeTab == tab ? tab.tint : Color.white.opacity(0.72))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(activeTab == tab ? tab.tint.opacity(0.35) : Color.black.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
    }

}
