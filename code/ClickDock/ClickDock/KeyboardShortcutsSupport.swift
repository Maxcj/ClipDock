//
//  KeyboardShortcutsSupport.swift
//  ClickDock
//

import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleMainWindow = Self(
        "toggleMainWindow",
        default: .init(.q, modifiers: [.control])
    )
}

@MainActor
final class KeyboardShortcutManager: ObservableObject {
    init() {
        KeyboardShortcuts.onKeyUp(for: .toggleMainWindow) {
            NotificationCenter.default.post(name: .clipDockTogglePanelRequested, object: nil)
        }
    }
}
