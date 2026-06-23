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

    init() {
        let context = PersistenceController.shared.container.viewContext
        _clipboardMonitor = StateObject(wrappedValue: ClipboardMonitor(context: context))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(clipboardMonitor)
        }
        .defaultSize(width: WindowLayout.defaultSize.width, height: WindowLayout.defaultSize.height)
    }
}
