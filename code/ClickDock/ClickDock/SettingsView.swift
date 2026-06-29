//
//  SettingsView.swift
//  ClipDock
//

import SwiftUI
import CoreData
import AppKit
import KeyboardShortcuts

struct SettingsView: View {
    @Environment(\.appLocalizer) private var localizer
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var loginItemManager: LoginItemManager
    @EnvironmentObject private var sparkleUpdateManager: SparkleUpdateManager
    @State private var activeTab: SettingsTab = .general
    @State private var hasConfiguredWindow = false
    @State private var windowRef: NSWindow?
    @StateObject private var storageSummaryLoader = StorageSummaryLoader()
    @AppStorage("clipboard.startAtLogin") private var startAtLogin = false
    @AppStorage("clipboard.keepImages") private var keepImages = true
    @AppStorage("clipboard.keepFiles") private var keepFiles = false
    @AppStorage("clipboard.retentionEnabled") private var retentionEnabled = true
    @AppStorage("clipboard.retentionValue") private var retentionValue = 7
    @AppStorage("clipboard.retentionUnit") private var retentionUnit = RetentionUnit.day.rawValue
    @AppStorage("clipboard.autoHideAfterCopy") private var autoHideAfterCopy = false
    @AppStorage(ClipboardPrivacyRules.excludedBundleIdentifiersStorageKey) private var excludedBundleIdentifiersStorage = ""
    @AppStorage(ClipboardPrivacyRules.ignoreVerificationCodesStorageKey) private var ignoreVerificationCodes = false
    @AppStorage(ClipboardPrivacyRules.ignorePasswordsAndTokensStorageKey) private var ignorePasswordsAndTokens = false
    @AppStorage(ClipboardPrivacyRules.ignorePrivateKeysStorageKey) private var ignorePrivateKeys = false
    @AppStorage(ClipboardPrivacyRules.ignoreLongSensitiveTextStorageKey) private var ignoreLongSensitiveText = false
    @AppStorage("app.languagePreference") private var languagePreference = AppLanguagePreference.system.rawValue

    private var automaticCheckForUpdatesBinding: Binding<Bool> {
        Binding(
            get: { sparkleUpdateManager.automaticallyChecksForUpdates },
            set: { sparkleUpdateManager.setAutomaticallyChecksForUpdates($0) }
        )
    }

    private var updateCheckIntervalBinding: Binding<UpdateCheckIntervalOption> {
        Binding(
            get: { UpdateCheckIntervalOption.from(interval: sparkleUpdateManager.updateCheckInterval) },
            set: { sparkleUpdateManager.setUpdateCheckInterval($0.rawValue) }
        )
    }

