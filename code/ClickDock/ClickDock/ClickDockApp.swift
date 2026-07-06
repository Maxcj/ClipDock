//
//  ClipDockApp.swift
//  ClipDock
//
//  Created by Maxcj on 2026/6/22.
//

import SwiftUI
import AppKit
import CoreData
import ServiceManagement
import KeyboardShortcuts

enum WindowLayout {
    static let defaultSize = CGSize(width: 992, height: 704)
    static let minimumSize = CGSize(width: 868, height: 602)
}

@main
struct ClipDockApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var clipboardMonitor: ClipboardMonitor
    @StateObject private var keyboardShortcutManager: KeyboardShortcutManager
    @StateObject private var loginItemManager: LoginItemManager
    @StateObject private var storageSummaryScheduler: StorageSummaryScheduler
    @StateObject private var sparkleUpdateManager: SparkleUpdateManager
    @AppStorage("app.languagePreference") private var languagePreference = AppLanguagePreference.system.rawValue

    init() {
        let context = PersistenceController.shared.container.viewContext
        _clipboardMonitor = StateObject(wrappedValue: ClipboardMonitor(context: context))
        UserDefaults.standard.register(defaults: [
            "clipboard.autoHideAfterCopy": false,
            "clipboard.keepImages": true,
            "clipboard.keepFiles": false,
            "clipboard.fileHistoryCopyStrategy": FileHistoryCopyStrategy.pathOnly.rawValue,
            "clipboard.retentionEnabled": true,
            "clipboard.retentionValue": 7,
            "clipboard.retentionUnit": RetentionUnit.day.rawValue,
            "sparkle.automaticallyChecksForUpdates": false,
            "sparkle.updateCheckInterval": 60.0 * 60.0 * 24.0,
            "sparkle.updateChannel": SparkleUpdateDefaults.defaultUpdateChannelRawValue,
            ClipboardPrivacyRules.ignoreVerificationCodesStorageKey: false,
            ClipboardPrivacyRules.ignorePasswordsAndTokensStorageKey: false,
            ClipboardPrivacyRules.ignorePrivateKeysStorageKey: false,
            ClipboardPrivacyRules.ignoreLongSensitiveTextStorageKey: false
        ])
        _keyboardShortcutManager = StateObject(wrappedValue: KeyboardShortcutManager())
        _loginItemManager = StateObject(wrappedValue: LoginItemManager())
        if !UserDefaults.standard.bool(forKey: "clipboard.cachedSizeBytesMigrated") {
            ClipboardStorageCalculator.rebuildCachedSizes(context: context)
            UserDefaults.standard.set(true, forKey: "clipboard.cachedSizeBytesMigrated")
        }
        let storageSummaryScheduler = StorageSummaryScheduler(container: PersistenceController.shared.container)
        _storageSummaryScheduler = StateObject(wrappedValue: storageSummaryScheduler)
        storageSummaryScheduler.start()
        _sparkleUpdateManager = StateObject(wrappedValue: SparkleUpdateManager())
    }

    var body: some Scene {
        let localizer = AppLocalizer(language: AppDisplayLanguage.resolve(from: languagePreference))

        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(\.appLocalizer, localizer)
                .environment(\.locale, Locale(identifier: localizer.language.localeIdentifier))
                .environmentObject(clipboardMonitor)
                .environmentObject(keyboardShortcutManager)
                .environmentObject(loginItemManager)
                .environmentObject(storageSummaryScheduler)
                .environmentObject(sparkleUpdateManager)
        }
        .defaultSize(width: WindowLayout.defaultSize.width, height: WindowLayout.defaultSize.height)
        .windowResizability(.contentSize)

        Window("Settings", id: "settings") {
            SettingsView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(\.appLocalizer, localizer)
                .environment(\.locale, Locale(identifier: localizer.language.localeIdentifier))
                .environmentObject(loginItemManager)
                .environmentObject(storageSummaryScheduler)
                .environmentObject(sparkleUpdateManager)
        }
        .defaultSize(width: 760, height: 520)
        .windowResizability(.contentSize)

        MenuBarExtra {
            StatusBarMenuView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(\.appLocalizer, localizer)
                .environment(\.locale, Locale(identifier: localizer.language.localeIdentifier))
                .environmentObject(sparkleUpdateManager)
        } label: {
            Image("StatusBarIcon")
                .renderingMode(.original)
        }
    }
}

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var statusMessageKey: AppTextKey?
    @Published private(set) var runtimeErrorMessage: String?

    var statusMessage: String? {
        if let runtimeErrorMessage, !runtimeErrorMessage.isEmpty {
            return runtimeErrorMessage
        }
        guard let statusMessageKey else { return nil }
        return AppLocalizer.current.text(statusMessageKey)
    }

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            statusMessageKey = nil
            runtimeErrorMessage = nil
        case .requiresApproval:
            isEnabled = false
            statusMessageKey = .loginApprovalRequired
            runtimeErrorMessage = nil
        case .notFound:
            isEnabled = false
            statusMessageKey = .loginItemNotFound
            runtimeErrorMessage = nil
        case .notRegistered:
            isEnabled = false
            statusMessageKey = nil
            runtimeErrorMessage = nil
        @unknown default:
            isEnabled = false
            statusMessageKey = .loginStatusUnknown
            runtimeErrorMessage = nil
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            runtimeErrorMessage = error.localizedDescription
        }

        refreshStatus()
    }
}

private struct StatusBarMenuView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.appLocalizer) private var localizer
    @EnvironmentObject private var sparkleUpdateManager: SparkleUpdateManager
    private var appVersion: String { Bundle.main.appVersionString }

    var body: some View {
        Button(action: {}) {
            statusBarMenuRow(
                title: appVersion,
                systemImage: "info.circle",
                tint: .secondary,
                textFont: .system(size: 11)
            )
        }
        .buttonStyle(.plain)
        .disabled(true)

        Divider()

        Button {
            NotificationCenter.default.post(name: .clipDockTogglePanelRequested, object: nil)
        } label: {
            statusBarMenuRow(
                title: localizer.text(.showHideMainWindow),
                systemImage: "sidebar.leading"
            )
        }

        Button {
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
            openWindow(id: "settings")
        } label: {
            statusBarMenuRow(
                title: localizer.text(.settings),
                systemImage: "gearshape"
            )
        }

        Button {
            sparkleUpdateManager.checkForUpdates()
        } label: {
            statusBarMenuRow(
                title: localizer.text(.checkForUpdates),
                systemImage: "arrow.clockwise"
            )
        }
        .disabled(!sparkleUpdateManager.canCheckForUpdates || sparkleUpdateManager.isUpdateCheckInProgress)

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            statusBarMenuRow(
                title: localizer.text(.quit),
                systemImage: "power"
            )
        }
    }

    @ViewBuilder
    private func statusBarMenuRow(
        title: String,
        systemImage: String,
        tint: Color = .primary,
        textFont: Font = .body
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 14, alignment: .center)
                .font(.system(size: 12, weight: .semibold))

            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(textFont)
        .foregroundStyle(tint)
        .contentShape(Rectangle())
    }
}
