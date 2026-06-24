//
//  ClickDockApp.swift
//  ClickDock
//
//  Created by Maxcj on 2026/6/22.
//

import SwiftUI

enum WindowLayout {
    static let defaultSize = CGSize(width: 1008, height: 717)
    static let minimumSize = CGSize(width: 868, height: 602)
}

@main
struct ClickDockApp: App {
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
    }
}
