//
//  ClipDockApp.swift
//  ClipDock
//
//  Created by Maxcj on 2026/6/22.
//

import SwiftUI
import AppKit

enum WindowLayout {
    static let defaultSize = CGSize(width: 1008, height: 717)
    static let minimumSize = CGSize(width: 868, height: 602)
}

@main
struct ClipDockApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var clipboardMonitor: ClipboardMonitor
    @StateObject private var hotkeyManager: GlobalHotkeyManager

    init() {
        let context = PersistenceController.shared.container.viewContext
        _clipboardMonitor = StateObject(wrappedValue: ClipboardMonitor(context: context))
        UserDefaults.standard.register(defaults: [
            "clipboard.hotkeyEnabled": true,
            "clipboard.hotkeyKeyCode": 49,
            "clipboard.hotkeyModifiers": Int(HotKeyConfiguration.defaultModifiers),
            "clipboard.hotkeyDisplay": HotKeyConfiguration.defaultDisplay
        ])
        _hotkeyManager = StateObject(wrappedValue: GlobalHotkeyManager())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(clipboardMonitor)
                .environmentObject(hotkeyManager)
        }
        .defaultSize(width: WindowLayout.defaultSize.width, height: WindowLayout.defaultSize.height)

        Window("Settings", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 560, height: 560)

        MenuBarExtra {
            StatusBarMenuView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        } label: {
            Image(systemName: "tray.full")
        }
    }
}

private struct StatusBarMenuView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("显示/隐藏主窗口") {
            NotificationCenter.default.post(name: .clipDockTogglePanelRequested, object: nil)
        }

        Button("设置") {
            openWindow(id: "settings")
        }

        Divider()

        Button("退出") {
            NSApplication.shared.terminate(nil)
        }
    }
}