    private var updateChannelBinding: Binding<SparkleUpdateChannel> {
        Binding(
            get: { sparkleUpdateManager.selectedUpdateChannel },
            set: { sparkleUpdateManager.setUpdateChannel($0) }
        )
    }

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
        .frame(minWidth: 760, minHeight: 520)
        .background(
            WindowAccessor { window in
                if windowRef !== window {
                    windowRef = window
                }
                guard !hasConfiguredWindow else { return }
                hasConfiguredWindow = true
                configureSettingsWindow(window)
                activateAppIfNeeded()
                DispatchQueue.main.async {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        )
        .onAppear {
            loginItemManager.refreshStatus()
            startAtLogin = loginItemManager.isEnabled
            if retentionValue <= 0 {
                retentionValue = 7
            }
            ClipboardCategoryManager.bootstrapSystemCategories(context: viewContext)
        }
        .onChange(of: startAtLogin) { newValue in
            guard newValue != loginItemManager.isEnabled else { return }
            loginItemManager.setEnabled(newValue)
            startAtLogin = loginItemManager.isEnabled
        }
        .onChange(of: activeTab) { newValue in
            if newValue == .storage {
                storageSummaryLoader.load(context: viewContext)
            }
        }
    }

    private func configureSettingsWindow(_ window: NSWindow) {
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert([.fullSizeContentView, .titled, .closable, .miniaturizable])
        window.styleMask.remove(.resizable)
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .normal
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.animationBehavior = .utilityWindow
        let fixedSize = NSSize(width: 760, height: 520)
        window.setContentSize(fixedSize)
        window.minSize = fixedSize
        window.maxSize = fixedSize
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func activateAppIfNeeded() {
        guard !NSApp.isActive else { return }
        NSApp.activate(ignoringOtherApps: true)
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
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                    Text(localizer.text(.versionLabel, appVersion))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .allowsTightening(true)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 18)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            activeTab = tab
                        }
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
                    settingsToggleRow(
                        iconName: "doc.on.doc",
                        title: localizer.text(.keepFiles),
                        subtitle: localizer.text(.keepFilesSubtitle),
                        isOn: $keepFiles
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
                settingsSection(title: localizer.text(.contentFilters), subtitle: localizer.text(.contentFiltersSubtitle)) {
                    settingsToggleRow(
                        iconName: "number",
                        title: localizer.text(.ignoreVerificationCodes),
                        subtitle: localizer.text(.ignoreVerificationCodesSubtitle),
                        isOn: $ignoreVerificationCodes
                    )

                    Divider().padding(.leading, 52)

                    settingsToggleRow(
                        iconName: "key.horizontal",
                        title: localizer.text(.ignorePasswordsAndTokens),
                        subtitle: localizer.text(.ignorePasswordsAndTokensSubtitle),
                        isOn: $ignorePasswordsAndTokens
                    )

                    Divider().padding(.leading, 52)

                    settingsToggleRow(
                        iconName: "lock.shield",
                        title: localizer.text(.ignorePrivateKeys),
                        subtitle: localizer.text(.ignorePrivateKeysSubtitle),
                        isOn: $ignorePrivateKeys
                    )

                    Divider().padding(.leading, 52)

                    settingsToggleRow(
                        iconName: "doc.text.magnifyingglass",
                        title: localizer.text(.ignoreLongSensitiveText),
                        subtitle: localizer.text(.ignoreLongSensitiveTextSubtitle),
                        isOn: $ignoreLongSensitiveText
                    )
                }

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
        case .storage:
            VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                settingsSection(title: localizer.text(.storageSectionTitle), subtitle: localizer.text(.storageSectionSubtitle)) {
                    if let storageSummary = storageSummaryLoader.summary {
                        settingsStaticValueRow(
                            iconName: "tray.full",
                            title: localizer.text(.storageTotalItems),
                            subtitle: localizer.text(.storageTotalItemsSubtitle),
                            value: storageSummary.totalItemsValue
                        )

                        Divider().padding(.leading, 52)

                        settingsStaticValueRow(
                            iconName: "text.alignleft",
                            title: localizer.text(.storageTextItems),
                            subtitle: localizer.text(.storageTextItemsSubtitle),
                            value: storageSummary.textItemsValue
                        )

                        Divider().padding(.leading, 52)

                        settingsStaticValueRow(
                            iconName: "photo.stack",
                            title: localizer.text(.storageImages),
                            subtitle: localizer.text(.storageImagesSubtitle),
                            value: storageSummary.imagesValue
                        )

                        Divider().padding(.leading, 52)

                        settingsStaticValueRow(
                            iconName: "externaldrive",
                            title: localizer.text(.storageFilesCache),
                            subtitle: localizer.text(.storageFilesCacheSubtitle),
                            value: storageSummary.filesCacheValue
                        )

                        Divider().padding(.leading, 52)

                        settingsStaticValueRow(
                            iconName: "globe.asia.australia",
                            title: localizer.text(.storageLinkMetadata),
                            subtitle: localizer.text(.storageLinkMetadataSubtitle),
                            value: storageSummary.linkMetadataValue
                        )

                        Divider().padding(.leading, 52)

                    } else {
                        HStack {
                            Spacer(minLength: 0)
                            ProgressView()
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }

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
                        isDimmed: !retentionEnabled,
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
                            .disabled(!retentionEnabled)
                            .opacity(retentionEnabled ? 1.0 : 0.45)
                        }
                    )
                }

                settingsSection(title: localizer.text(.dataManagement), subtitle: localizer.text(.dataManagementSubtitle)) {
                    settingsDestructiveRow(
                        iconName: "externaldrive.fill",
                        title: localizer.text(.clearCache),
                        subtitle: localizer.text(.clearCacheSubtitle),
                        buttonTitle: localizer.text(.clear),
                        action: {
                            clearStorageCache()
                        }
                    )

                    Divider().padding(.leading, 52)

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
        case .categories:
            ClipboardCategorySettingsView()
        case .about:
            VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                settingsSection(title: localizer.text(.updates), subtitle: localizer.text(.updatesSubtitle)) {
                    settingsValueRow(
                        iconName: "arrow.triangle.branch",
                        title: localizer.text(.updateChannel),
                        subtitle: localizer.text(.updateChannelSubtitle),
                        isDimmed: !sparkleUpdateManager.isConfigured
                    ) {
                        Picker("", selection: updateChannelBinding) {
                            ForEach(SparkleUpdateChannel.allCases) { channel in
                                Text(localizer.text(channel.titleKey)).tag(channel)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                        .disabled(!sparkleUpdateManager.isConfigured)
                    }

                    Divider().padding(.leading, 52)

                    settingsToggleRow(
                        iconName: "clock.arrow.circlepath",
                        title: localizer.text(.automaticCheckForUpdates),
                        subtitle: localizer.text(.automaticCheckForUpdatesSubtitle),
                        isOn: automaticCheckForUpdatesBinding,
                        isDimmed: !sparkleUpdateManager.isConfigured
                    )

                    Divider().padding(.leading, 52)

                    settingsValueRow(
                        iconName: "calendar.badge.clock",
                        title: localizer.text(.automaticCheckInterval),
                        subtitle: localizer.text(.automaticCheckIntervalSubtitle),
                        isDimmed: !sparkleUpdateManager.isConfigured || !sparkleUpdateManager.automaticallyChecksForUpdates
                    ) {
                        Picker("", selection: updateCheckIntervalBinding) {
                            ForEach(UpdateCheckIntervalOption.allCases) { option in
                                Text(localizer.text(option.titleKey)).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 160)
                        .disabled(!sparkleUpdateManager.isConfigured || !sparkleUpdateManager.automaticallyChecksForUpdates)
                    }

                    Divider().padding(.leading, 52)

                    settingsActionRow(
                        iconName: "arrow.triangle.2.circlepath",
                        title: localizer.text(.checkForUpdates),
                        subtitle: localizer.text(.checkForUpdatesSubtitle),
                        buttonTitle: localizer.text(.checkForUpdates),
                        isDimmed: !sparkleUpdateManager.canCheckForUpdates,
                        action: {
                            sparkleUpdateManager.checkForUpdates()
                        }
                    )

                    if let ignoredVersion = sparkleUpdateManager.ignoredVersion {
                        Divider().padding(.leading, 52)

                        settingsValueRow(
                            iconName: "eye.slash",
                            title: localizer.text(.ignoredVersion),
                            subtitle: localizer.text(.ignoredVersionSubtitle),
                            accessory: {
                                HStack(spacing: 10) {
                                    Text(ignoredVersion)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.trailing)

                                    Button(localizer.text(.clearIgnoredVersion)) {
                                        sparkleUpdateManager.clearIgnoredVersion()
                                    }
                                    .buttonStyle(SettingsSecondaryButtonStyle())
                                }
                            }
                        )
                    }

                    if !sparkleUpdateManager.isConfigured {
                        Divider().padding(.leading, 52)
                        settingsInlineMessage(localizer.text(.updatesFeedNotConfigured))
                    }
                }

                settingsSection(title: localizer.text(.about), subtitle: localizer.text(.appInfo)) {
                    settingsAboutRow()
                }
            }
        }
    }
    @ViewBuilder
    private func settingsSidebarItem(tab: SettingsTab, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? tab.tint.opacity(0.16) : Color.white.opacity(0.0))

                Image(systemName: tab.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? tab.tint : Color.black.opacity(0.62))
            }
            .frame(width: 32, height: 32)

