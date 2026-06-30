//
//  ContentView.swift
//  ClipDock
//
//  Created by Maxcj on 2026/6/22.
//

import SwiftUI
import CoreData
import AppKit
import Combine

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var clipboardMonitor: ClipboardMonitor
    @EnvironmentObject private var sparkleUpdateManager: SparkleUpdateManager
    @Environment(\.openWindow) private var openWindow

    @State private var searchText = ""
    @State private var categorySelection: ClipboardCategorySelection = .system(.all)
    @State private var selectedRecordID: NSManagedObjectID?
    @State private var hasConfiguredWindow = false
    @State private var windowRef: NSWindow?

    var body: some View {
        GeometryReader { proxy in
            let layout = SimpleClipboardLayout(containerSize: proxy.size)

            ZStack(alignment: .topLeading) {
                SimpleClipboardWorkspaceView(
                    searchText: $searchText,
                    categorySelection: $categorySelection,
                    selectedRecordID: $selectedRecordID,
                    containerSize: proxy.size,
                    onOpenSettings: {
                        activateAppIfNeeded()
                        openWindow(id: "settings")
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                WindowChromeOverlay(window: windowRef, layout: layout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Rectangle().fill(Color.white.opacity(0.18))
                }
            )
            .ignoresSafeArea()
        }
        .background(
            WindowAccessor { window in
                if windowRef !== window {
                    windowRef = window
                }
                guard !hasConfiguredWindow else { return }
                hasConfiguredWindow = true
                configureFloatingWindow(window)
            }
        )
        .task {
            clipboardMonitor.start()
        }
        .task {
            sparkleUpdateManager.performStartupUpdateCheckIfNeeded()
        }
        .onDisappear {
            clipboardMonitor.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipDockTogglePanelRequested)) { _ in
            toggleMainWindowVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipDockHidePanelRequested)) { _ in
            hideMainWindow()
        }
    }

    private func configureFloatingWindow(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }

        let visibleFrame = screen.visibleFrame
        let width = min(visibleFrame.width - 56, WindowLayout.defaultSize.width)
        let height = min(visibleFrame.height - 80, WindowLayout.defaultSize.height)
        let originX = visibleFrame.midX - width / 2
        let originY = visibleFrame.minY + 18
        let frame = NSRect(x: originX, y: originY, width: width, height: height)

        window.setFrame(frame, display: true, animate: false)
        window.setFrameOrigin(NSPoint(x: originX, y: originY))
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
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.animationBehavior = .utilityWindow
        window.minSize = frame.size
        window.maxSize = frame.size
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func toggleMainWindowVisibility() {
        guard let windowRef else { return }

        if windowRef.isVisible {
            windowRef.orderOut(nil)
            return
        }

        showMainWindow()
    }

    private func hideMainWindow() {
        windowRef?.orderOut(nil)
    }

    private func showMainWindow() {
        guard let windowRef else { return }

        activateAppIfNeeded()
        DispatchQueue.main.async {
            windowRef.makeKeyAndOrderFront(nil)
        }
    }

    private func activateAppIfNeeded() {
        guard !NSApp.isActive else { return }
        NSApp.activate(ignoringOtherApps: true)
    }

}
