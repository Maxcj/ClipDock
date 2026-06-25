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

    init() {
        let context = PersistenceController.shared.container.viewContext
        _clipboardMonitor = StateObject(wrappedValue: ClipboardMonitor(context: context))
        UserDefaults.standard.register(defaults: [
            "clipboard.hotkeyEnabled": true,
            "clipboard.hotkeyKeyCode": 49,
            "clipboard.hotkeyModifiers": Int(HotKeyConfiguration.defaultModifiers),
            "clipboard.hotkeyDisplay": HotKeyConfiguration.defaultDisplay,
            "clipboard.autoHideAfterCopy": false
        ])
        _hotkeyManager = StateObject(wrappedValue: GlobalHotkeyManager())
        _loginItemManager = StateObject(wrappedValue: LoginItemManager())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(clipboardMonitor)
                .environmentObject(hotkeyManager)
                .environmentObject(loginItemManager)
        }
        .defaultSize(width: WindowLayout.defaultSize.width, height: WindowLayout.defaultSize.height)

        Window("Settings", id: "settings") {
            SettingsView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(loginItemManager)
        }
        .defaultSize(width: 720, height: 500)

        MenuBarExtra {
            StatusBarMenuView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        } label: {
            Image("StatusBarIcon")
                .renderingMode(.original)
        }
    }
}

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var statusMessage: String?

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            statusMessage = nil
        case .requiresApproval:
            isEnabled = false
            statusMessage = "Login item registration needs approval in System Settings."
        case .notFound:
            isEnabled = false
            statusMessage = "The app could not register itself as a login item."
        case .notRegistered:
            isEnabled = false
            statusMessage = nil
        @unknown default:
            isEnabled = false
            statusMessage = "Unable to determine launch-at-login status."
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
            statusMessage = error.localizedDescription
        }

        refreshStatus()
    }
}

private struct StatusBarMenuView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("显示/隐藏主窗口") {
            NotificationCenter.default.post(name: .clipDockTogglePanelRequested, object: nil)
        }

        Button("设置") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }

        Divider()

        Button("退出") {
            NSApplication.shared.terminate(nil)
        }
    }
}