            Text(localizer.text(tab.titleKey))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(isSelected ? tab.tint : Color.black.opacity(0.80))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? tab.tint.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
        isOn: Binding<Bool>,
        isDimmed: Bool = false
    ) -> some View {
        SettingsPreferenceRow(iconName: iconName, title: title, subtitle: subtitle, isDimmed: isDimmed) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(isDimmed)
        }
    }

    @ViewBuilder
    private func settingsValueRow<Accessory: View>(
        iconName: String,
        title: String,
        subtitle: String,
        isDimmed: Bool = false,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        SettingsPreferenceRow(iconName: iconName, title: title, subtitle: subtitle, isDimmed: isDimmed) {
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
    private func settingsActionRow(
        iconName: String,
        title: String,
        subtitle: String,
        buttonTitle: String,
        isDimmed: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        SettingsPreferenceRow(iconName: iconName, title: title, subtitle: subtitle, isDimmed: isDimmed) {
            Button(buttonTitle, action: action)
                .buttonStyle(SettingsSecondaryButtonStyle())
                .disabled(isDimmed)
        }
    }

    @ViewBuilder
    private func settingsStaticValueRow(
        iconName: String,
        title: String,
        subtitle: String,
        value: String
    ) -> some View {
        SettingsPreferenceRow(iconName: iconName, title: title, subtitle: subtitle) {
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
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
        SettingsPreferenceRow(
            iconName: "command",
            title: localizer.text(.shortcutRecordTitle),
            subtitle: localizer.text(.shortcutChangeSubtitle)
        ) {
            KeyboardShortcuts.Recorder("", name: .toggleMainWindow)
                .labelsHidden()
        }
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

                VStack(alignment: .leading, spacing: 4) {
                    if let appContactEmailURL {
                        SettingsInlineLinkRow(
                            title: localizer.text(.email),
                            value: appContactEmail ?? "",
                            destination: appContactEmailURL
                        )
                    }

                    SettingsInlineKeyValueRow(title: localizer.text(.author), value: appAuthor)
                }
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
            if activeTab == .storage {
                storageSummaryLoader.load(context: viewContext)
            }
        } catch {
            NSLog("Failed to clear clipboard history from settings: \(error.localizedDescription)")
        }
    }

    private func clearStorageCache() {
        let request = NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")

        do {
            let records = try viewContext.fetch(request)
            var changed = false

            for record in records {
                switch record.kind {
                case .link:
                    if record.linkTitleValue != nil || record.linkHostValue != nil || record.linkIconDataValue != nil || record.linkMetadataCheckedAtValue != nil {
                        record.linkTitleValue = nil
                        record.linkHostValue = nil
                        record.linkIconDataValue = nil
                        record.linkMetadataCheckedAtValue = nil
                        changed = true
                    }
                case .files:
                    if let legacyCacheFolderURL = record.fileReferenceSet.legacyCacheFolderURL {
                        try? FileManager.default.removeItem(at: legacyCacheFolderURL)
                    }
                    if record.assetPathValue != nil {
                        record.assetPathValue = nil
                        changed = true
                    }
                default:
                    continue
                }
            }

            if changed {
                try viewContext.save()
            }

            if activeTab == .storage {
                storageSummaryLoader.load(context: viewContext)
            }
        } catch {
            NSLog("Failed to clear storage cache from settings: \(error.localizedDescription)")
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
                    withAnimation(.easeInOut(duration: 0.18)) {
                        activeTab = tab
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 13, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(activeTab == tab ? Color.white : Color.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
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

final class StorageSummaryLoader: ObservableObject {
    @Published private(set) var summary: ClipboardStorageSummary?
    @Published private(set) var isLoading = false

    private var requestToken = UUID()

    func load(context: NSManagedObjectContext) {
        let token = UUID()
        requestToken = token
        summary = nil
        isLoading = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let computedSummary = ClipboardStorageCalculator.summary(context: context)

            DispatchQueue.main.async {
                guard let self, self.requestToken == token else { return }
                self.summary = computedSummary
                self.isLoading = false
            }
        }
    }
}
