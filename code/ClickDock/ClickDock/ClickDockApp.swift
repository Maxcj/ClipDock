//
//  ClipDockApp.swift
//  ClipDock
//
//  Created by Maxcj on 2026/6/22.
//

import SwiftUI
import AppKit
import ServiceManagement

enum WindowLayout {
    static let defaultSize = CGSize(width: 1008, height: 717)
    static let minimumSize = CGSize(width: 868, height: 602)
}

@main
struct ClipDockApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var clipboardMonitor: ClipboardMonitor
    @StateObject private var hotkeyManager: GlobalHotkeyManager
    @StateObject private var loginItemManager: LoginItemManager
    @AppStorage("app.languagePreference") private var languagePreference = AppLanguagePreference.system.rawValue

    init() {
        let context = PersistenceController.shared.container.viewContext
        _clipboardMonitor = StateObject(wrappedValue: ClipboardMonitor(context: context))
        UserDefaults.standard.register(defaults: [
            "clipboard.hotkeyEnabled": false,
            "clipboard.hotkeyKeyCode": 49,
            "clipboard.hotkeyModifiers": Int(HotKeyConfiguration.defaultModifiers),
            "clipboard.hotkeyDisplay": HotKeyConfiguration.defaultDisplay,
            "clipboard.autoHideAfterCopy": false,
            "clipboard.keepImages": false,
            "clipboard.retentionEnabled": true,
            "clipboard.retentionValue": 7,
            "clipboard.retentionUnit": RetentionUnit.day.rawValue
        ])
        _hotkeyManager = StateObject(wrappedValue: GlobalHotkeyManager())
        _loginItemManager = StateObject(wrappedValue: LoginItemManager())
    }

    var body: some Scene {
        let localizer = AppLocalizer(language: AppDisplayLanguage.resolve(from: languagePreference))

        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(\.appLocalizer, localizer)
                .environment(\.locale, Locale(identifier: localizer.language.localeIdentifier))
                .environmentObject(clipboardMonitor)
                .environmentObject(hotkeyManager)
                .environmentObject(loginItemManager)
        }
        .defaultSize(width: WindowLayout.defaultSize.width, height: WindowLayout.defaultSize.height)

        Window("Settings", id: "settings") {
            SettingsView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(\.appLocalizer, localizer)
                .environment(\.locale, Locale(identifier: localizer.language.localeIdentifier))
                .environmentObject(loginItemManager)
        }
        .defaultSize(width: 720, height: 500)

        MenuBarExtra {
            StatusBarMenuView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(\.appLocalizer, localizer)
                .environment(\.locale, Locale(identifier: localizer.language.localeIdentifier))
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

    var body: some View {
        Button(localizer.text(.showHideMainWindow)) {
            NotificationCenter.default.post(name: .clipDockTogglePanelRequested, object: nil)
        }

        Button(localizer.text(.settings)) {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }

        Divider()

        Button(localizer.text(.quit)) {
            NSApplication.shared.terminate(nil)
        }
    }
}
